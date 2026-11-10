-- Stock Point Sale: Doc No (auto) + Manual Doc No, like Quick Entry.
-- Adds p_manual_doc_no and p_assign_doc_no. The old 10-argument version is
-- dropped first so the RPC call can't match two functions.
DROP FUNCTION IF EXISTS public.create_in_house_sale_v1(uuid, jsonb, uuid, text, text, text, numeric, date, text, uuid);

CREATE OR REPLACE FUNCTION public.create_in_house_sale_v1(p_trader_id uuid, p_items jsonb, p_retailer_id uuid DEFAULT NULL::uuid, p_walkin_name text DEFAULT NULL::text, p_walkin_phone text DEFAULT NULL::text, p_payment_mode text DEFAULT 'cash'::text, p_collected_amount numeric DEFAULT NULL::numeric, p_sale_date date DEFAULT CURRENT_DATE, p_notes text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid, p_manual_doc_no text DEFAULT NULL::text, p_assign_doc_no boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- ══════════════════════════════════════════════════════════════════════
-- In-House Stock Point Sale (Phase 2)
-- Customer -> Order -> Invoice -> Ledger -> Stock Movement, all reusing
-- existing tables/triggers/RPCs. No deliveries/agent/shift/batch row is
-- ever created. Stock is reduced via fn_write_stock_movement only; the
-- invoice is inserted with status='approved' so the existing
-- fn_ledger_on_invoice_approve trigger writes the debit ledger entry;
-- record_payment() writes the credit (collection) ledger entry — neither
-- is duplicated here.
-- ══════════════════════════════════════════════════════════════════════
DECLARE
  v_retailer_id      uuid;
  v_is_walkin        boolean;
  v_item             jsonb;
  v_item_count       int := 0;
  v_product_id       uuid;
  v_bird_count       int;
  v_weight_kg        numeric;
  v_rate_override    numeric;
  v_resolved         record;
  v_rate             numeric;
  v_rate_source      text;
  v_base_rate        numeric;
  v_zone_id          uuid;
  v_zone_name        text;
  v_adj_type         text;
  v_adj_value        numeric;
  v_house_cost       numeric;
  v_line_total       numeric;
  v_avail_birds      int;
  v_avail_kg         numeric;
  v_product_name     text;
  v_resolved_items   jsonb := '[]'::jsonb;
  v_total_birds      int := 0;
  v_total_kg         numeric := 0;
  v_subtotal         numeric := 0;
  v_first_product_id uuid;
  v_order_id         uuid;
  v_invoice_id       uuid;
  v_invoice_number   text;
  v_seq              bigint;
  v_order_item_id    uuid;
  v_stock_ledger_id  uuid;
  v_collected        numeric;
  v_order_collected  numeric;
  v_order_balance    numeric;
  v_doc_no           text;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) != 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one product line is required.';
  END IF;
  IF p_payment_mode NOT IN ('cash','upi','bank','credit') THEN
    RAISE EXCEPTION 'Invalid payment mode: %', p_payment_mode;
  END IF;
  IF p_sale_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'Sale date cannot be in the future.';
  END IF;

  -- Resolve retailer: existing, or the trader's single walk-in stub
  IF p_retailer_id IS NOT NULL THEN
    SELECT (retailer_type = 'walk_in') INTO v_is_walkin
    FROM retailers WHERE id = p_retailer_id AND trader_id = p_trader_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Retailer not found or not active.';
    END IF;
    v_retailer_id := p_retailer_id;
  ELSE
    v_retailer_id := fn_get_or_create_walkin_retailer(p_trader_id);
    v_is_walkin := true;
  END IF;

  IF v_is_walkin AND p_payment_mode = 'credit' THEN
    RAISE EXCEPTION 'Walk-in sales must be paid immediately (cash, UPI, or bank). Credit requires a registered retailer.';
  END IF;

  -- Pass 1: validate each line against current in-house stock, resolve rate,
  -- and accumulate totals. No writes yet.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_item_count := v_item_count + 1;

    v_product_id := (v_item->>'product_id')::uuid;
    IF v_product_id IS NULL THEN
      RAISE EXCEPTION 'Product is required on line %.', v_item_count;
    END IF;

    SELECT name INTO v_product_name FROM master_products WHERE id = v_product_id AND is_active = true;
    IF v_product_name IS NULL THEN
      RAISE EXCEPTION 'Product not found or inactive on line %.', v_item_count;
    END IF;

    v_bird_count   := NULLIF(v_item->>'bird_count', '')::int;
    v_weight_kg    := (v_item->>'weight_kg')::numeric;
    v_rate_override := NULLIF(v_item->>'rate_per_kg', '')::numeric;

    IF v_weight_kg IS NULL OR v_weight_kg <= 0 THEN
      RAISE EXCEPTION 'Weight must be greater than 0 kg on line %.', v_item_count;
    END IF;
    IF COALESCE(v_bird_count, 0) < 0 THEN
      RAISE EXCEPTION 'Bird count cannot be negative on line %.', v_item_count;
    END IF;

    -- Sufficient in-house stock check (agent_id = NULL scope) — prevents negative stock
    SELECT COALESCE(in_house_birds, 0), COALESCE(in_house_kg, 0)
    INTO v_avail_birds, v_avail_kg
    FROM get_available_stock(p_trader_id, v_product_id, NULL, NULL)
    LIMIT 1;

    IF v_weight_kg > COALESCE(v_avail_kg, 0) THEN
      RAISE EXCEPTION 'Insufficient in-house stock for %. Available: % kg. Requested: % kg.',
        v_product_name, COALESCE(v_avail_kg, 0), v_weight_kg;
    END IF;
    IF COALESCE(v_bird_count, 0) > 0 AND v_bird_count > COALESCE(v_avail_birds, 0) THEN
      RAISE EXCEPTION 'Insufficient in-house stock for %. Available: % birds. Requested: % birds.',
        v_product_name, COALESCE(v_avail_birds, 0), v_bird_count;
    END IF;

    -- Rate resolution: manual override, else the existing rate cascade (get_effective_rate_v4)
    IF v_rate_override IS NOT NULL AND v_rate_override > 0 THEN
      v_rate := v_rate_override;
      v_rate_source := 'manual_override';
      v_base_rate := v_rate_override;
      v_zone_id := NULL; v_zone_name := NULL; v_adj_type := NULL; v_adj_value := NULL;
    ELSE
      SELECT * INTO v_resolved
      FROM get_effective_rate_v4(p_trader_id, v_retailer_id, v_product_id, v_weight_kg, p_sale_date);

      IF COALESCE(v_resolved.rate, 0) <= 0 THEN
        RAISE EXCEPTION 'No rate found for %. Set a zone rate or default rate first, or provide a manual rate for this sale.', v_product_name;
      END IF;

      v_rate := v_resolved.rate;
      v_rate_source := v_resolved.rate_source;
      v_base_rate := v_resolved.base_rate;
      v_zone_id := v_resolved.zone_id;
      v_zone_name := v_resolved.zone_name;
      v_adj_type := v_resolved.pricing_type;
      v_adj_value := v_resolved.adjustment_value;
    END IF;

    -- House cost basis — same weighted-average formula get_stock_valuation()
    -- already uses (reused, not reinvented), so P&L COGS is real, not estimated.
    SELECT CASE WHEN SUM(net_weight_kg) > 0 THEN SUM(total_landed_cost) / SUM(net_weight_kg) ELSE NULL END
    INTO v_house_cost
    FROM purchase_entries
    WHERE trader_id = p_trader_id AND product_id = v_product_id
      AND status != 'draft' AND total_landed_cost > 0;

    v_line_total := ROUND(v_weight_kg * v_rate, 2);

    v_resolved_items := v_resolved_items || jsonb_build_array(jsonb_build_object(
      'product_id', v_product_id, 'product_name', v_product_name,
      'bird_count', v_bird_count, 'weight_kg', v_weight_kg,
      'rate_per_kg', v_rate, 'rate_source', v_rate_source, 'base_rate', v_base_rate,
      'zone_id', v_zone_id, 'zone_name', v_zone_name,
      'adjustment_type', v_adj_type, 'adjustment_value', v_adj_value,
      'house_cost_per_kg', v_house_cost, 'line_total', v_line_total
    ));

    IF v_item_count = 1 THEN v_first_product_id := v_product_id; END IF;
    v_total_birds := v_total_birds + COALESCE(v_bird_count, 0);
    v_total_kg    := v_total_kg + v_weight_kg;
    v_subtotal    := v_subtotal + v_line_total;
  END LOOP;

  IF v_subtotal <= 0 THEN
    RAISE EXCEPTION 'Sale total must be greater than 0.';
  END IF;

  v_collected := COALESCE(p_collected_amount, CASE WHEN p_payment_mode = 'credit' THEN 0 ELSE v_subtotal END);

  -- Doc No: same DOC-YYYYMM-NNNNN series and lock as Quick Entry
  -- (agent_create_instant_order_multi), so the two never hand out the same number.
  IF p_assign_doc_no THEN
    PERFORM pg_advisory_xact_lock(hashtext('order_doc_no:' || p_trader_id::text));
    v_doc_no := fn_next_order_doc_no(p_trader_id, p_sale_date);
  END IF;

  -- Order (no agent, no batch — source='in_house' marks it distinctly)
  INSERT INTO orders(
    trader_id, retailer_id, product_id, order_date, delivery_date,
    status, source, total_quantity, estimated_birds, total_amount, final_amount,
    collected_amount, balance_amount, payment_type,
    approval_status, approved_at, approved_by,
    walk_in_name, walk_in_phone, notes,
    is_instant_order, created_by_agent_id, batch_id,
    doc_no, manual_doc_no
  ) VALUES (
    p_trader_id, v_retailer_id, v_first_product_id, p_sale_date, p_sale_date,
    'invoiced', 'in_house', v_total_kg, v_total_birds, v_subtotal, v_subtotal,
    0, v_subtotal, p_payment_mode,
    'approved', now(), p_created_by,
    CASE WHEN v_is_walkin THEN p_walkin_name ELSE NULL END,
    CASE WHEN v_is_walkin THEN p_walkin_phone ELSE NULL END,
    p_notes,
    false, NULL, NULL,
    v_doc_no, NULLIF(btrim(p_manual_doc_no), '')
  ) RETURNING id INTO v_order_id;

  -- Invoice — status='approved' at insert fires fn_ledger_on_invoice_approve
  -- automatically (debit ledger entry). Do not insert into ledger_entries here.
  SELECT nextval('invoice_seq') INTO v_seq;
  v_invoice_number := 'INV-' || TO_CHAR(p_sale_date, 'YYYYMM') || '-' || LPAD(v_seq::text, 5, '0');

  INSERT INTO invoices(
    trader_id, order_id, delivery_id, retailer_id, invoice_number, invoice_date,
    quantity_kg, bird_count, price_per_kg,
    subtotal_amount, discount_percent, discount_amount, total_amount,
    collected_amount, balance_amount, status, approved_by, approved_at, notes
  ) VALUES (
    p_trader_id, v_order_id, NULL, v_retailer_id, v_invoice_number, p_sale_date,
    v_total_kg, v_total_birds, CASE WHEN v_total_kg > 0 THEN v_subtotal / v_total_kg ELSE 0 END,
    v_subtotal, 0, 0, v_subtotal,
    0, v_subtotal, 'approved', p_created_by, now(), p_notes
  ) RETURNING id INTO v_invoice_id;

  -- Pass 2: order_items, invoice_items, and the stock movement — one per line
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_resolved_items) LOOP
    INSERT INTO order_items(order_id, trader_id, product_id, bird_count, total_weight, rate_per_kg, line_total)
    VALUES (
      v_order_id, p_trader_id, (v_item->>'product_id')::uuid,
      NULLIF(v_item->>'bird_count','')::int, (v_item->>'weight_kg')::numeric,
      (v_item->>'rate_per_kg')::numeric, (v_item->>'line_total')::numeric
    ) RETURNING id INTO v_order_item_id;

    INSERT INTO invoice_items(
      invoice_id, order_item_id, product_id, product_name, bird_count, weight_kg,
      rate_per_kg, line_total, applied_rate, rate_source, rate_zone_id, rate_zone_name,
      base_rate, adjustment_type, adjustment_value, house_cost_per_kg
    ) VALUES (
      v_invoice_id, v_order_item_id, (v_item->>'product_id')::uuid, v_item->>'product_name',
      NULLIF(v_item->>'bird_count','')::int, (v_item->>'weight_kg')::numeric,
      (v_item->>'rate_per_kg')::numeric, (v_item->>'line_total')::numeric,
      (v_item->>'rate_per_kg')::numeric, v_item->>'rate_source',
      NULLIF(v_item->>'zone_id','')::uuid, v_item->>'zone_name',
      (v_item->>'base_rate')::numeric, v_item->>'adjustment_type',
      (v_item->>'adjustment_value')::numeric, (v_item->>'house_cost_per_kg')::numeric
    );

    v_stock_ledger_id := fn_write_stock_movement(
      p_trader_id      => p_trader_id,
      p_product_id     => (v_item->>'product_id')::uuid,
      p_movement_type  => 'in_house_sale',
      p_quantity_birds => COALESCE(NULLIF(v_item->>'bird_count','')::int, 0),
      p_quantity_kg    => (v_item->>'weight_kg')::numeric,
      p_reference_type => 'invoice',
      p_reference_id   => v_invoice_id,
      p_entry_date     => p_sale_date,
      p_agent_id       => NULL,
      p_notes          => 'In-house stock point sale — invoice ' || v_invoice_number,
      p_created_by     => p_created_by
    );
  END LOOP;

  -- Payment collection (credit side of the ledger) — reuses record_payment,
  -- not duplicated here. Only called when something was actually collected.
  -- ★ FIX (Business Date audit): now passes p_sale_date through as
  -- record_payment's p_entry_date, so a backdated stock point sale's
  -- collection lands on the same day as the sale itself instead of always
  -- defaulting to CURRENT_DATE — keeping the debit (invoice) and credit
  -- (payment) sides of the ledger, Cash Flow, and Customer Ledger in sync.
  IF v_collected > 0 THEN
    PERFORM record_payment(
      p_trader_id, v_retailer_id, v_collected, p_payment_mode,
      v_invoice_id, v_order_id,
      'In-house sale payment — invoice ' || v_invoice_number,
      p_created_by,
      p_sale_date
    );
  END IF;

  -- Recompute order-level collected/balance from its invoice(s), same
  -- aggregation pattern process_return_v2 already uses for order totals.
  SELECT COALESCE(SUM(collected_amount), 0), COALESCE(SUM(GREATEST(balance_amount, 0)), 0)
  INTO v_order_collected, v_order_balance
  FROM invoices WHERE order_id = v_order_id AND status NOT IN ('cancelled','rejected');

  UPDATE orders SET collected_amount = v_order_collected, balance_amount = v_order_balance
  WHERE id = v_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order_id,
    'invoice_id', v_invoice_id,
    'invoice_number', v_invoice_number,
    'retailer_id', v_retailer_id,
    'is_walkin', v_is_walkin,
    'total_birds', v_total_birds,
    'total_kg', v_total_kg,
    'total_amount', v_subtotal,
    'collected_amount', v_order_collected,
    'balance_amount', v_order_balance,
    'doc_no', v_doc_no,
    'manual_doc_no', NULLIF(btrim(p_manual_doc_no), '')
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_in_house_sale_v1(uuid, jsonb, uuid, text, text, text, numeric, date, text, uuid, text, boolean) TO anon, authenticated, service_role;
