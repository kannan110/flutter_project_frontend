-- Quick Entry: Rate/kg typed by the trader is used on the invoice.
--
-- 1. agent_create_instant_order_multi: an item may carry "rate_per_kg".
--    When > 0 it is stored on order_items.rate_per_kg with rate_source
--    'manual' (previously rate_per_kg was always NULL). Items without it are
--    unchanged.
-- 2. approve_delivery_and_order, automatic-rate path (no p_item_rates, e.g.
--    Approve All): an order item with rate_source 'manual' keeps its stored
--    rate instead of being re-priced. Every other item is priced exactly as
--    before. (The single Approve screen already starts from the stored rate.)
--
-- Patches only those two spots inside the live function definitions and
-- stops with an error if either function doesn't match the expected text.
-- Safe to run twice (skips a function that is already patched).
DO $patch$
DECLARE
  d text;
  n int;
  v_create regprocedure := 'public.agent_create_instant_order_multi(uuid,uuid,jsonb,text,text,text,uuid,text,timestamp with time zone,uuid,text,text,boolean)'::regprocedure;
  v_approve regprocedure := 'public.approve_delivery_and_order(uuid,numeric,numeric,uuid,text,date,jsonb)'::regprocedure;
  v_pat text := 'bird_count, total_weight, rate_per_kg(\s*\)\s*VALUES\s*\(\s*v_order_id, v_agent\.trader_id, v_product_id,\s*COALESCE\(v_birds, 0\), v_weight, )NULL';
  v_anchor text := 'IF v_oi_rate <= 0 THEN RAISE EXCEPTION ''No rate found for product %.';
BEGIN
  -- 1. Store the typed rate at order creation.
  d := pg_get_functiondef(v_create);
  IF position('rate_per_kg, rate_source' in d) > 0 THEN
    RAISE NOTICE 'agent_create_instant_order_multi already patched';
  ELSE
    SELECT count(*) INTO n FROM regexp_matches(d, v_pat, 'g');
    IF n <> 1 THEN
      RAISE EXCEPTION 'agent_create_instant_order_multi: expected 1 match, found %', n;
    END IF;
    d := regexp_replace(d, v_pat,
      'bird_count, total_weight, rate_per_kg, rate_source\1'
      || $r$CASE WHEN NULLIF(v_item->>'rate_per_kg','')::numeric > 0 THEN NULLIF(v_item->>'rate_per_kg','')::numeric END,
            CASE WHEN NULLIF(v_item->>'rate_per_kg','')::numeric > 0 THEN 'manual' END$r$);
    EXECUTE d;
  END IF;

  -- 2. Keep a manual item rate on automatic approval.
  d := pg_get_functiondef(v_approve);
  IF position('Rate typed in Quick Entry' in d) > 0 THEN
    RAISE NOTICE 'approve_delivery_and_order already patched';
  ELSE
    n := (length(d) - length(replace(d, v_anchor, ''))) / length(v_anchor);
    IF n <> 1 THEN
      RAISE EXCEPTION 'approve_delivery_and_order: expected 1 match, found %', n;
    END IF;
    d := replace(d, v_anchor,
      $r$-- Rate typed in Quick Entry (rate_source 'manual') wins over pricing.
        IF EXISTS (SELECT 1 FROM order_items WHERE id = v_oi_id AND rate_source = 'manual' AND rate_per_kg > 0) THEN
          v_oi_rate := (SELECT rate_per_kg FROM order_items WHERE id = v_oi_id);
          v_resolved.rate_source := 'manual';
          v_resolved.pricing_type := 'fixed';
          v_resolved.adjustment_value := 0;
        END IF;
        $r$ || v_anchor);
    EXECUTE d;
  END IF;
END
$patch$;
