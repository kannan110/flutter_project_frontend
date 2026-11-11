-- Supplier Statement: an opening balance entry (supplier_ledger reason
-- 'opening_balance') belongs in the Opening Balance line, not in the
-- period's transactions — same as the Customer Ledger (get_retailer_statement).
--  * opening_balance includes opening_balance entries up to p_to_date, even
--    when dated inside the period
--  * those entries are not listed as rows, and rows' running balance includes them
--  * period summary totals leave them out
--  * closing_balance is unchanged
CREATE OR REPLACE FUNCTION public.get_supplier_statement(p_farm_id uuid, p_from_date date, p_to_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_trader_id uuid;
  v_result    jsonb;
BEGIN
  SELECT trader_id INTO v_trader_id FROM farms WHERE id = p_farm_id;
  IF v_trader_id IS NULL THEN
    RAISE EXCEPTION 'Farm not found: %', p_farm_id;
  END IF;

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
        'farmer_name',     f.farmer_name,
        'farm_name',       f.farm_name,
        'farm_phone',      f.phone,
        'farm_location',   f.location,
        'farm_village',    f.village,
        'farm_district',   f.district,
        'farm_bank_name',  f.bank_name,
        'farm_bank_account', f.bank_account,
        'farm_bank_ifsc',  f.bank_ifsc,
        'credit_days',     f.credit_days,
        'from_date',       p_from_date,
        'to_date',         p_to_date,
        'generated_at',    now()
      )
      FROM farms f
      JOIN traders t ON t.id = f.trader_id
      WHERE f.id = p_farm_id
    ),

    'opening_balance', (
      SELECT COALESCE(
        SUM(CASE WHEN entry_type='debit' THEN amount ELSE -amount END), 0
      )
      FROM supplier_ledger
      WHERE farm_id = p_farm_id
        AND (entry_date < p_from_date
             OR (reason = 'opening_balance' AND entry_date <= p_to_date))
    ),

    'rows', (
      SELECT COALESCE(json_agg(row_to_json(s) ORDER BY s.entry_date, s.created_at), '[]'::json)
      FROM (
        SELECT
          sl.id,
          sl.entry_date,
          sl.entry_type,
          sl.reason,
          sl.amount,
          sl.payment_mode,
          sl.description,
          sl.reference_number,
          sl.purchase_entry_id,
          pe.dc_number AS ref_number,
          pe.net_weight_kg AS weight_kg,
          pe.purchase_rate_per_kg AS rate_per_kg,
          pe.bird_count AS birds,
          (
            SELECT COALESCE(SUM(
              CASE WHEN sl2.entry_type='debit' THEN sl2.amount ELSE -sl2.amount END
            ), 0)
            FROM supplier_ledger sl2
            WHERE sl2.farm_id = p_farm_id
              AND (
                sl2.entry_date < sl.entry_date
                OR (sl2.entry_date = sl.entry_date AND sl2.created_at <= sl.created_at)
                OR (sl2.reason = 'opening_balance' AND sl2.entry_date <= p_to_date)
              )
          ) AS running_balance,
          sl.created_at
        FROM supplier_ledger sl
        LEFT JOIN purchase_entries pe ON pe.id = sl.purchase_entry_id
        WHERE sl.farm_id = p_farm_id
          AND sl.entry_date BETWEEN p_from_date AND p_to_date
          AND sl.reason IS DISTINCT FROM 'opening_balance'
        ORDER BY sl.entry_date, sl.created_at
      ) s
    ),

    'summary', (
      SELECT jsonb_build_object(
        'total_purchases',  COALESCE(SUM(amount) FILTER (WHERE entry_type='debit'  AND reason='purchase'), 0),
        'total_payments',   COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND reason='payment'),  0),
        'total_debits',     COALESCE(SUM(amount) FILTER (WHERE entry_type='debit'),  0),
        'total_credits',    COALESCE(SUM(amount) FILTER (WHERE entry_type='credit'), 0),
        'cash_paid',        COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND payment_mode='cash'), 0),
        'upi_paid',         COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND payment_mode='upi'),  0),
        'bank_paid',        COALESCE(SUM(amount) FILTER (WHERE entry_type='credit' AND payment_mode='bank'), 0),
        'entry_count',      COUNT(*)
      )
      FROM supplier_ledger
      WHERE farm_id = p_farm_id
        AND entry_date BETWEEN p_from_date AND p_to_date
        AND reason IS DISTINCT FROM 'opening_balance'
    ),

    'closing_balance', (
      SELECT COALESCE(
        SUM(CASE WHEN entry_type='debit' THEN amount ELSE -amount END), 0
      )
      FROM supplier_ledger
      WHERE farm_id = p_farm_id AND entry_date <= p_to_date
    )

  ) INTO v_result;

  RETURN v_result;
END;
$function$;
