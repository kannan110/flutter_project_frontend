-- Supplier / company opening balance.
-- The app stores an opening balance as a supplier_ledger row:
--   entry_type 'debit', reason 'opening_balance', no purchase_entry_id.
-- Outstanding on the Purchase screen was computed only from purchase_entries,
-- so it now also adds the ledger entries that aren't tied to a purchase:
-- opening balances, minus payments recorded against a supplier/company
-- without a specific DC (so paying off an opening balance reduces it).

-- 1) Ledger balance not tied to any purchase entry, up to p_to_date.
--    p_farm_id NULL = whole trader (includes company-level entries).
CREATE OR REPLACE FUNCTION public.fn_supplier_untied_balance(p_trader_id uuid, p_farm_id uuid, p_to_date date DEFAULT CURRENT_DATE)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(SUM(CASE WHEN sl.entry_type = 'debit' THEN sl.amount ELSE -sl.amount END), 0)
  FROM supplier_ledger sl
  WHERE sl.trader_id = p_trader_id
    AND sl.purchase_entry_id IS NULL
    AND (p_farm_id IS NULL OR sl.farm_id = p_farm_id)
    AND sl.entry_date <= COALESCE(p_to_date, CURRENT_DATE);
$function$;

-- 2) get_supplier_dashboard: Outstanding includes the untied balance;
--    each supplier row also returns opening_balance.
CREATE OR REPLACE FUNCTION public.get_supplier_dashboard(p_trader_id uuid, p_farm_id uuid DEFAULT NULL::uuid, p_from_date date DEFAULT (CURRENT_DATE - 364), p_to_date date DEFAULT CURRENT_DATE)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_result json;
BEGIN
  SELECT json_build_object(
    -- ── Overview ────────────────────────────────────────────────────────
    'summary', (
      SELECT json_build_object(
        'total_dcs',       COUNT(*),
        'total_birds',     COALESCE(SUM(pe.bird_count), 0),
        'total_weight_kg', COALESCE(SUM(pe.net_weight_kg), 0),
        'total_amount',    COALESCE(SUM(pe.total_landed_cost), 0),
        'total_paid',      COALESCE(SUM(pe.total_paid), 0),
        'total_claims',    COALESCE(SUM(pe.claim_amount), 0),
        'outstanding',     GREATEST(0,
          COALESCE(SUM(pe.total_landed_cost),0) -
          COALESCE(SUM(pe.total_paid),0) -
          COALESCE(SUM(pe.claim_amount),0)
          + fn_supplier_untied_balance(p_trader_id, p_farm_id, p_to_date)),
        'avg_rate_per_kg', CASE WHEN COALESCE(SUM(pe.net_weight_kg),0) > 0
          THEN ROUND(COALESCE(SUM(pe.base_purchase_amount),0) / SUM(pe.net_weight_kg), 4)
          ELSE NULL END,
        'overdue_count',   COUNT(*) FILTER (WHERE pe.payment_status = 'overdue'),
        'pending_rate',    COUNT(*) FILTER (WHERE pe.status = 'draft')
      )
      FROM purchase_entries pe
      WHERE pe.trader_id = p_trader_id
        AND (p_farm_id IS NULL OR pe.farm_id = p_farm_id)
        AND pe.dc_date BETWEEN p_from_date AND p_to_date
    ),

    -- ── Farms / Suppliers breakdown ──────────────────────────────────────
    'farms', (
      SELECT COALESCE(json_agg(row_to_json(fd)), '[]'::json) FROM (
        SELECT
          f.id, f.farmer_name, f.farm_name, f.phone, f.location,
          f.credit_days, f.default_rate_per_kg,
          pc.company_name,
          COUNT(pe.id)                               AS dc_count,
          COALESCE(SUM(pe.net_weight_kg), 0)         AS total_kg,
          COALESCE(SUM(pe.total_landed_cost), 0)     AS total_amount,
          COALESCE(SUM(pe.total_paid), 0)            AS paid,
          GREATEST(0, COALESCE(SUM(pe.total_landed_cost),0)
            - COALESCE(SUM(pe.total_paid),0)
            - COALESCE(SUM(pe.claim_amount),0)
            + fn_supplier_untied_balance(p_trader_id, f.id, p_to_date)) AS outstanding,
          (SELECT COALESCE(SUM(ob.amount), 0) FROM supplier_ledger ob
            WHERE ob.trader_id = p_trader_id AND ob.farm_id = f.id
              AND ob.reason = 'opening_balance')   AS opening_balance,
          MAX(pe.dc_date)                            AS last_dc_date,
          MIN(pe.payment_due_date)
            FILTER (WHERE pe.payment_status != 'paid') AS earliest_due
        FROM farms f
        LEFT JOIN poultry_companies pc ON pc.id = f.company_id
        LEFT JOIN purchase_entries pe ON pe.farm_id = f.id
          AND pe.trader_id = p_trader_id
          AND pe.dc_date BETWEEN p_from_date AND p_to_date
        WHERE f.trader_id = p_trader_id
          AND f.is_active = true
          AND (p_farm_id IS NULL OR f.id = p_farm_id)
        GROUP BY f.id, f.farmer_name, f.farm_name, f.phone, f.location,
          f.credit_days, f.default_rate_per_kg, pc.company_name
        ORDER BY total_amount DESC
      ) fd
    ),

    -- ── Recent payments ──────────────────────────────────────────────────
    'recent_payments', (
      SELECT COALESCE(json_agg(row_to_json(rp)), '[]'::json) FROM (
        SELECT
          pp.id, pp.payment_date, pp.amount, pp.payment_mode,
          pp.reference_number, pp.status, pp.notes,
          pe.dc_number, pe.farmer_name,
          f.farmer_name AS farm_farmer_name
        FROM purchase_payments pp
        JOIN purchase_entries pe ON pe.id = pp.purchase_entry_id
        LEFT JOIN farms f ON f.id = pp.farm_id
        WHERE pp.trader_id = p_trader_id
          AND (p_farm_id IS NULL OR pp.farm_id = p_farm_id)
          AND pp.payment_date BETWEEN p_from_date AND p_to_date
          AND pp.status = 'active'
        ORDER BY pp.payment_date DESC, pp.created_at DESC
        LIMIT 20
      ) rp
    ),

    -- ── Monthly trend (last 6 months) ────────────────────────────────────
    'monthly_trend', (
      SELECT COALESCE(json_agg(row_to_json(mt) ORDER BY mt.month), '[]'::json) FROM (
        SELECT
          DATE_TRUNC('month', pe.dc_date)::date  AS month,
          COUNT(*)                               AS dc_count,
          COALESCE(SUM(pe.net_weight_kg), 0)     AS total_kg,
          COALESCE(SUM(pe.total_landed_cost), 0) AS total_amount,
          COALESCE(SUM(pe.total_paid), 0)        AS paid
        FROM purchase_entries pe
        WHERE pe.trader_id = p_trader_id
          AND (p_farm_id IS NULL OR pe.farm_id = p_farm_id)
          AND pe.dc_date >= CURRENT_DATE - 180
        GROUP BY DATE_TRUNC('month', pe.dc_date)
        ORDER BY month
      ) mt
    ),

    -- ── Profitability from batch_costing ────────────────────────────────
    'profitability', (
      SELECT json_build_object(
        'total_revenue',   COALESCE(SUM(bc.revenue), 0),
        'total_cost',      COALESCE(SUM(bc.total_cost), 0),
        'gross_profit',    COALESCE(SUM(bc.gross_profit), 0),
        'net_profit',      COALESCE(SUM(bc.net_profit), 0),
        'avg_margin_pct',  CASE WHEN COALESCE(SUM(bc.revenue), 0) > 0
          THEN ROUND(COALESCE(SUM(bc.net_profit),0) / SUM(bc.revenue) * 100, 2)
          ELSE NULL END
      )
      FROM batch_costing bc
      JOIN purchase_entries pe ON pe.batch_id = bc.batch_id
      WHERE bc.trader_id = p_trader_id
        AND (p_farm_id IS NULL OR pe.farm_id = p_farm_id)
    ),

    'from_date', p_from_date,
    'to_date',   p_to_date
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- 3) get_purchase_summary: total and per-supplier Outstanding include the
--    untied balance (rows without a farm get none of it).
CREATE OR REPLACE FUNCTION public.get_purchase_summary(p_trader_id uuid, p_from_date date DEFAULT (CURRENT_DATE - 29), p_to_date date DEFAULT CURRENT_DATE)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_result json;
BEGIN
  PERFORM refresh_overdue_payments(p_trader_id);

  SELECT json_build_object(
    'total_dcs',         COUNT(*),
    'total_birds',       COALESCE(SUM(pe.bird_count), 0),
    'total_weight_kg',   COALESCE(SUM(pe.net_weight_kg), 0),
    'total_purchase_amt',COALESCE(SUM(pe.total_landed_cost), 0),
    'total_paid',        COALESCE(SUM(pe.total_paid), 0),
    'total_claim',       COALESCE(SUM(pe.claim_amount), 0),
    'total_outstanding', GREATEST(0,
      COALESCE(SUM(pe.total_landed_cost), 0)
      - COALESCE(SUM(pe.total_paid),      0)
      - COALESCE(SUM(pe.claim_amount),    0)
      + fn_supplier_untied_balance(p_trader_id, NULL, p_to_date)),
    'pending_rate',      COUNT(*) FILTER (WHERE pe.status = 'draft'),
    'confirmed',         COUNT(*) FILTER (WHERE pe.status = 'confirmed'),
    'overdue_count',     COUNT(*) FILTER (WHERE pe.payment_status = 'overdue'),
    'avg_cost_per_kg',   CASE WHEN COALESCE(SUM(pe.net_weight_kg), 0) > 0
                              THEN ROUND(COALESCE(SUM(pe.total_landed_cost), 0) / SUM(pe.net_weight_kg), 4)
                              ELSE NULL END,
    'farm_breakdown', (
      SELECT COALESCE(json_agg(row_to_json(fb)), '[]'::json) FROM (
        SELECT
          COALESCE(f.farmer_name, pe2.farmer_name, '—') AS farm_name,
          f.id                                           AS farm_id,
          COUNT(pe2.id)                                  AS dc_count,
          COALESCE(SUM(pe2.net_weight_kg), 0)            AS total_kg,
          COALESCE(SUM(pe2.total_landed_cost), 0)        AS total_amount,
          COALESCE(SUM(pe2.total_paid), 0)               AS paid,
          COALESCE(SUM(pe2.claim_amount), 0)             AS claims,
          GREATEST(0,
            COALESCE(SUM(pe2.total_landed_cost), 0)
            - COALESCE(SUM(pe2.total_paid),      0)
            - COALESCE(SUM(pe2.claim_amount),    0)
            + CASE WHEN f.id IS NULL THEN 0
                   ELSE fn_supplier_untied_balance(p_trader_id, f.id, p_to_date) END) AS outstanding,
          COUNT(*) FILTER (WHERE pe2.payment_status = 'overdue') AS overdue_count,
          MIN(pe2.payment_due_date)
            FILTER (WHERE pe2.payment_status NOT IN ('paid')) AS earliest_due
        FROM purchase_entries pe2
        LEFT JOIN delivery_batches db2 ON db2.id = pe2.batch_id
        LEFT JOIN farms f ON f.id = pe2.farm_id
        WHERE pe2.trader_id = p_trader_id
          AND pe2.dc_date BETWEEN p_from_date AND p_to_date
          AND (db2.id IS NULL OR db2.status <> 'cancelled')
        GROUP BY pe2.farm_id, f.id, f.farmer_name, pe2.farmer_name
        ORDER BY total_amount DESC
        LIMIT 20
      ) fb
    ),
    'from_date', p_from_date,
    'to_date',   p_to_date
  ) INTO v_result
  FROM purchase_entries pe
  LEFT JOIN delivery_batches db ON db.id = pe.batch_id
  WHERE pe.trader_id = p_trader_id
    AND pe.dc_date BETWEEN p_from_date AND p_to_date
    AND (db.id IS NULL OR db.status <> 'cancelled');

  RETURN v_result;
END;
$function$;
