-- Retailer to Retailer Transfer.
--
-- Retailer A sells birds to Retailer B through the trader. One transfer
-- posts, in a single transaction:
--   * A: a credit in the customer ledger (kg × A's rate) — A's outstanding
--        goes down — and a stock-in row (A's birds / kg come into stock).
--   * B: a debit in the customer ledger (kg × B's rate) — B's outstanding
--        goes up — and a stock-out row (the same birds / kg go out to B).
-- Net stock is 0 when both sides use the same item; both movements are kept.
--
-- Doc No: RTR-YYYYMM-NNNNN, its own series, restarting at 00001 each year
-- (same pattern as cash collection's CSH- series). Kept on edit.
--
-- ledger_entries and stock_ledger rows are never updated or deleted:
--   * Edit   = reverse the current rows (opposite entries) + post new ones.
--   * Delete = reverse the current rows; the transfer is marked deleted.
-- Every edit / delete writes an audit row with the old values and the ids of
-- the reversed and reversal rows.
--
-- ledger_entries.doc_no has a unique index per trader (cash collection doc
-- numbers), so the transfer's ledger rows keep only manual_doc_no; the RTR
-- Doc No lives on retailer_transfers and get_retailer_statement shows it.
-- Ledger rows use source_type 'retailer_transfer' (live postings) and
-- 'retailer_transfer_reversal' (reversals). get_retailer_statement hides the
-- reversals and the postings they cancel, so the statement shows only the
-- current version of each transfer, with its Doc No / Man. Doc No.
-- Stock rows use movement_type 'retailer_transfer_in' / 'retailer_transfer_out'
-- (reference_type 'retailer_transfer' or 'retailer_transfer_reversal').
--
-- Existing functions patched in place (each patch stops with an error if the
-- function doesn't look as expected; safe to run twice):
--   * get_retailer_statement         — hide reversed transfers, show kg / rate /
--                                      birds / item / other party.
--   * fn_update_retailer_outstanding — a deleted transfer no longer counts in
--                                      B's total_purchases.
--   * fn_stock_point_in_house_balance, get_inventory_ledger_v1
--                                    — count transfer in / out rows.

-- ── 1. Tables ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.retailer_transfers (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trader_id        uuid NOT NULL REFERENCES public.traders(id),
  doc_no           text NOT NULL,
  manual_doc_no    text,
  transfer_date    date NOT NULL,
  -- Purchase From (Retailer A)
  from_retailer_id uuid NOT NULL REFERENCES public.retailers(id),
  from_product_id  uuid NOT NULL REFERENCES public.master_products(id),
  purchase_rate    numeric(12,2) NOT NULL CHECK (purchase_rate >= 0),
  purchase_amount  numeric(14,2) NOT NULL CHECK (purchase_amount >= 0),
  -- Sales To (Retailer B)
  to_retailer_id   uuid NOT NULL REFERENCES public.retailers(id),
  to_product_id    uuid NOT NULL REFERENCES public.master_products(id),
  sale_rate        numeric(12,2) NOT NULL CHECK (sale_rate >= 0),
  sale_amount      numeric(14,2) NOT NULL CHECK (sale_amount >= 0),
  bird_count       integer NOT NULL DEFAULT 0 CHECK (bird_count >= 0),
  quantity_kg      numeric(12,3) NOT NULL CHECK (quantity_kg > 0),
  -- Current ledger / stock rows of this transfer
  from_ledger_id   uuid REFERENCES public.ledger_entries(id),
  to_ledger_id     uuid REFERENCES public.ledger_entries(id),
  stock_in_id      uuid REFERENCES public.stock_ledger(id),
  stock_out_id     uuid REFERENCES public.stock_ledger(id),
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active','deleted')),
  version          integer NOT NULL DEFAULT 1,
  created_by       uuid,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       uuid,
  updated_at       timestamptz,
  deleted_by       uuid,
  deleted_at       timestamptz,
  delete_reason    text,
  CONSTRAINT retailer_transfers_diff_retailers CHECK (from_retailer_id <> to_retailer_id),
  CONSTRAINT retailer_transfers_doc_no_key UNIQUE (trader_id, doc_no)
);

CREATE INDEX IF NOT EXISTS idx_retailer_transfers_trader_date
  ON public.retailer_transfers (trader_id, transfer_date DESC);
CREATE INDEX IF NOT EXISTS idx_retailer_transfers_from_ledger
  ON public.retailer_transfers (from_ledger_id);
CREATE INDEX IF NOT EXISTS idx_retailer_transfers_to_ledger
  ON public.retailer_transfers (to_ledger_id);

CREATE TABLE IF NOT EXISTS public.retailer_transfer_audit (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id         uuid NOT NULL REFERENCES public.retailer_transfers(id),
  trader_id           uuid NOT NULL,
  action              text NOT NULL CHECK (action IN ('edit','delete')),
  reason              text,
  old_values          jsonb NOT NULL,
  new_values          jsonb,
  reversed_ledger_ids uuid[] NOT NULL,
  reversal_ledger_ids uuid[] NOT NULL,
  reversed_stock_ids  uuid[] NOT NULL,
  reversal_stock_ids  uuid[] NOT NULL,
  performed_by        uuid,
  performed_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_retailer_transfer_audit_transfer
  ON public.retailer_transfer_audit (transfer_id);

-- Read access for the trader's own users; all writes go through the RPCs.
ALTER TABLE public.retailer_transfers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.retailer_transfer_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS retailer_transfers_read ON public.retailer_transfers;
CREATE POLICY retailer_transfers_read ON public.retailer_transfers
  FOR SELECT USING (trader_id IN (
    SELECT ur.trader_id FROM public.user_roles ur
    WHERE ur.user_id = auth.uid() AND ur.is_active = true));

DROP POLICY IF EXISTS retailer_transfer_audit_read ON public.retailer_transfer_audit;
CREATE POLICY retailer_transfer_audit_read ON public.retailer_transfer_audit
  FOR SELECT USING (trader_id IN (
    SELECT ur.trader_id FROM public.user_roles ur
    WHERE ur.user_id = auth.uid() AND ur.is_active = true));

-- ── 2. Doc No series ──────────────────────────────────────────────────────
-- Next RTR-YYYYMM-NNNNN for the date's year. Deleted transfers keep their
-- number, so a number is never reused.
CREATE OR REPLACE FUNCTION public.fn_next_rtr_doc_no(p_trader_id uuid, p_date date)
RETURNS text
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
  SELECT 'RTR-' || to_char(p_date, 'YYYYMM') || '-' ||
         lpad((COALESCE(max(substring(doc_no FROM 12)::int), 0) + 1)::text, 5, '0')
  FROM retailer_transfers
  WHERE trader_id = p_trader_id
    AND doc_no LIKE 'RTR-' || to_char(p_date, 'YYYY') || '%'
    AND substring(doc_no FROM 12) ~ '^[0-9]+$';
$$;

CREATE OR REPLACE FUNCTION public.preview_retailer_transfer_doc_no(
  p_trader_id uuid, p_date date DEFAULT CURRENT_DATE)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid() AND trader_id = p_trader_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Access denied.';
  END IF;
  RETURN fn_next_rtr_doc_no(p_trader_id, COALESCE(p_date, CURRENT_DATE));
END;
$$;

-- ── 3. Internal helpers ───────────────────────────────────────────────────
-- Trader admin of this trader, or raise.
CREATE OR REPLACE FUNCTION public.fn_rtr_assert_admin(p_trader_id uuid)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid() AND trader_id = p_trader_id AND is_active = true
      AND role IN ('super_admin','trader_admin')
  ) THEN
    RAISE EXCEPTION 'Access denied: only the trader admin can record retailer transfers.';
  END IF;
END;
$$;

-- Checks the inputs and fills the amounts on the given row.
CREATE OR REPLACE FUNCTION public.fn_rtr_validate(INOUT t public.retailer_transfers)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF t.transfer_date IS NULL THEN
    RAISE EXCEPTION 'Date is required.';
  END IF;
  IF t.transfer_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'Date cannot be in the future: %', t.transfer_date;
  END IF;
  IF t.from_retailer_id IS NULL OR t.to_retailer_id IS NULL THEN
    RAISE EXCEPTION 'Choose both customers (Sales To and Purchase From).';
  END IF;
  IF t.from_retailer_id = t.to_retailer_id THEN
    RAISE EXCEPTION 'Sales To and Purchase From must be different customers.';
  END IF;
  IF (SELECT count(*) FROM retailers
       WHERE id IN (t.from_retailer_id, t.to_retailer_id)
         AND trader_id = t.trader_id) <> 2 THEN
    RAISE EXCEPTION 'Customer not found for this trader.';
  END IF;
  IF t.from_product_id IS NULL OR t.to_product_id IS NULL THEN
    RAISE EXCEPTION 'Choose the item for both customers.';
  END IF;
  IF (SELECT count(DISTINCT id) FROM master_products
       WHERE id IN (t.from_product_id, t.to_product_id))
     <> (CASE WHEN t.from_product_id = t.to_product_id THEN 1 ELSE 2 END) THEN
    RAISE EXCEPTION 'Item not found.';
  END IF;
  IF COALESCE(t.quantity_kg, 0) <= 0 THEN
    RAISE EXCEPTION 'Kgs must be more than 0.';
  END IF;
  IF COALESCE(t.bird_count, 0) < 0 THEN
    RAISE EXCEPTION 'No. of birds cannot be negative.';
  END IF;
  IF COALESCE(t.sale_rate, 0) <= 0 OR COALESCE(t.purchase_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'Both rates must be more than 0.';
  END IF;

  t.bird_count      := COALESCE(t.bird_count, 0);
  t.quantity_kg     := round(t.quantity_kg, 3);
  t.sale_rate       := round(t.sale_rate, 2);
  t.purchase_rate   := round(t.purchase_rate, 2);
  t.sale_amount     := round(t.quantity_kg * t.sale_rate, 2);
  t.purchase_amount := round(t.quantity_kg * t.purchase_rate, 2);
  t.manual_doc_no   := NULLIF(btrim(t.manual_doc_no), '');
END;
$$;

-- Posts the 2 ledger rows and 2 stock rows for the transfer and stores their
-- ids on it.
CREATE OR REPLACE FUNCTION public.fn_rtr_post(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t        retailer_transfers;
  v_from   text;
  v_to     text;
  v_fprod  text;
  v_tprod  text;
  v_fl     uuid;
  v_tl     uuid;
  v_si     uuid;
  v_so     uuid;
BEGIN
  SELECT * INTO t FROM retailer_transfers WHERE id = p_id;
  SELECT shop_name INTO v_from FROM retailers WHERE id = t.from_retailer_id;
  SELECT shop_name INTO v_to   FROM retailers WHERE id = t.to_retailer_id;
  SELECT name INTO v_fprod FROM master_products WHERE id = t.from_product_id;
  SELECT name INTO v_tprod FROM master_products WHERE id = t.to_product_id;

  -- A: credit (A sold to us) — outstanding goes down.
  INSERT INTO ledger_entries(
    trader_id, retailer_id, entry_type, amount, payment_mode,
    source_type, source_id, description, entry_date, recorded_by,
    manual_doc_no)
  VALUES (
    t.trader_id, t.from_retailer_id, 'credit', t.purchase_amount, 'adjustment',
    'retailer_transfer', t.id,
    'Customer transfer to ' || v_to || ' - ' || v_fprod || ' ' ||
      t.quantity_kg || ' kg, ' || t.bird_count || ' birds @ ' || t.purchase_rate,
    t.transfer_date, auth.uid(), t.manual_doc_no)
  RETURNING id INTO v_fl;

  -- B: debit (we sold to B) — outstanding goes up.
  INSERT INTO ledger_entries(
    trader_id, retailer_id, entry_type, amount, payment_mode,
    source_type, source_id, description, entry_date, recorded_by,
    manual_doc_no)
  VALUES (
    t.trader_id, t.to_retailer_id, 'debit', t.sale_amount, 'adjustment',
    'retailer_transfer', t.id,
    'Customer transfer from ' || v_from || ' - ' || v_tprod || ' ' ||
      t.quantity_kg || ' kg, ' || t.bird_count || ' birds @ ' || t.sale_rate,
    t.transfer_date, auth.uid(), t.manual_doc_no)
  RETURNING id INTO v_tl;

  -- Stock in from A, stock out to B (stock point: no agent / shift).
  INSERT INTO stock_ledger(
    trader_id, product_id, entry_date, movement_type, quantity_birds,
    quantity_kg, reference_type, reference_id, notes, created_by)
  VALUES (
    t.trader_id, t.from_product_id, t.transfer_date, 'retailer_transfer_in',
    t.bird_count, t.quantity_kg, 'retailer_transfer', t.id,
    t.doc_no || ' - from ' || v_from, auth.uid())
  RETURNING id INTO v_si;

  INSERT INTO stock_ledger(
    trader_id, product_id, entry_date, movement_type, quantity_birds,
    quantity_kg, reference_type, reference_id, notes, created_by)
  VALUES (
    t.trader_id, t.to_product_id, t.transfer_date, 'retailer_transfer_out',
    t.bird_count, t.quantity_kg, 'retailer_transfer', t.id,
    t.doc_no || ' - to ' || v_to, auth.uid())
  RETURNING id INTO v_so;

  UPDATE retailer_transfers
     SET from_ledger_id = v_fl, to_ledger_id = v_tl,
         stock_in_id = v_si, stock_out_id = v_so
   WHERE id = t.id;
END;
$$;

-- Posts opposite entries for the transfer's current ledger / stock rows and
-- writes the audit row. Leaves the transfer row itself unchanged.
CREATE OR REPLACE FUNCTION public.fn_rtr_reverse(
  p_id uuid, p_action text, p_reason text, p_new_values jsonb)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t       retailer_transfers;
  v_label text := CASE WHEN p_action = 'delete' THEN 'deleted' ELSE 'edited' END;
  v_fl    uuid;
  v_tl    uuid;
  v_si    uuid;
  v_so    uuid;
  v_audit uuid;
BEGIN
  SELECT * INTO t FROM retailer_transfers WHERE id = p_id;

  -- A: debit back the credit.
  INSERT INTO ledger_entries(
    trader_id, retailer_id, entry_type, amount, payment_mode,
    source_type, source_id, description, entry_date, recorded_by,
    manual_doc_no)
  SELECT trader_id, retailer_id, 'debit', amount, payment_mode,
         'retailer_transfer_reversal', t.id,
         'Reversal (' || v_label || '): ' || description,
         entry_date, auth.uid(), manual_doc_no
    FROM ledger_entries WHERE id = t.from_ledger_id
  RETURNING id INTO v_fl;

  -- B: credit back the debit.
  INSERT INTO ledger_entries(
    trader_id, retailer_id, entry_type, amount, payment_mode,
    source_type, source_id, description, entry_date, recorded_by,
    manual_doc_no)
  SELECT trader_id, retailer_id, 'credit', amount, payment_mode,
         'retailer_transfer_reversal', t.id,
         'Reversal (' || v_label || '): ' || description,
         entry_date, auth.uid(), manual_doc_no
    FROM ledger_entries WHERE id = t.to_ledger_id
  RETURNING id INTO v_tl;

  -- Stock: take back the stock-in, put back the stock-out.
  INSERT INTO stock_ledger(
    trader_id, product_id, entry_date, movement_type, quantity_birds,
    quantity_kg, reference_type, reference_id, notes, created_by)
  SELECT trader_id, product_id, entry_date, 'retailer_transfer_out',
         quantity_birds, quantity_kg, 'retailer_transfer_reversal', t.id,
         'Reversal (' || v_label || '): ' || COALESCE(notes, ''), auth.uid()
    FROM stock_ledger WHERE id = t.stock_in_id
  RETURNING id INTO v_si;

  INSERT INTO stock_ledger(
    trader_id, product_id, entry_date, movement_type, quantity_birds,
    quantity_kg, reference_type, reference_id, notes, created_by)
  SELECT trader_id, product_id, entry_date, 'retailer_transfer_in',
         quantity_birds, quantity_kg, 'retailer_transfer_reversal', t.id,
         'Reversal (' || v_label || '): ' || COALESCE(notes, ''), auth.uid()
    FROM stock_ledger WHERE id = t.stock_out_id
  RETURNING id INTO v_so;

  INSERT INTO retailer_transfer_audit(
    transfer_id, trader_id, action, reason, old_values, new_values,
    reversed_ledger_ids, reversal_ledger_ids,
    reversed_stock_ids, reversal_stock_ids, performed_by)
  VALUES (
    t.id, t.trader_id, p_action, NULLIF(btrim(p_reason), ''), to_jsonb(t), p_new_values,
    ARRAY[t.from_ledger_id, t.to_ledger_id], ARRAY[v_fl, v_tl],
    ARRAY[t.stock_in_id, t.stock_out_id], ARRAY[v_si, v_so], auth.uid())
  RETURNING id INTO v_audit;

  RETURN v_audit;
END;
$$;

-- Helpers are internal only.
REVOKE ALL ON FUNCTION public.fn_rtr_validate(public.retailer_transfers) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_rtr_post(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_rtr_reverse(uuid, text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_rtr_assert_admin(uuid) FROM PUBLIC, anon, authenticated;

-- ── 4. RPCs ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_retailer_transfer(
  p_trader_id        uuid,
  p_transfer_date    date,
  p_to_retailer_id   uuid,
  p_to_product_id    uuid,
  p_from_retailer_id uuid,
  p_from_product_id  uuid,
  p_bird_count       integer,
  p_quantity_kg      numeric,
  p_sale_rate        numeric,
  p_purchase_rate    numeric,
  p_manual_doc_no    text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t retailer_transfers;
BEGIN
  PERFORM fn_rtr_assert_admin(p_trader_id);

  t.trader_id        := p_trader_id;
  t.transfer_date    := COALESCE(p_transfer_date, CURRENT_DATE);
  t.to_retailer_id   := p_to_retailer_id;
  t.to_product_id    := p_to_product_id;
  t.from_retailer_id := p_from_retailer_id;
  t.from_product_id  := COALESCE(p_from_product_id, p_to_product_id);
  t.bird_count       := p_bird_count;
  t.quantity_kg      := p_quantity_kg;
  t.sale_rate        := p_sale_rate;
  t.purchase_rate    := p_purchase_rate;
  t.manual_doc_no    := p_manual_doc_no;
  t := fn_rtr_validate(t);

  PERFORM pg_advisory_xact_lock(hashtext('rtr_doc_no:' || p_trader_id::text));
  t.doc_no := fn_next_rtr_doc_no(p_trader_id, t.transfer_date);

  INSERT INTO retailer_transfers(
    trader_id, doc_no, manual_doc_no, transfer_date,
    from_retailer_id, from_product_id, purchase_rate, purchase_amount,
    to_retailer_id, to_product_id, sale_rate, sale_amount,
    bird_count, quantity_kg, created_by)
  VALUES (
    t.trader_id, t.doc_no, t.manual_doc_no, t.transfer_date,
    t.from_retailer_id, t.from_product_id, t.purchase_rate, t.purchase_amount,
    t.to_retailer_id, t.to_product_id, t.sale_rate, t.sale_amount,
    t.bird_count, t.quantity_kg, auth.uid())
  RETURNING id INTO t.id;

  PERFORM fn_rtr_post(t.id);

  RETURN jsonb_build_object('id', t.id, 'doc_no', t.doc_no,
    'sale_amount', t.sale_amount, 'purchase_amount', t.purchase_amount);
END;
$$;

-- Edit = reverse the current rows + post new ones. Doc No stays the same.
CREATE OR REPLACE FUNCTION public.update_retailer_transfer(
  p_transfer_id      uuid,
  p_transfer_date    date,
  p_to_retailer_id   uuid,
  p_to_product_id    uuid,
  p_from_retailer_id uuid,
  p_from_product_id  uuid,
  p_bird_count       integer,
  p_quantity_kg      numeric,
  p_sale_rate        numeric,
  p_purchase_rate    numeric,
  p_manual_doc_no    text DEFAULT NULL,
  p_reason           text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  o retailer_transfers;
  t retailer_transfers;
BEGIN
  SELECT * INTO o FROM retailer_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;
  PERFORM fn_rtr_assert_admin(o.trader_id);
  IF o.status <> 'active' THEN
    RAISE EXCEPTION 'Transfer % is deleted and cannot be edited.', o.doc_no;
  END IF;

  t := o;
  t.transfer_date    := COALESCE(p_transfer_date, o.transfer_date);
  t.to_retailer_id   := p_to_retailer_id;
  t.to_product_id    := p_to_product_id;
  t.from_retailer_id := p_from_retailer_id;
  t.from_product_id  := COALESCE(p_from_product_id, p_to_product_id);
  t.bird_count       := p_bird_count;
  t.quantity_kg      := p_quantity_kg;
  t.sale_rate        := p_sale_rate;
  t.purchase_rate    := p_purchase_rate;
  t.manual_doc_no    := p_manual_doc_no;
  t := fn_rtr_validate(t);

  IF (t.transfer_date, t.to_retailer_id, t.to_product_id, t.from_retailer_id,
      t.from_product_id, t.bird_count, t.quantity_kg, t.sale_rate,
      t.purchase_rate, t.manual_doc_no)
     IS NOT DISTINCT FROM
     (o.transfer_date, o.to_retailer_id, o.to_product_id, o.from_retailer_id,
      o.from_product_id, o.bird_count, o.quantity_kg, o.sale_rate,
      o.purchase_rate, o.manual_doc_no) THEN
    RAISE EXCEPTION 'Nothing changed.';
  END IF;

  PERFORM fn_rtr_reverse(o.id, 'edit', COALESCE(NULLIF(btrim(p_reason), ''), 'Edited'),
    jsonb_build_object(
      'transfer_date', t.transfer_date, 'to_retailer_id', t.to_retailer_id,
      'to_product_id', t.to_product_id, 'from_retailer_id', t.from_retailer_id,
      'from_product_id', t.from_product_id, 'bird_count', t.bird_count,
      'quantity_kg', t.quantity_kg, 'sale_rate', t.sale_rate,
      'purchase_rate', t.purchase_rate, 'manual_doc_no', t.manual_doc_no));

  UPDATE retailer_transfers SET
    transfer_date    = t.transfer_date,
    manual_doc_no    = t.manual_doc_no,
    from_retailer_id = t.from_retailer_id,
    from_product_id  = t.from_product_id,
    purchase_rate    = t.purchase_rate,
    purchase_amount  = t.purchase_amount,
    to_retailer_id   = t.to_retailer_id,
    to_product_id    = t.to_product_id,
    sale_rate        = t.sale_rate,
    sale_amount      = t.sale_amount,
    bird_count       = t.bird_count,
    quantity_kg      = t.quantity_kg,
    version          = o.version + 1,
    updated_by       = auth.uid(),
    updated_at       = now()
  WHERE id = o.id;

  PERFORM fn_rtr_post(o.id);

  RETURN jsonb_build_object('id', o.id, 'doc_no', o.doc_no,
    'sale_amount', t.sale_amount, 'purchase_amount', t.purchase_amount);
END;
$$;

-- Delete = reverse the current rows; the transfer stays, marked deleted.
CREATE OR REPLACE FUNCTION public.delete_retailer_transfer(
  p_transfer_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  o retailer_transfers;
BEGIN
  SELECT * INTO o FROM retailer_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;
  PERFORM fn_rtr_assert_admin(o.trader_id);
  IF o.status <> 'active' THEN
    RAISE EXCEPTION 'Transfer % is already deleted.', o.doc_no;
  END IF;
  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required to delete a transfer.';
  END IF;

  PERFORM fn_rtr_reverse(o.id, 'delete', p_reason, NULL);

  UPDATE retailer_transfers SET
    status        = 'deleted',
    deleted_by    = auth.uid(),
    deleted_at    = now(),
    delete_reason = btrim(p_reason)
  WHERE id = o.id;

  RETURN jsonb_build_object('id', o.id, 'doc_no', o.doc_no);
END;
$$;

-- View list: transfers in a date range with customer / item names.
CREATE OR REPLACE FUNCTION public.get_retailer_transfers(
  p_trader_id       uuid,
  p_from_date       date DEFAULT NULL,
  p_to_date         date DEFAULT NULL,
  p_include_deleted boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid() AND trader_id = p_trader_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Access denied.';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.transfer_date DESC, x.doc_no DESC)
    FROM (
      SELECT t.id, t.doc_no, t.manual_doc_no, t.transfer_date,
             t.to_retailer_id,   rb.shop_name AS to_retailer_name,
             t.to_product_id,    pb.name      AS to_product_name,
             t.from_retailer_id, ra.shop_name AS from_retailer_name,
             t.from_product_id,  pa.name      AS from_product_name,
             t.bird_count, t.quantity_kg,
             t.sale_rate, t.sale_amount, t.purchase_rate, t.purchase_amount,
             t.status, t.version, t.created_at, t.updated_at,
             t.deleted_at, t.delete_reason
      FROM retailer_transfers t
      JOIN retailers rb       ON rb.id = t.to_retailer_id
      JOIN retailers ra       ON ra.id = t.from_retailer_id
      JOIN master_products pb ON pb.id = t.to_product_id
      JOIN master_products pa ON pa.id = t.from_product_id
      WHERE t.trader_id = p_trader_id
        AND (p_from_date IS NULL OR t.transfer_date >= p_from_date)
        AND (p_to_date   IS NULL OR t.transfer_date <= p_to_date)
        AND (p_include_deleted OR t.status = 'active')
    ) x
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.create_retailer_transfer(uuid, date, uuid, uuid, uuid, uuid, integer, numeric, numeric, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_retailer_transfer(uuid, date, uuid, uuid, uuid, uuid, integer, numeric, numeric, numeric, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_retailer_transfer(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_retailer_transfers(uuid, date, date, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.preview_retailer_transfer_doc_no(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_retailer_transfer(uuid, date, uuid, uuid, uuid, uuid, integer, numeric, numeric, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_retailer_transfer(uuid, date, uuid, uuid, uuid, uuid, integer, numeric, numeric, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_retailer_transfer(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_retailer_transfers(uuid, date, date, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_retailer_transfer_doc_no(uuid, date) TO authenticated;

-- ── 5. fn_update_retailer_outstanding: total_purchases ────────────────────
-- Same as before, plus: a transfer reversal's debit (to A) is not a purchase,
-- and its credit (to B) takes the reversed sale back out.
CREATE OR REPLACE FUNCTION public.fn_update_retailer_outstanding()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_rid uuid;
BEGIN
  v_rid := COALESCE(NEW.retailer_id, OLD.retailer_id);
  IF v_rid IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  UPDATE retailers SET
    -- BUG-ACC-05 FIX: removed GREATEST(0,...) — credit balances now visible
    outstanding_balance = (
      SELECT COALESCE(SUM(
        CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END
      ), 0)
      FROM ledger_entries
      WHERE retailer_id = v_rid
    ),
    -- BUG-ACC-06 FIX: exclude opening_balance from purchase metric
    -- payment_reversal / retailer_transfer_reversal debits are not sales.
    -- A retailer_transfer_reversal credit cancels a transfer sale to B.
    total_purchases = (
      SELECT COALESCE(SUM(amount) FILTER (
               WHERE entry_type = 'debit'
                 AND source_type NOT IN ('opening_balance', 'payment_reversal',
                                         'retailer_transfer_reversal')), 0)
           - COALESCE(SUM(amount) FILTER (
               WHERE entry_type = 'credit'
                 AND source_type = 'retailer_transfer_reversal'), 0)
      FROM ledger_entries
      WHERE retailer_id = v_rid
    )
  WHERE id = v_rid;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- ── 6. Patches in place ───────────────────────────────────────────────────
DO $patch$
DECLARE
  d text;
  n int;
BEGIN
  -- 6a. get_retailer_statement ------------------------------------------
  d := pg_get_functiondef('public.get_retailer_statement(uuid,date,date,uuid)'::regprocedure);
  IF position('retailer_transfer' IN d) = 0 THEN
    -- hide reversals and the postings they cancelled
    n := (length(d) - length(replace(d,
      $o$AND le.source_type NOT IN ('invoice_cancellation', 'payment_reversal')$o$, '')))
      / length($o$AND le.source_type NOT IN ('invoice_cancellation', 'payment_reversal')$o$);
    IF n <> 1 THEN RAISE EXCEPTION 'get_retailer_statement: effective_ledger filter not found (%).', n; END IF;
    d := replace(d,
      $o$AND le.source_type NOT IN ('invoice_cancellation', 'payment_reversal')$o$,
      $n$AND le.source_type NOT IN ('invoice_cancellation', 'payment_reversal', 'retailer_transfer_reversal')
      -- Retailer transfer: only the current postings of active transfers
      AND NOT (le.source_type = 'retailer_transfer' AND NOT EXISTS (
        SELECT 1 FROM retailer_transfers rtx
        WHERE rtx.status = 'active'
          AND le.id IN (rtx.from_ledger_id, rtx.to_ledger_id)))$n$);

    -- kg / rate / birds for transfer rows
    IF position($o$CASE WHEN el.source_type = 'return' THEN rte.weight_kg ELSE i.quantity_kg  END AS weight_kg$o$ IN d) = 0
       OR position($o$CASE WHEN el.source_type = 'return' THEN rcn.rate_per_kg ELSE i.price_per_kg END AS rate_per_kg$o$ IN d) = 0
       OR position($o$CASE WHEN el.source_type = 'return' THEN rte.bird_count ELSE i.bird_count   END AS birds$o$ IN d) = 0
       OR position($o$rte.reason AS return_reason,$o$ IN d) = 0
       OR position($o$NULL::text AS return_reason,$o$ IN d) = 0
       OR position($o$LEFT JOIN orders ord ON ord.id = el.order_id$o$ IN d) = 0 THEN
      RAISE EXCEPTION 'get_retailer_statement does not look as expected; not patched.';
    END IF;
    d := replace(d,
      $o$CASE WHEN el.source_type = 'return' THEN rte.weight_kg ELSE i.quantity_kg  END AS weight_kg$o$,
      $n$CASE WHEN el.source_type = 'return' THEN rte.weight_kg WHEN el.source_type = 'retailer_transfer' THEN rtr.quantity_kg ELSE i.quantity_kg  END AS weight_kg$n$);
    d := replace(d,
      $o$CASE WHEN el.source_type = 'return' THEN rcn.rate_per_kg ELSE i.price_per_kg END AS rate_per_kg$o$,
      $n$CASE WHEN el.source_type = 'return' THEN rcn.rate_per_kg WHEN el.source_type = 'retailer_transfer' THEN (CASE WHEN el.entry_type = 'debit' THEN rtr.sale_rate ELSE rtr.purchase_rate END) ELSE i.price_per_kg END AS rate_per_kg$n$);
    d := replace(d,
      $o$CASE WHEN el.source_type = 'return' THEN rte.bird_count ELSE i.bird_count   END AS birds$o$,
      $n$CASE WHEN el.source_type = 'return' THEN rte.bird_count WHEN el.source_type = 'retailer_transfer' THEN rtr.bird_count ELSE i.bird_count   END AS birds$n$);
    -- item and the other customer, for the Details column
    -- Doc No from the transfer (ledger_entries.doc_no is unique per trader,
    -- so the transfer's two ledger rows can't both carry it)
    IF position($o$COALESCE(el.doc_no, ord.doc_no) AS doc_no$o$ IN d) = 0 THEN
      RAISE EXCEPTION 'get_retailer_statement: doc_no column not found; not patched.';
    END IF;
    d := replace(d,
      $o$COALESCE(el.doc_no, ord.doc_no) AS doc_no$o$,
      $n$COALESCE(el.doc_no, rtr.doc_no, ord.doc_no) AS doc_no$n$);
    d := replace(d,
      $o$rte.reason AS return_reason,$o$,
      $n$rte.reason AS return_reason,
          rtp.name AS transfer_product_name,
          rtparty.shop_name AS transfer_party,$n$);
    d := replace(d,
      $o$NULL::text AS return_reason,$o$,
      $n$NULL::text AS return_reason,
          NULL::text AS transfer_product_name,
          NULL::text AS transfer_party,$n$);
    d := replace(d,
      $o$LEFT JOIN orders ord ON ord.id = el.order_id$o$,
      $n$LEFT JOIN orders ord ON ord.id = el.order_id
        LEFT JOIN retailer_transfers rtr ON rtr.id = el.source_id AND el.source_type = 'retailer_transfer'
        LEFT JOIN master_products rtp ON rtp.id = (CASE WHEN el.entry_type = 'debit' THEN rtr.to_product_id ELSE rtr.from_product_id END)
        LEFT JOIN retailers rtparty ON rtparty.id = (CASE WHEN el.entry_type = 'debit' THEN rtr.from_retailer_id ELSE rtr.to_retailer_id END)$n$);
    EXECUTE d;
  END IF;

  -- 6b. fn_stock_point_in_house_balance -----------------------------------
  d := pg_get_functiondef('public.fn_stock_point_in_house_balance(uuid,uuid,date)'::regprocedure);
  IF position('retailer_transfer' IN d) = 0 THEN
    n := (length(d) - length(replace(d, $o$('physical_count_increase','manual_adjustment_increase')$o$, '')))
         / length($o$('physical_count_increase','manual_adjustment_increase')$o$);
    IF n <> 2 THEN RAISE EXCEPTION 'fn_stock_point_in_house_balance: increase list found % times, expected 2.', n; END IF;
    n := (length(d) - length(replace(d, $o$'manual_adjustment_decrease','in_house_sale','theft')$o$, '')))
         / length($o$'manual_adjustment_decrease','in_house_sale','theft')$o$);
    IF n <> 2 THEN RAISE EXCEPTION 'fn_stock_point_in_house_balance: decrease list found % times, expected 2.', n; END IF;
    d := replace(d, $o$('physical_count_increase','manual_adjustment_increase')$o$,
                    $n$('physical_count_increase','manual_adjustment_increase','retailer_transfer_in')$n$);
    d := replace(d, $o$'manual_adjustment_decrease','in_house_sale','theft')$o$,
                    $n$'manual_adjustment_decrease','in_house_sale','theft','retailer_transfer_out')$n$);
    EXECUTE d;
  END IF;

  -- 6c. get_inventory_ledger_v1: transfer-in rows are "in" ----------------
  d := pg_get_functiondef('public.get_inventory_ledger_v1(uuid,date,date,uuid,text)'::regprocedure);
  IF position('retailer_transfer' IN d) = 0 THEN
    n := (length(d) - length(replace(d, $o$'physical_count_increase','manual_adjustment_increase')$o$, '')))
         / length($o$'physical_count_increase','manual_adjustment_increase')$o$);
    IF n <> 3 THEN RAISE EXCEPTION 'get_inventory_ledger_v1: in-list found % times, expected 3.', n; END IF;
    d := replace(d, $o$'physical_count_increase','manual_adjustment_increase')$o$,
                    $n$'physical_count_increase','manual_adjustment_increase','retailer_transfer_in')$n$);
    EXECUTE d;
  END IF;
END
$patch$;
