-- Cash Collection Edit / Remove fixes. Run after collection_supervisor.sql.
--
-- 1. get_supervisor_report: a collection that was removed or edited (its id is
--    an original_entry_id in retailer_payment_audit_log) is no longer counted
--    — same rule the Customer Ledger, Collection report and statement already
--    use. Patched in place; stops if the function doesn't look as expected.
--
-- 2. edit_collection: restored. The live version had lost both ledger inserts
--    (the reversal debit and the corrected credit) and the step that adds the
--    corrected amount back to the invoice, so an edit would hide the original
--    collection, create nothing in its place, and lower the invoice's collected
--    amount. This is the original version (migration create_edit_collection_rpc)
--    plus: the corrected entry keeps the original's supervisor and Man. Doc No,
--    and gets a new CSH Doc No when the original had one.

DO $patch$
DECLARE
  d text;
  v_fn regprocedure := 'public.get_supervisor_report(uuid,date,date,uuid,uuid,text)'::regprocedure;
  v_old text := 'AND le.entry_type = ''credit'' AND le.source_type = ''payment''';
  v_new text := 'AND le.entry_type = ''credit'' AND le.source_type = ''payment'''
             || ' AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le.id)';
  n int;
BEGIN
  d := pg_get_functiondef(v_fn);
  IF position('rpal.original_entry_id = le.id' in d) > 0 THEN
    RAISE NOTICE 'get_supervisor_report already excludes removed/edited collections';
    RETURN;
  END IF;
  n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
  IF n <> 1 THEN
    RAISE EXCEPTION 'get_supervisor_report: expected 1 match, found %', n;
  END IF;
  EXECUTE replace(d, v_old, v_new);
END
$patch$;

CREATE OR REPLACE FUNCTION public.edit_collection(p_entry_id uuid, p_new_amount numeric, p_new_entry_date date, p_new_payment_mode text, p_new_description text DEFAULT NULL::text, p_edited_by uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_entry            ledger_entries%rowtype;
  v_reversal_id      uuid;
  v_new_id           uuid;
  v_already_reversed boolean;
  v_doc_no           text;
BEGIN
  -- Edit = reverse the original in full (exactly like reverse_collection)
  -- + insert a brand-new corrected credit entry, atomically. The original
  -- row is never touched; both the reversal and the replacement carry
  -- their own audit trail via retailer_payment_audit_log.
  IF p_new_amount IS NULL OR p_new_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero.';
  END IF;

  IF p_new_entry_date IS NULL OR p_new_entry_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'Business date cannot be in the future.';
  END IF;

  IF p_new_payment_mode NOT IN ('cash','upi','bank','adjustment') THEN
    RAISE EXCEPTION 'Invalid payment mode: %', p_new_payment_mode;
  END IF;

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason is required to edit a collection.';
  END IF;

  SELECT * INTO v_entry FROM ledger_entries WHERE id = p_entry_id;
  IF v_entry.id IS NULL THEN
    RAISE EXCEPTION 'Ledger entry not found: %', p_entry_id;
  END IF;

  IF v_entry.entry_type <> 'credit' OR v_entry.source_type <> 'payment' THEN
    RAISE EXCEPTION 'Only a recorded payment (credit/payment) can be edited.';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM retailer_payment_audit_log WHERE original_entry_id = p_entry_id
  ) INTO v_already_reversed;
  IF v_already_reversed THEN
    RAISE EXCEPTION 'This collection has already been reversed/edited.';
  END IF;

  -- Step 1: reverse the original (same mechanics as reverse_collection)
  INSERT INTO ledger_entries(
    trader_id, retailer_id, order_id, invoice_id,
    entry_type, amount, payment_mode,
    source_type, source_id,
    description, entry_date, recorded_by
  ) VALUES (
    v_entry.trader_id, v_entry.retailer_id, v_entry.order_id, v_entry.invoice_id,
    'debit', v_entry.amount, v_entry.payment_mode,
    'payment_reversal', v_entry.id,
    'Reversal of collection dated ' || v_entry.entry_date || ' (₹' ||
      to_char(v_entry.amount, 'FM999999999.00') || ' via ' || v_entry.payment_mode ||
      ') for correction. Reason: ' || p_reason,
    CURRENT_DATE, p_edited_by
  ) RETURNING id INTO v_reversal_id;

  IF v_entry.invoice_id IS NOT NULL THEN
    UPDATE invoices SET
      collected_amount = GREATEST(0, COALESCE(collected_amount, 0) - v_entry.amount),
      balance_amount   = COALESCE(total_amount, 0) - GREATEST(0, COALESCE(collected_amount, 0) - v_entry.amount)
    WHERE id = v_entry.invoice_id;
  END IF;

  -- Corrected entry keeps a CSH Doc No when the original had one (a new
  -- number — the original keeps its own).
  IF v_entry.doc_no IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cash_doc_no:' || v_entry.trader_id::text));
    v_doc_no := fn_next_cash_doc_no(v_entry.trader_id, p_new_entry_date);
  END IF;

  -- Step 2: insert the corrected replacement collection (mirrors
  -- record_payment's own insert + invoice bump, so behaves identically
  -- to a fresh Collect Cash entry with the corrected values).
  INSERT INTO ledger_entries(
    trader_id, retailer_id, order_id, invoice_id,
    entry_type, amount, payment_mode,
    source_type, source_id,
    description, entry_date, recorded_by,
    doc_no, manual_doc_no, supervisor_id
  ) VALUES (
    v_entry.trader_id, v_entry.retailer_id, v_entry.order_id, v_entry.invoice_id,
    'credit', p_new_amount, p_new_payment_mode,
    'payment', v_entry.id,
    COALESCE(p_new_description, 'Corrected payment via ' || p_new_payment_mode),
    p_new_entry_date, p_edited_by,
    v_doc_no, v_entry.manual_doc_no, v_entry.supervisor_id
  ) RETURNING id INTO v_new_id;

  IF v_entry.invoice_id IS NOT NULL THEN
    UPDATE invoices SET
      collected_amount = COALESCE(collected_amount, 0) + p_new_amount,
      balance_amount   = GREATEST(0, COALESCE(total_amount, 0) - (COALESCE(collected_amount, 0) + p_new_amount))
    WHERE id = v_entry.invoice_id;
  END IF;

  UPDATE retailers SET last_payment_date = GREATEST(COALESCE(last_payment_date, p_new_entry_date), p_new_entry_date)
  WHERE id = v_entry.retailer_id;

  INSERT INTO retailer_payment_audit_log(
    original_entry_id, reversal_entry_id, new_entry_id, trader_id, retailer_id,
    action, reason, actor_id, old_values, new_values
  ) VALUES (
    v_entry.id, v_reversal_id, v_new_id, v_entry.trader_id, v_entry.retailer_id,
    'edit', p_reason, p_edited_by,
    jsonb_build_object(
      'amount', v_entry.amount, 'payment_mode', v_entry.payment_mode,
      'entry_date', v_entry.entry_date, 'description', v_entry.description
    ),
    jsonb_build_object(
      'amount', p_new_amount, 'payment_mode', p_new_payment_mode,
      'entry_date', p_new_entry_date, 'description', p_new_description
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'original_entry_id', v_entry.id,
    'reversal_entry_id', v_reversal_id,
    'new_entry_id', v_new_id
  );
END;
$function$;
