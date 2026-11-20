-- Returns: each product line gets its own credit note amount.
--
-- process_return_batch_v1 passed the WHOLE return's total (p_credit_note_amount)
-- to process_return_v2 for every line, so a return of 2 products created two
-- credit notes each carrying the full total — the customer was credited twice.
-- (A return of one product was always right.)
--
-- Now each line's amount is:
--   1. the item's own "credit_amount" (sent by the Return screen = weight × rate,
--      using the rate the user may have edited), else
--   2. weight × rate_per_kg of the item, else
--   3. the total, only when the return has a single line (old behaviour).
-- Everything else is unchanged.

CREATE OR REPLACE FUNCTION public.process_return_batch_v1(p_trader_id uuid, p_delivery_id uuid, p_retailer_id uuid, p_agent_id uuid, p_return_type text, p_return_date date, p_reason text, p_processed_by uuid, p_items jsonb, p_returned_to text, p_stock_credited boolean, p_credit_note_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_item        jsonb;
  v_return_id   uuid;
  v_return_ids  uuid[] := '{}';
  v_item_count  int := 0;
  v_lines       int;
  v_rate        numeric;
  v_amount      numeric;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one product line with a return quantity is required.';
  END IF;
  v_lines := jsonb_array_length(p_items);

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_item_count := v_item_count + 1;

    IF (v_item->>'product_id') IS NULL THEN
      RAISE EXCEPTION 'Product % is missing a product_id.', v_item_count;
    END IF;

    v_rate := NULLIF(v_item->>'rate_per_kg', '')::numeric;
    v_amount := COALESCE(
      NULLIF(v_item->>'credit_amount', '')::numeric,
      round((v_item->>'weight_kg')::numeric * v_rate, 2),
      CASE WHEN v_lines = 1 THEN p_credit_note_amount END
    );
    IF v_amount IS NULL THEN
      RAISE EXCEPTION 'Product % has no rate, so its credit amount cannot be worked out.', v_item_count;
    END IF;

    v_return_id := process_return_v2(
      p_trader_id,
      p_delivery_id,
      p_retailer_id,
      p_agent_id,
      p_return_type,
      (v_item->>'bird_count')::int,
      (v_item->>'weight_kg')::numeric,
      v_rate,
      p_reason,
      p_processed_by,
      (v_item->>'product_id')::uuid,
      p_return_date,
      p_returned_to,
      p_stock_credited,
      v_amount
    );
    v_return_ids := array_append(v_return_ids, v_return_id);
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'return_ids', to_jsonb(v_return_ids),
    'items_processed', v_item_count,
    'total_credit_amount', (
      SELECT COALESCE(SUM(credit_note_amount),0) FROM return_entries WHERE id = ANY(v_return_ids)
    )
  );
END;
$function$;
