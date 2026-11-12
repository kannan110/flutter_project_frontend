-- Cash Collection (Customer Ledger → Collect): Doc No (auto) + Man. Doc No.
--
--  * ledger_entries.doc_no / manual_doc_no (new, nullable). Unique per trader.
--  * Doc No format CSH-YYYYMM-XXXXX: YYYYMM from the payment's Business Date,
--    XXXXX = running number per trader that restarts at 00001 each calendar
--    year (e.g. CSH-202612-00418 → CSH-202701-00001).
--  * record_payment gets p_manual_doc_no and p_assign_doc_no (both optional,
--    default off), so every other caller (Stock Point Sale, supervisor app,
--    edits/reversals) is unchanged. The old 9-argument version is dropped
--    first so the RPC call can't match two functions.
--  * Also fixes record_payment's overpayment alert, which inserted into a
--    non-existent column (alerts.p_trader_id) and made any payment that left
--    the customer in credit fail.

ALTER TABLE public.ledger_entries
  ADD COLUMN IF NOT EXISTS doc_no text,
  ADD COLUMN IF NOT EXISTS manual_doc_no text;

CREATE UNIQUE INDEX IF NOT EXISTS ledger_entries_trader_doc_no_uq
  ON public.ledger_entries (trader_id, doc_no)
  WHERE doc_no IS NOT NULL;

-- Next CSH number for this trader in p_date's year.
CREATE OR REPLACE FUNCTION public.fn_next_cash_doc_no(p_trader_id uuid, p_date date)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT 'CSH-' || to_char(p_date, 'YYYYMM') || '-' ||
         lpad((COALESCE(max(substring(doc_no FROM 12)::int), 0) + 1)::text, 5, '0')
  FROM ledger_entries
  WHERE trader_id = p_trader_id
    AND doc_no LIKE 'CSH-' || to_char(p_date, 'YYYY') || '%'
    AND substring(doc_no FROM 12) ~ '^[0-9]+$';
$function$;

-- Shown in the Collect Payment sheet before saving (same pattern as
-- preview_quick_entry_doc_no). The real number is assigned on save.
CREATE OR REPLACE FUNCTION public.preview_cash_collection_doc_no(p_trader_id uuid, p_date date DEFAULT CURRENT_DATE)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid() AND trader_id = p_trader_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Access denied.';
  END IF;
  RETURN fn_next_cash_doc_no(p_trader_id, COALESCE(p_date, CURRENT_DATE));
END;
$function$;

DROP FUNCTION IF EXISTS public.record_payment(uuid, uuid, numeric, text, uuid, uuid, text, uuid, date);

CREATE OR REPLACE FUNCTION public.record_payment(p_trader_id uuid, p_retailer_id uuid, p_amount numeric, p_payment_mode text, p_invoice_id uuid DEFAULT NULL::uuid, p_order_id uuid DEFAULT NULL::uuid, p_description text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_entry_date date DEFAULT NULL::date, p_manual_doc_no text DEFAULT NULL::text, p_assign_doc_no boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$DECLARE
  v_entry_id       uuid;
  v_outstanding    numeric;
  v_entry_date     date;
  v_doc_no         text;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be > 0. Got: %', p_amount;
  END IF;
  IF p_payment_mode NOT IN ('cash','upi','bank','adjustment') THEN
    RAISE EXCEPTION 'Invalid payment mode: %', p_payment_mode;
  END IF;

  v_entry_date := COALESCE(p_entry_date, CURRENT_DATE);
  IF v_entry_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'Business Date cannot be in the future: %', v_entry_date;
  END IF;

  -- Cash Collection Doc No (CSH-YYYYMM-XXXXX, restarts every year).
  IF p_assign_doc_no THEN
    PERFORM pg_advisory_xact_lock(hashtext('cash_doc_no:' || p_trader_id::text));
    v_doc_no := fn_next_cash_doc_no(p_trader_id, v_entry_date);
  END IF;

  INSERT INTO ledger_entries(
    trader_id, retailer_id, order_id, invoice_id,
    entry_type, amount, payment_mode,
    source_type, source_id,
    description, entry_date, recorded_by,
    doc_no, manual_doc_no
  ) VALUES (
    p_trader_id, p_retailer_id, p_order_id, p_invoice_id,
    'credit', p_amount, p_payment_mode,
    'payment', p_invoice_id,
    COALESCE(p_description, 'Payment received via ' || p_payment_mode),
    v_entry_date, p_recorded_by,
    v_doc_no, NULLIF(btrim(p_manual_doc_no), '')
  ) RETURNING id INTO v_entry_id;

  IF p_invoice_id IS NOT NULL THEN
    UPDATE invoices SET
      collected_amount = COALESCE(collected_amount, 0) + p_amount,
      balance_amount   = GREATEST(0, COALESCE(total_amount, 0) - (COALESCE(collected_amount, 0) + p_amount))
    WHERE id = p_invoice_id;
  END IF;

  SELECT get_retailer_outstanding(p_retailer_id) INTO v_outstanding;
  IF v_outstanding < 0 THEN
    INSERT INTO alerts(trader_id, alert_type, severity, title, message, reference_type, reference_id)
    SELECT p_trader_id, 'payment_overdue', 'info',
      'Overpayment Recorded',
      'Retailer has a credit balance of ₹' || ABS(v_outstanding)::text || ' — carry forward or refund.',
      'ledger_entries', v_entry_id
    WHERE NOT EXISTS (
      SELECT 1 FROM alerts WHERE trader_id=p_trader_id AND reference_id=v_entry_id
    );
  END IF;

  UPDATE retailers SET last_payment_date = GREATEST(COALESCE(last_payment_date, v_entry_date), v_entry_date)
  WHERE id = p_retailer_id;

  RETURN v_entry_id;
END;$function$;
