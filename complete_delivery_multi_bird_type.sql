-- Quick Entry with two (or more) bird types took all the stock from one type.
--
-- When no order line is picked, complete_delivery picked the line matching
-- the order's main product (orders.product_id = the first product entered).
-- For a Quick Entry of Broiler + Country that meant the delivery was treated
-- as "Broiler only": the stock trigger then took ALL birds/kg from Broiler and
-- nothing from Country, and the stock check only looked at Broiler.
--
-- Now, when no line is picked:
--   • the main-product line is picked only if the order has a single product;
--   • if the order has more than one bird type, stock is checked across all
--     of them (not just the main product's type).
-- With no line picked, the stock trigger already splits the delivery over
-- every line, so each bird type is deducted its own birds/kg.
-- Deliveries that pick a line (agent Delivery screen) are unchanged.
--
-- Patched in place; stops with an error if the function doesn't look as
-- expected. Safe to run twice.
DO $patch$
DECLARE
  d text;
  v_fn regprocedure;
  n int;
  v_old1 text := '    IF p_selected_order_item_id IS NULL AND v_product_id IS NOT NULL THEN';
  v_new1 text :=
'    -- Several bird types on the order and no line picked (e.g. Quick Entry):
    -- the delivery covers every line, so check stock across all bird types.
    IF p_selected_order_item_id IS NULL AND (
        SELECT COUNT(DISTINCT COALESCE(mp.parent_product_id, mp.id))
        FROM order_items oi JOIN master_products mp ON mp.id = oi.product_id
        WHERE oi.order_id = v_order_id) > 1 THEN
        v_product_family_id := NULL;
    END IF;

    -- Pick the main product''s line only when the order has a single product.
    IF p_selected_order_item_id IS NULL AND v_product_id IS NOT NULL
       AND (SELECT COUNT(DISTINCT product_id) FROM order_items
            WHERE order_id = v_order_id) <= 1 THEN';
  v_old2 text := '    ELSIF v_product_id IS NOT NULL THEN
        SELECT available_birds, available_kg INTO v_avail, v_avail_kg';
  v_new2 text := '    ELSIF v_product_id IS NOT NULL AND v_product_family_id IS NOT NULL THEN
        SELECT available_birds, available_kg INTO v_avail, v_avail_kg';
BEGIN
  SELECT oid::regprocedure INTO v_fn FROM pg_proc
   WHERE proname = 'complete_delivery' AND pronamespace = 'public'::regnamespace;
  d := pg_get_functiondef(v_fn);

  IF position('check stock across all bird types' in d) > 0 THEN
    RAISE NOTICE 'complete_delivery already handles multi bird type orders';
    RETURN;
  END IF;

  n := (length(d) - length(replace(d, v_old1, ''))) / length(v_old1);
  IF n <> 1 THEN
    RAISE EXCEPTION 'complete_delivery: expected 1 match for the line pick, found %', n;
  END IF;
  n := (length(d) - length(replace(d, v_old2, ''))) / length(v_old2);
  IF n <> 1 THEN
    RAISE EXCEPTION 'complete_delivery: expected 1 match for the kg check, found %', n;
  END IF;

  EXECUTE replace(replace(d, v_old1, v_new1), v_old2, v_new2);
END
$patch$;
