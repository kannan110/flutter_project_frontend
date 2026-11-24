-- DCs with the same DC number on one batch ("double entry").
--
-- 1. add_batch_dc / pickup_batch skipped the stock entry when ANY stock row
--    on the batch already mentioned the DC number (meant to stop a repeat),
--    so a second DC with the same number — or a DC re-added after its first
--    copy was deleted, or "12" when "123" exists — was saved with no birds /
--    kg in stock. Now only a row written by this same call counts, so every
--    DC gets its own stock entry.
--
-- 2. delete_batch_dc refused to delete a DC when another DC on the batch had
--    the same number, so the duplicate always stayed in the list. Now it
--    deletes just that DC: its own stock rows are the ones written in the
--    same transaction as the DC (same created_at), so only that DC's birds /
--    kg are reversed, plus its own purchase entry. A duplicate that never got
--    stock (bug 1) is deleted with nothing to reverse. Older DCs whose stock
--    row was written separately still fall back to the DC number in the
--    notes, but only when the number is unique on the batch, and skipping
--    rows of DCs with that number that were already deleted.
--
-- Patched in place; each patch stops with an error if the function doesn't
-- look as expected. Safe to run twice.

-- ── 1. add_batch_dc and pickup_batch ──────────────────────────────────────
DO $patch$
DECLARE
  d text;
  f text;
  v_old text;
  v_new text;
  n int;
BEGIN
  FOREACH f IN ARRAY ARRAY['add_batch_dc', 'pickup_batch'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p
     WHERE p.proname = f AND p.pronamespace = 'public'::regnamespace;
    IF position('-- only this call''s own stock row counts' in d) > 0 THEN
      RAISE NOTICE '% already patched', f;
      CONTINUE;
    END IF;
    v_old := CASE f
      WHEN 'add_batch_dc' THEN E'          AND notes LIKE ''%'' || p_dc_number || ''%''\n'
      ELSE E'                  AND notes LIKE ''%'' || p_dc_number || ''%''\n' END;
    v_new := v_old || CASE f
      WHEN 'add_batch_dc' THEN E'          AND created_at = now() -- only this call''s own stock row counts\n'
      ELSE E'                  AND created_at = now() -- only this call''s own stock row counts\n' END;
    n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '%: expected 1 match for the stock check, found %', f, n;
    END IF;
    EXECUTE replace(d, v_old, v_new);
  END LOOP;
END
$patch$;

-- ── 2. delete_batch_dc ────────────────────────────────────────────────────
DO $patch$
DECLARE
  d text;
  v_fn regprocedure;
  r text[][];
  i int;
  n int;
BEGIN
  SELECT oid::regprocedure INTO v_fn FROM pg_proc
   WHERE proname = 'delete_batch_dc' AND pronamespace = 'public'::regnamespace;
  d := pg_get_functiondef(v_fn);
  IF position('v_dup' in d) > 0 THEN
    RAISE NOTICE 'delete_batch_dc already patched';
    RETURN;
  END IF;

  r := ARRAY[
    -- a) variables
    ARRAY[E'  v_note_prefixes text[];\n',
          E'  v_note_prefixes text[];\n  v_dup          boolean;\n  v_any_note     boolean;\n'],
    -- b) same-number DCs no longer block the delete
    ARRAY[E'  IF EXISTS (\n    SELECT 1 FROM delivery_challans\n    WHERE batch_id = v_dc.batch_id AND id <> v_dc.id AND dc_number = v_dc.dc_number\n  ) THEN\n    RAISE EXCEPTION ''Cannot delete DC %: another DC on this batch has the same number.'', v_dc.dc_number;\n  END IF;\n',
          E'  -- Another DC on this batch with the same number: only this DC''s own\n  -- stock rows (written in the same transaction as the DC) are reversed.\n  v_dup := EXISTS (\n    SELECT 1 FROM delivery_challans\n    WHERE batch_id = v_dc.batch_id AND id <> v_dc.id AND dc_number = v_dc.dc_number\n  );\n'],
    -- c) a DC's own batch stock rows: same transaction as the DC
    ARRAY[E'          AND sl.movement_type IN (''purchased'',''returned_in'')\n          AND EXISTS (\n',
          E'          AND sl.movement_type IN (''purchased'',''returned_in'')\n          AND sl.created_at = v_dc.created_at\n          AND EXISTS (\n'],
    -- d) fallback for older DCs + count
    ARRAY[E'  SELECT count(*), COALESCE(sum(quantity_birds), 0), COALESCE(sum(quantity_kg), 0)\n  INTO v_ledger_cnt, v_rev_birds, v_rev_kg FROM _dc_rows;\n',
          E'  -- Any stock row mentioning this DC number on the batch at all?\n  v_any_note := EXISTS (\n    SELECT 1 FROM stock_ledger sl\n    WHERE sl.trader_id = v_dc.trader_id\n      AND sl.reference_type = ''batch'' AND sl.reference_id = v_dc.batch_id\n      AND sl.movement_type IN (''purchased'',''returned_in'')\n      AND EXISTS (SELECT 1 FROM unnest(v_note_prefixes) p\n                  WHERE sl.notes = p OR left(sl.notes, length(p) + 3) = p || '' — ''));\n\n  -- Older DCs whose stock row was written separately: fall back to the DC\n  -- number in the notes — only when no other DC on the batch has this\n  -- number, skipping rows of DCs with this number that were already deleted.\n  IF NOT v_dup AND NOT EXISTS (SELECT 1 FROM _dc_rows) THEN\n    INSERT INTO _dc_rows\n    SELECT sl.* FROM stock_ledger sl\n    WHERE sl.trader_id = v_dc.trader_id\n      AND sl.reference_type = ''batch'' AND sl.reference_id = v_dc.batch_id\n      AND sl.movement_type IN (''purchased'',''returned_in'')\n      AND EXISTS (SELECT 1 FROM unnest(v_note_prefixes) p\n                  WHERE sl.notes = p OR left(sl.notes, length(p) + 3) = p || '' — '')\n      AND NOT EXISTS (\n        SELECT 1 FROM audit_log al\n        WHERE al.table_name = ''delivery_challans'' AND al.action = ''DELETE''\n          AND al.trader_id = v_dc.trader_id\n          AND al.old_values->>''batch_id'' = v_dc.batch_id::text\n          AND (al.old_values->>''created_at'')::timestamptz = sl.created_at);\n  END IF;\n\n  SELECT count(*), COALESCE(sum(quantity_birds), 0), COALESCE(sum(quantity_kg), 0)\n  INTO v_ledger_cnt, v_rev_birds, v_rev_kg FROM _dc_rows;\n'],
    -- e) a duplicate (or re-added) DC that never got stock can still be deleted
    ARRAY[E'  IF v_ledger_cnt = 0 AND COALESCE(v_dc.bird_count, 0) > 0 THEN\n',
          E'  IF v_ledger_cnt = 0 AND COALESCE(v_dc.bird_count, 0) > 0\n     AND NOT v_dup AND NOT v_any_note THEN\n']
  ];

  FOR i IN 1 .. array_length(r, 1) LOOP
    n := (length(d) - length(replace(d, r[i][1], ''))) / length(r[i][1]);
    IF n <> 1 THEN
      RAISE EXCEPTION 'delete_batch_dc: part % expected 1 match, found %', chr(96 + i), n;
    END IF;
    d := replace(d, r[i][1], r[i][2]);
  END LOOP;

  EXECUTE d;
END
$patch$;
