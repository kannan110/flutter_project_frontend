-- Cash Collection (Customer Ledger → Collect): Supervisor.
--
--  * ledger_entries.supervisor_id (nullable, → supervisor_profiles.id).
--  * record_payment gets p_supervisor_id (optional). When not given and the
--    payment is recorded by a supervisor's own login (supervisor app), it is
--    filled with that supervisor — so every supervisor collection carries it.
--    Run AFTER cash_collection_doc_no.sql (this replaces that 11-argument
--    version; the RPC call must not match two functions).
--  * get_supervisor_report credits a collection to ledger_entries.supervisor_id
--    when set, otherwise (older rows) to the supervisor whose login recorded
--    it — exactly as before. Patched in place (one JOIN line); stops with an
--    error if the function doesn't look as expected.

ALTER TABLE public.ledger_entries
  ADD COLUMN IF NOT EXISTS supervisor_id uuid REFERENCES public.supervisor_profiles(id);

CREATE INDEX IF NOT EXISTS ledger_entries_supervisor_id_idx
  ON public.ledger_entries (supervisor_id) WHERE supervisor_id IS NOT NULL;

DROP FUNCTION IF EXISTS public.record_payment(uuid, uuid, numeric, text, uuid, uuid, text, uuid, date, text, boolean);

CREATE OR REPLACE FUNCTION public.record_payment(p_trader_id uuid, p_retailer_id uuid, p_amount numeric, p_payment_mode text, p_invoice_id uuid DEFAULT NULL::uuid, p_order_id uuid DEFAULT NULL::uuid, p_description text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_entry_date date DEFAULT NULL::date, p_manual_doc_no text DEFAULT NULL::text, p_assign_doc_no boolean DEFAULT false, p_supervisor_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$DECLARE
  v_entry_id       uuid;
  v_outstanding    numeric;
  v_entry_date     date;
  v_doc_no         text;
  v_supervisor_id  uuid := p_supervisor_id;
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

  -- Supervisor: must belong to this trader. When not given, a payment
  -- recorded by a supervisor's own login is credited to that supervisor.
  IF v_supervisor_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM supervisor_profiles WHERE id = v_supervisor_id AND trader_id = p_trader_id) THEN
      RAISE EXCEPTION 'Supervisor not found for this trader.';
    END IF;
  ELSIF p_recorded_by IS NOT NULL THEN
    SELECT id INTO v_supervisor_id FROM supervisor_profiles
     WHERE user_id = p_recorded_by AND trader_id = p_trader_id
     LIMIT 1;
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
    doc_no, manual_doc_no, supervisor_id
  ) VALUES (
    p_trader_id, p_retailer_id, p_order_id, p_invoice_id,
    'credit', p_amount, p_payment_mode,
    'payment', p_invoice_id,
    COALESCE(p_description, 'Payment received via ' || p_payment_mode),
    v_entry_date, p_recorded_by,
    v_doc_no, NULLIF(btrim(p_manual_doc_no), ''), v_supervisor_id
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

-- Supervisor Report: use the chosen supervisor when set.
DO $patch$
DECLARE
  d text;
  v_fn regprocedure := 'public.get_supervisor_report(uuid,date,date,uuid,uuid,text)'::regprocedure;
  v_old text := 'JOIN supervisor_profiles sp ON sp.user_id = le.recorded_by AND sp.trader_id = p_trader_id';
  v_new text := 'JOIN supervisor_profiles sp ON sp.trader_id = p_trader_id'
             || ' AND (sp.id = le.supervisor_id OR (le.supervisor_id IS NULL AND sp.user_id = le.recorded_by))';
  n int;
BEGIN
  d := pg_get_functiondef(v_fn);
  IF position('sp.id = le.supervisor_id' in d) > 0 THEN
    RAISE NOTICE 'get_supervisor_report already patched';
    RETURN;
  END IF;
  n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
  IF n <> 1 THEN
    RAISE EXCEPTION 'get_supervisor_report: expected 1 match, found %', n;
  END IF;
  EXECUTE replace(d, v_old, v_new);
END
$patch$;
