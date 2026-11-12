-- Customer Ledger: show a cash collection's Doc No / Man. Doc No (Bill No).
-- get_retailer_statement took doc_no / manual_doc_no only from the order, so
-- collection rows (no order) were always blank. Now each row uses the ledger
-- entry's own numbers when it has them (cash collections: CSH-…, Man. Doc No),
-- otherwise the order's — sales rows are unchanged (their ledger entries carry
-- no numbers). Run after cash_collection_doc_no.sql. Patched in place; stops
-- with an error if the function doesn't look as expected.
DO $patch$
DECLARE
  d text;
  v_fn regprocedure;
  v_old text := 'ord.doc_no, ord.manual_doc_no,';
  v_new text := 'COALESCE(el.doc_no, ord.doc_no) AS doc_no, COALESCE(el.manual_doc_no, ord.manual_doc_no) AS manual_doc_no,';
  n int;
BEGIN
  SELECT oid::regprocedure INTO v_fn FROM pg_proc
   WHERE proname = 'get_retailer_statement' AND pronamespace = 'public'::regnamespace;
  d := pg_get_functiondef(v_fn);
  IF position('COALESCE(el.doc_no, ord.doc_no)' in d) > 0 THEN
    RAISE NOTICE 'get_retailer_statement already returns collection doc numbers';
    RETURN;
  END IF;
  n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
  IF n <> 1 THEN
    RAISE EXCEPTION 'get_retailer_statement: expected 1 match, found %', n;
  END IF;
  EXECUTE replace(d, v_old, v_new);
END
$patch$;
