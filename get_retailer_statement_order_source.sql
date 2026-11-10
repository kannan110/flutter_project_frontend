CREATE OR REPLACE FUNCTION public.get_retailer_statement(p_retailer_id uuid, p_from_date date DEFAULT (CURRENT_DATE - 29), p_to_date date DEFAULT CURRENT_DATE, p_agent_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_trader_id uuid;
  v_result    jsonb;
BEGIN
  SELECT trader_id INTO v_trader_id FROM retailers WHERE id = p_retailer_id;
  IF v_trader_id IS NULL THEN
    RAISE EXCEPTION 'Retailer not found: %', p_retailer_id;
  END IF;

  WITH effective_ledger AS (
    SELECT le.*
    FROM ledger_entries le
    LEFT JOIN invoices inv ON inv.id = le.invoice_id
    WHERE le.retailer_id = p_retailer_id
      AND le.source_type NOT IN ('invoice_cancellation', 'payment_reversal')
      AND NOT (le.source_type = 'invoice' AND inv.status = 'cancelled')
      AND NOT (le.source_type = 'payment' AND le.invoice_id IS NOT NULL AND inv.status = 'cancelled')
      AND NOT EXISTS (
        SELECT 1 FROM retailer_payment_audit_log rpal
        WHERE rpal.original_entry_id = le.id OR rpal.reversal_entry_id = le.id
      )
  )
  SELECT jsonb_build_object(

    'header', (
      SELECT jsonb_build_object(
        'company_name',    t.company_name,
        'company_phone',   t.phone,
        'company_address', t.address,
        'company_city',    t.city,
        'company_gst',     t.gst_number,
        'company_fssai',   t.fssai_number,
        'company_logo',    t.logo_url,
        'company_email',   t.email,
        'retailer_name',   r.shop_name,
        'retailer_owner',  r.owner_name,
        'retailer_phone',  r.phone,
        'retailer_address',r.address,
        'retailer_city',   r.city,
        'retailer_gst',    r.gst_number,
        'retailer_area',   a.area_name,
        'from_date',       p_from_date,
        'to_date',         p_to_date,
        'generated_at',    now()
      )
      FROM retailers r
      JOIN traders t ON t.id = r.trader_id
      LEFT JOIN areas a ON a.id = r.area_id
      WHERE r.id = p_retailer_id
    ),

    'opening_balance', (
      SELECT COALESCE(
        SUM(CASE WHEN entry_type='debit' THEN amount ELSE -amount END), 0
      )
      FROM effective_ledger el
      WHERE el.entry_date < p_from_date
         OR (el.source_type = 'opening_balance' AND el.entry_date <= p_to_date)
    ),

    'rows', (
      SELECT COALESCE(json_agg(row_to_json(s) ORDER BY s.entry_date, s.created_at), '[]'::json)
      FROM (
        SELECT
          el.id,
          el.entry_date,
          el.entry_type,
          el.source_type,
          el.amount,
          el.payment_mode,
          el.description,
          el.invoice_id,
          el.order_id,
          ord.remarks AS order_remarks,
          ord.doc_no, ord.manual_doc_no,  -- NEW
          ord.source AS order_source,  -- 'in_house' = Stock Point sale
          CASE
            WHEN el.source_type = 'invoice'         THEN i.invoice_number
            WHEN el.source_type = 'credit_note'     THEN cn.credit_number
            WHEN el.source_type = 'return'          THEN rcn.credit_number
            ELSE NULL
          END AS ref_number,
          COALESCE(i.invoice_date, el.entry_date) AS ref_date,
          CASE WHEN el.source_type = 'return' THEN rte.weight_kg ELSE i.quantity_kg  END AS weight_kg,
          CASE WHEN el.source_type = 'return' THEN rcn.rate_per_kg ELSE i.price_per_kg END AS rate_per_kg,
          CASE WHEN el.source_type = 'return' THEN rte.bird_count ELSE i.bird_count   END AS birds,
          rmp.name AS return_product_name,
          rte.reason AS return_reason,
          (
            SELECT jsonb_agg(jsonb_build_object(
              'product_name',    mp.name,
              'weight_kg',       ii.weight_kg,
              'bird_count',      ii.bird_count,
              'applied_rate',    ii.applied_rate,
              'base_rate',       ii.base_rate,
              'adjustment_type', ii.adjustment_type,
              'adjustment_value',ii.adjustment_value,
              'rate_zone_name',  ii.rate_zone_name,
              'rate_source',     ii.rate_source,
              'line_total',      ii.line_total
            ) ORDER BY mp.sort_order)
            FROM invoice_items ii
            JOIN master_products mp ON mp.id = ii.product_id
            WHERE ii.invoice_id = el.invoice_id
          ) AS rate_breakdown,
          (
            SELECT COALESCE(SUM(
              CASE WHEN el2.entry_type='debit' THEN el2.amount ELSE -el2.amount END
            ), 0)
            FROM effective_ledger el2
            WHERE el2.entry_date < el.entry_date
               OR (el2.entry_date = el.entry_date AND el2.created_at <= el.created_at)
          ) AS running_balance,
          COALESCE(
            (SELECT d.delivery_agent_id FROM invoices i2
               JOIN deliveries d ON d.id = i2.delivery_id
              WHERE i2.id = el.invoice_id),
            (CASE WHEN el.source_type = 'return' THEN rte.agent_id END),
            (SELECT d2.delivery_agent_id FROM deliveries d2
              WHERE d2.order_id = el.order_id
              ORDER BY d2.created_at LIMIT 1)
          ) AS resolved_agent_id,
          el.created_at
        FROM effective_ledger el
        LEFT JOIN invoices       i   ON i.id  = el.invoice_id
        LEFT JOIN credit_notes   cn  ON cn.id = el.source_id AND el.source_type = 'credit_note'
        LEFT JOIN return_entries rte ON rte.id = el.source_id AND el.source_type = 'return'
        LEFT JOIN credit_notes   rcn ON rcn.return_id = rte.id
        LEFT JOIN master_products rmp ON rmp.id = rte.product_id
        LEFT JOIN orders ord ON ord.id = el.order_id
        WHERE el.entry_date BETWEEN p_from_date AND p_to_date
          AND el.source_type <> 'opening_balance'

        UNION ALL

        SELECT
          d.id,
          g.entry_date,
          CASE WHEN g.net_amount >= 0 THEN 'debit' ELSE 'credit' END AS entry_type,
          'opening_balance' AS source_type,
          ABS(g.net_amount) AS amount,
          NULL::text AS payment_mode,
          d.description,
          NULL::uuid AS invoice_id,
          NULL::uuid AS order_id,
          NULL::text AS order_remarks,
          NULL::text AS doc_no, NULL::text AS manual_doc_no,  -- NEW
          NULL::text AS order_source,
          'OB' AS ref_number,
          g.entry_date AS ref_date,
          NULL::numeric AS weight_kg,
          NULL::numeric AS rate_per_kg,
          NULL::integer AS birds,
          NULL::text AS return_product_name,
          NULL::text AS return_reason,
          NULL::jsonb AS rate_breakdown,
          (
            SELECT COALESCE(SUM(
              CASE WHEN el2.entry_type='debit' THEN el2.amount ELSE -el2.amount END
            ), 0)
            FROM effective_ledger el2
            WHERE el2.entry_date < g.entry_date
               OR (el2.entry_date = g.entry_date AND el2.created_at <= d.created_at)
          ) AS running_balance,
          NULL::uuid AS resolved_agent_id,
          d.created_at
        FROM (
          SELECT el.entry_date,
                 SUM(CASE WHEN el.entry_type='debit' THEN el.amount ELSE -el.amount END) AS net_amount
          FROM effective_ledger el
          WHERE el.source_type = 'opening_balance'
            AND el.entry_date BETWEEN p_from_date AND p_to_date
          GROUP BY el.entry_date
        ) g
        JOIN LATERAL (
          SELECT el.id, el.description, el.created_at
          FROM effective_ledger el
          WHERE el.source_type = 'opening_balance'
            AND el.entry_date = g.entry_date
          ORDER BY el.created_at DESC, el.id DESC
          LIMIT 1
        ) d ON true
      ) s
      WHERE (p_agent_id IS NULL OR s.resolved_agent_id = p_agent_id)
    ),

    'summary', (
      SELECT jsonb_build_object(
        'total_invoiced',     COALESCE(SUM(amount) FILTER (WHERE entry_type='debit'  AND source_type='invoice'), 0),
        'total_collections',  COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND source_type IN ('delivery','payment')), 0),
        'total_credit_notes', COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND source_type='credit_note'), 0),
        'total_debits',       COALESCE(SUM(amount) FILTER (WHERE entry_type='debit'), 0),
        'total_credits',      COALESCE(SUM(amount) FILTER (WHERE entry_type='credit'), 0),
        'cash_collected',     COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND payment_mode='cash'), 0),
        'upi_collected',      COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND payment_mode='upi'), 0),
        'bank_collected',     COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND payment_mode='bank'), 0),
        'credit_collected',   COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND payment_mode='credit'), 0),
        'entry_count',        COUNT(*),
        'total_birds',        (SELECT COALESCE(SUM(i2.bird_count), 0)
                                FROM effective_ledger el2
                                JOIN invoices i2 ON i2.id = el2.invoice_id
                                WHERE el2.entry_date BETWEEN p_from_date AND p_to_date
                                  AND el2.source_type = 'invoice'),
        'total_weight_kg',    (SELECT COALESCE(SUM(i2.quantity_kg), 0)
                                FROM effective_ledger el2
                                JOIN invoices i2 ON i2.id = el2.invoice_id
                                WHERE el2.entry_date BETWEEN p_from_date AND p_to_date
                                  AND el2.source_type = 'invoice')
      )
      FROM effective_ledger
      WHERE entry_date BETWEEN p_from_date AND p_to_date
    ),

    'closing_balance', (
      SELECT COALESCE(
        SUM(CASE WHEN entry_type='debit' THEN amount ELSE -amount END), 0
      )
      FROM effective_ledger
      WHERE entry_date <= p_to_date
    )

  ) INTO v_result;

  RETURN v_result;
END;
$function$;
