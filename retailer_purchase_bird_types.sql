-- Retailer Purchase report: bird type filter and bird-type-wise breakdown.
--
-- New, separate function (get_report_data is not changed). Same filters as the
-- report (dates, agent, retailer) plus an optional bird type. A bird type is
-- the main product: sizes such as Broiler Small / Broiler Medium count under
-- Broiler — the same level the DCs are recorded at, so Purchased KGS and
-- Sold KGS compare like with like.
--
-- Returns:
--   bird_types : bird types sold in the period (for the filter list)
--   by_type    : one row per bird type — orders, birds, kg, amount
--   summary / retailers / daily : the report's tables limited to the chosen
--                bird type (used by the screen when a bird type is picked)
--   shop_types : one row per shop and bird type — the printed sheet
--
-- Birds / kg come from the order lines. Amount = the approved invoice lines
-- for that bird type; orders not invoiced yet use the same rate preview the
-- report already uses. Collected / outstanding can't be split by bird type,
-- so they are not returned here.

CREATE OR REPLACE FUNCTION public.get_retailer_purchase_bird_types(
  p_trader_id uuid,
  p_from_date date,
  p_to_date date,
  p_agent_id uuid DEFAULT NULL,
  p_retailer_id uuid DEFAULT NULL,
  p_bird_type_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v json;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid() AND trader_id = p_trader_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Access denied.';
  END IF;

  WITH ord AS (
    SELECT o.id, o.order_date, o.retailer_id, o.manual_doc_no, o.remarks
    FROM orders o
    WHERE o.trader_id = p_trader_id
      AND o.order_date BETWEEN p_from_date AND p_to_date
      AND o.status NOT IN ('cancelled')
      AND (p_retailer_id IS NULL OR o.retailer_id = p_retailer_id)
      AND (p_agent_id IS NULL OR EXISTS (
            SELECT 1 FROM deliveries dl
            WHERE dl.order_id = o.id AND dl.trader_id = p_trader_id
              AND dl.delivery_agent_id = p_agent_id))
  ),
  -- Order lines rolled up to (order, bird type).
  items AS (
    SELECT oi.order_id, COALESCE(mp.parent_product_id, oi.product_id) AS type_id,
           SUM(COALESCE(oi.bird_count, 0)) AS birds,
           SUM(COALESCE(oi.total_weight, 0)) AS kg
    FROM order_items oi
    JOIN ord ON ord.id = oi.order_id
    LEFT JOIN master_products mp ON mp.id = oi.product_id
    GROUP BY 1, 2
  ),
  invoiced AS (
    SELECT DISTINCT i.order_id
    FROM invoices i
    WHERE i.trader_id = p_trader_id AND i.status IN ('approved', 'invoiced')
      AND i.order_id IN (SELECT id FROM ord)
  ),
  inv AS (
    SELECT i.order_id, COALESCE(mp.parent_product_id, ii.product_id) AS type_id,
           SUM(COALESCE(ii.line_total, 0)) AS amount,
           STRING_AGG(DISTINCT to_char(ii.rate_per_kg, 'FM999990.00'), ', ') AS rates
    FROM invoice_items ii
    JOIN invoices i ON i.id = ii.invoice_id
    LEFT JOIN master_products mp ON mp.id = ii.product_id
    WHERE i.trader_id = p_trader_id AND i.status IN ('approved', 'invoiced')
      AND i.order_id IN (SELECT id FROM ord)
    GROUP BY 1, 2
  ),
  est AS (
    SELECT o.id AS order_id, COALESCE(mp.parent_product_id, pv.product_id) AS type_id,
           SUM(COALESCE(pv.line_total, 0)) AS amount,
           STRING_AGG(DISTINCT to_char(pv.rate, 'FM999990.00'), ', ') AS rates
    FROM ord o
    CROSS JOIN LATERAL get_order_rate_preview(o.id, o.order_date) pv
    LEFT JOIN master_products mp ON mp.id = pv.product_id
    WHERE o.id NOT IN (SELECT order_id FROM invoiced)
    GROUP BY 1, 2
  ),
  lines AS (
    SELECT it.order_id, it.type_id, it.birds, it.kg,
           CASE WHEN iv.order_id IS NOT NULL THEN COALESCE(inv.amount, 0)
                ELSE COALESCE(est.amount, 0) END AS amount,
           CASE WHEN iv.order_id IS NOT NULL THEN inv.rates ELSE est.rates END AS rates,
           ord.order_date, ord.retailer_id, ord.manual_doc_no, ord.remarks
    FROM items it
    JOIN ord ON ord.id = it.order_id
    LEFT JOIN invoiced iv ON iv.order_id = it.order_id
    LEFT JOIN inv ON inv.order_id = it.order_id AND inv.type_id = it.type_id
    LEFT JOIN est ON est.order_id = it.order_id AND est.type_id = it.type_id
  ),
  fl AS (
    SELECT * FROM lines WHERE p_bird_type_id IS NULL OR type_id = p_bird_type_id
  )
  SELECT json_build_object(
    'report', 'retailer_purchase_bird_types',
    'bird_type_id', p_bird_type_id,

    'bird_types', (
      SELECT COALESCE(json_agg(json_build_object('id', t.type_id, 'name', t.name) ORDER BY t.name), '[]'::json)
      FROM (SELECT DISTINCT l.type_id, COALESCE(mp.name, 'Unknown') AS name
            FROM lines l LEFT JOIN master_products mp ON mp.id = l.type_id) t
    ),

    'by_type', (
      SELECT COALESCE(json_agg(row_to_json(b) ORDER BY b.kg DESC), '[]'::json)
      FROM (
        SELECT fl.type_id AS bird_type_id, COALESCE(mp.name, 'Unknown') AS bird_type,
               COUNT(DISTINCT fl.order_id) AS orders,
               SUM(fl.birds) AS birds, SUM(fl.kg) AS kg, SUM(fl.amount) AS amount
        FROM fl LEFT JOIN master_products mp ON mp.id = fl.type_id
        GROUP BY fl.type_id, mp.name
      ) b
    ),

    'summary', (
      SELECT json_build_object(
        'total_orders', COUNT(DISTINCT fl.order_id),
        'total_kg', COALESCE(SUM(fl.kg), 0),
        'total_birds', COALESCE(SUM(fl.birds), 0),
        'total_billed', COALESCE(SUM(fl.amount), 0))
      FROM fl
    ),

    'retailers', (
      SELECT COALESCE(json_agg(row_to_json(r) ORDER BY r.total_kg DESC), '[]'::json)
      FROM (
        SELECT rt.shop_name, rt.owner_name, rt.phone,
               COUNT(DISTINCT fl.order_id) AS orders,
               SUM(fl.kg) AS total_kg,
               SUM(fl.birds) AS total_birds,
               STRING_AGG(DISTINCT NULLIF(btrim(fl.manual_doc_no), ''), ', ') AS doc_nos,
               (SELECT STRING_AGG(DISTINCT x, ', ')
                  FROM fl f2, unnest(string_to_array(f2.rates, ', ')) x
                 WHERE f2.retailer_id = rt.id) AS rates,
               SUM(fl.amount) AS billed
        FROM fl JOIN retailers rt ON rt.id = fl.retailer_id
        GROUP BY rt.id, rt.shop_name, rt.owner_name, rt.phone
      ) r
    ),

    -- One row per shop and bird type (the printed Retailer Purchase sheet),
    -- by shop name, then bird type.
    'shop_types', (
      SELECT COALESCE(json_agg(row_to_json(s) ORDER BY lower(s.shop_name), lower(s.bird_type)), '[]'::json)
      FROM (
        SELECT rt.shop_name, COALESCE(mp.name, 'Unknown') AS bird_type,
               COUNT(DISTINCT fl.order_id) AS orders,
               SUM(fl.kg) AS total_kg,
               SUM(fl.birds) AS total_birds,
               STRING_AGG(DISTINCT NULLIF(btrim(fl.manual_doc_no), ''), ', ') AS doc_nos,
               (SELECT STRING_AGG(DISTINCT x, ', ')
                  FROM fl f2, unnest(string_to_array(f2.rates, ', ')) x
                 WHERE f2.retailer_id = rt.id AND f2.type_id = fl.type_id) AS rates,
               SUM(fl.amount) AS billed
        FROM fl
        JOIN retailers rt ON rt.id = fl.retailer_id
        LEFT JOIN master_products mp ON mp.id = fl.type_id
        GROUP BY rt.id, rt.shop_name, fl.type_id, mp.name
      ) s
    ),

    'daily', (
      SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.order_date DESC), '[]'::json)
      FROM (
        SELECT fl.order_date, rt.shop_name,
               SUM(fl.kg) AS kg, SUM(fl.birds) AS birds,
               SUM(fl.amount) AS billed,
               CASE WHEN SUM(fl.kg) > 0 THEN round(SUM(fl.amount) / SUM(fl.kg), 2) ELSE 0 END AS rate,
               MAX(fl.remarks) AS order_remarks
        FROM fl JOIN retailers rt ON rt.id = fl.retailer_id
        GROUP BY fl.order_id, fl.order_date, rt.shop_name
      ) d
    )
  ) INTO v;

  RETURN v;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_retailer_purchase_bird_types(uuid, date, date, uuid, uuid, uuid) TO authenticated;
