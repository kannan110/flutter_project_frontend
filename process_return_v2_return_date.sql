-- Returns: use the Return Date picked in the app, not today's date.
-- process_return_v2 received p_return_date but wrote CURRENT_DATE into
-- return_entries.return_date, stock_ledger.entry_date and
-- credit_notes.credit_date (+ the credit note number's month). The customer
-- ledger row (trg_credit_to_ledger) copies credit_date, so it showed today too.
-- Only change: v_date := COALESCE(p_return_date, CURRENT_DATE) used in those
-- places. Everything else is unchanged.
CREATE OR REPLACE FUNCTION public.process_return_v2(p_trader_id uuid, p_delivery_id uuid, p_retailer_id uuid, p_agent_id uuid, p_return_type text, p_bird_count integer, p_weight_kg numeric, p_rate_per_kg numeric, p_reason text, p_processed_by uuid, p_product_id uuid, p_return_date date, p_returned_to text, p_stock_credited boolean, p_credit_note_amount numeric)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$DECLARE
  v_return_id  uuid;
  v_trader_id  uuid;
  v_order_id   uuid;
  v_product_id uuid;
  v_invoice_id uuid;
  v_cn_number text;
  v_date       date := COALESCE(p_return_date, CURRENT_DATE);
BEGIN
  -- Get trader_id from delivery
  SELECT trader_id, order_id INTO v_trader_id, v_order_id
  FROM deliveries WHERE id = p_delivery_id;

  IF v_trader_id IS NULL THEN
    RAISE EXCEPTION 'Delivery not found: %', p_delivery_id;
  END IF;

  -- Validate: return cannot exceed delivered
  IF p_return_type = 'same_batch' THEN
    DECLARE v_delivered int;
    BEGIN
      SELECT delivered_bird_count INTO v_delivered FROM deliveries WHERE id = p_delivery_id;
      IF p_bird_count > v_delivered THEN
        RAISE EXCEPTION 'Return count (%) exceeds delivered count (%)', p_bird_count, v_delivered;
      END IF;
    END;
  END IF;

  -- Insert return entry
  INSERT INTO return_entries(
    trader_id, delivery_id, order_id, retailer_id, agent_id,
    return_type, return_date, bird_count, weight_kg, reason,
    status, processed_at, processed_by,stock_credited,credit_note_amount,product_id
  ) VALUES (
    v_trader_id, p_delivery_id, v_order_id, p_retailer_id, p_agent_id,
    p_return_type, v_date, p_bird_count, p_weight_kg, p_reason,
    'processed', now(), p_processed_by,p_stock_credited,p_credit_note_amount,p_product_id
  ) RETURNING id INTO v_return_id;

  -- Get product_id for stock entry
  SELECT oi.product_id INTO v_product_id
  FROM order_items oi WHERE oi.order_id = v_order_id LIMIT 1;

  -- Stock update for same_batch: adjust delivery counts
  IF p_return_type = 'same_batch' THEN
    UPDATE deliveries SET
      delivered_bird_count = GREATEST(0, delivered_bird_count - p_bird_count),
      delivered_total_weight = GREATEST(0, delivered_total_weight - p_weight_kg),
      returned_same_batch_count = returned_same_batch_count + p_bird_count,
      returned_same_batch_weight = returned_same_batch_weight + p_weight_kg
    WHERE id = p_delivery_id;

    -- Add returned birds back to stock
    INSERT INTO stock_ledger(trader_id, product_id, entry_date, movement_type,
      quantity_birds, quantity_kg, reference_type, reference_id, notes)
    VALUES (v_trader_id, v_product_id, v_date, 'returned_in',
      p_bird_count, p_weight_kg, 'return', v_return_id,
      'Same-batch return from retailer');

  --Add Creditnotes
    -- Get invoice_id for creditnote entry
    SELECT oi.id INTO v_invoice_id
    FROM invoices oi WHERE oi.delivery_id = p_delivery_id;

    v_cn_number := next_credit_note_number(v_trader_id, v_date);

    INSERT INTO credit_notes(
    trader_id, retailer_id, return_id,invoice_id,credit_number,credit_date,quantity_kg,bird_count,
    rate_per_kg,total_amount,status,product_id
  ) VALUES (
    v_trader_id, p_retailer_id, v_return_id,v_invoice_id,v_cn_number,v_date,
    p_weight_kg,p_bird_count,p_rate_per_kg,p_credit_note_amount,'issued',p_product_id
  );

  ELSIF p_return_type = 'old_stock' THEN
    -- Old stock return: just add to stock, log old batch return
    UPDATE deliveries SET
      returned_old_stock_count = returned_old_stock_count + p_bird_count,
      returned_old_stock_weight = returned_old_stock_weight + p_weight_kg
    WHERE id = p_delivery_id;

    INSERT INTO stock_ledger(trader_id, product_id, entry_date, movement_type,
      quantity_birds, quantity_kg, reference_type, reference_id, notes)
    VALUES (v_trader_id, v_product_id, v_date, 'returned_in',
      p_bird_count, p_weight_kg, 'return', v_return_id,
      'Old-stock return — added back to inventory');

    UPDATE return_entries SET stock_credited = true WHERE id = v_return_id;
  END IF;

  RETURN v_return_id;
END;$function$;
