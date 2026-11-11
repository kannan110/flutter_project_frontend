-- get_report_data: current version, copied from staging (jhlraqsntgrpwctgpuzc) on
-- 2026-11-11. Includes the Retailer Purchase report changes (Doc No(s) and
-- Rate columns, invoice aggregation, estimated amount/rate for orders not yet
-- invoiced) plus every later staging change to this function.
-- Run on production to bring get_report_data in line with staging.

CREATE OR REPLACE FUNCTION public.get_report_data(p_trader_id uuid, p_from_date date, p_to_date date, p_report text, p_agent_id uuid DEFAULT NULL::uuid, p_retailer_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
AS $function$DECLARE v json;
DECLARE v_pnl jsonb;
BEGIN

IF p_report = 'daily_summary' THEN
  v_pnl := get_pnl_statement(p_trader_id, p_from_date, p_to_date, 'daily');
  SELECT json_build_object(
    'report','daily_summary','from_date',p_from_date,'to_date',p_to_date,
    'summary', json_build_object(
      'total_birds_dc',    (SELECT COALESCE(SUM(dcr.final_bird_count),0)  FROM delivery_challans_reconciled dcr WHERE dcr.trader_id=p_trader_id AND dcr.dc_date BETWEEN p_from_date AND p_to_date),
      'total_gross_wt',    (SELECT COALESCE(SUM(gross_weight),0)  FROM delivery_challans WHERE trader_id=p_trader_id AND dc_date BETWEEN p_from_date AND p_to_date),
      'total_tare_wt',     (SELECT COALESCE(SUM(empty_crate_weight),0) FROM delivery_challans WHERE trader_id=p_trader_id AND dc_date BETWEEN p_from_date AND p_to_date),
      'total_net_wt',      (SELECT COALESCE(SUM(dcr.final_net_weight),0) FROM delivery_challans_reconciled dcr WHERE dcr.trader_id=p_trader_id AND dcr.dc_date BETWEEN p_from_date AND p_to_date),
      'total_birds_del',   (SELECT COALESCE(SUM(delivered_bird_count),0) FROM deliveries WHERE trader_id=p_trader_id AND status='delivered' AND DATE(delivered_at) BETWEEN p_from_date AND p_to_date),
      'total_del_weight',  (SELECT COALESCE(SUM(delivered_total_weight),0) FROM deliveries WHERE trader_id=p_trader_id AND status='delivered' AND DATE(delivered_at) BETWEEN p_from_date AND p_to_date),
      'gross_revenue',     (SELECT COALESCE(SUM(total_amount),0)   FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced')),
      'returns_amount',    (SELECT COALESCE(SUM(cn.total_amount),0)
                            FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                            WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued'
                              AND cn.credit_date BETWEEN p_from_date AND p_to_date),
      'total_revenue',     (SELECT COALESCE(SUM(total_amount),0)   FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced'))
                          - (SELECT COALESCE(SUM(cn.total_amount),0)
                             FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                             WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued'
                               AND cn.credit_date BETWEEN p_from_date AND p_to_date),
      'total_collected',   (SELECT COALESCE(SUM(total_amount),0)   FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced')),
      'total_pending',     (SELECT COALESCE(SUM(balance_amount),0) FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced') AND balance_amount>0),
      'total_outstanding', (SELECT COALESCE(SUM(CASE WHEN entry_type='debit' THEN amount ELSE -amount END),0) FROM ledger_entries WHERE trader_id=p_trader_id),
      'total_mortality',   (SELECT COALESCE(SUM(quantity_birds),0) FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type='mortality' AND entry_date BETWEEN p_from_date AND p_to_date),
      'total_expenses',    COALESCE((v_pnl->'summary'->>'total_expenses')::numeric, 0)
    ),
    'daily', (
      SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.dt DESC),'[]'::json) FROM (
        SELECT dates.dt,
          COALESCE((SELECT SUM(dcr.final_bird_count) FROM delivery_challans_reconciled dcr WHERE dcr.trader_id=p_trader_id AND dcr.dc_date=dates.dt),0) AS dc_birds,
          COALESCE((SELECT SUM(dc.gross_weight)    FROM delivery_challans dc WHERE dc.trader_id=p_trader_id AND dc.dc_date=dates.dt),0) AS gross_wt,
          COALESCE((SELECT SUM(dc.empty_crate_weight) FROM delivery_challans dc WHERE dc.trader_id=p_trader_id AND dc.dc_date=dates.dt),0) AS tare_wt,
          COALESCE((SELECT SUM(dcr.final_net_weight) FROM delivery_challans_reconciled dcr WHERE dcr.trader_id=p_trader_id AND dcr.dc_date=dates.dt),0) AS net_wt,
          COALESCE((SELECT SUM(d2.delivered_bird_count) FROM deliveries d2 WHERE d2.trader_id=p_trader_id AND d2.status='delivered' AND DATE(d2.delivered_at)=dates.dt),0) AS del_birds,
          COALESCE((SELECT SUM(d2.delivered_total_weight) FROM deliveries d2 WHERE d2.trader_id=p_trader_id AND d2.status='delivered' AND DATE(d2.delivered_at)=dates.dt),0) AS del_weight,
          COALESCE((SELECT SUM(i.total_amount) FROM invoices i WHERE i.trader_id=p_trader_id AND i.invoice_date=dates.dt AND i.status IN ('approved','invoiced')),0) AS gross_revenue,
          COALESCE((SELECT SUM(cn.total_amount) FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                    WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued' AND cn.credit_date=dates.dt),0) AS returns_amount,
          COALESCE((SELECT SUM(i.total_amount) FROM invoices i WHERE i.trader_id=p_trader_id AND i.invoice_date=dates.dt AND i.status IN ('approved','invoiced')),0)
            - COALESCE((SELECT SUM(cn.total_amount) FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                    WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued' AND cn.credit_date=dates.dt),0) AS revenue,
          COALESCE((SELECT SUM(i.collected_amount) FROM invoices i WHERE i.trader_id=p_trader_id AND i.invoice_date=dates.dt AND i.status IN ('approved','invoiced')),0) AS collected,
          COALESCE((SELECT SUM(i.balance_amount) FROM invoices i WHERE i.trader_id=p_trader_id AND i.invoice_date=dates.dt AND i.status IN ('approved','invoiced') AND i.balance_amount>0),0) AS pending
        FROM generate_series(p_from_date, p_to_date, '1 day'::interval) AS dates(dt)
      ) d)
  ) INTO v;

ELSIF p_report = 'stock_reconciliation' THEN
  SELECT json_build_object(
    'report','stock_reconciliation','from_date',p_from_date,'to_date',p_to_date,
    'summary', json_build_object(
      'opening',         (SELECT COALESCE(SUM(quantity_birds),0) FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type='opening'       AND entry_date < p_from_date),
      'dc_loaded',       (SELECT COALESCE(SUM(quantity_birds),0) FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type IN ('purchased','transferred_in') AND entry_date BETWEEN p_from_date AND p_to_date),
      'dc_loaded_kg',    (SELECT COALESCE(SUM(quantity_kg),0)    FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type IN ('purchased','transferred_in') AND entry_date BETWEEN p_from_date AND p_to_date),
      'delivered',       (SELECT COALESCE(SUM(quantity_birds),0) FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type='delivered'      AND entry_date BETWEEN p_from_date AND p_to_date),
      'delivered_kg',    (SELECT COALESCE(SUM(quantity_kg),0)    FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type='delivered'      AND entry_date BETWEEN p_from_date AND p_to_date),
      'returned', (
        SELECT COALESCE(SUM(quantity_birds),0) FROM stock_ledger
        WHERE trader_id=p_trader_id
          AND movement_type IN ('returned_in','shift_close_return')
          AND entry_date BETWEEN p_from_date AND p_to_date
      ),
      'returned_kg', (
        SELECT COALESCE(SUM(quantity_kg),0) FROM stock_ledger
        WHERE trader_id=p_trader_id
          AND movement_type IN ('returned_in','shift_close_return')
          AND entry_date BETWEEN p_from_date AND p_to_date
      ),
      'mortality',       (SELECT COALESCE(SUM(quantity_birds),0) FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type='mortality'      AND entry_date BETWEEN p_from_date AND p_to_date),
      'mortality_kg',    (SELECT COALESCE(SUM(quantity_kg),0)    FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type='mortality'      AND entry_date BETWEEN p_from_date AND p_to_date),
      'transferred_out', (SELECT COALESCE(SUM(quantity_birds),0) FROM stock_ledger WHERE trader_id=p_trader_id AND movement_type='transferred_out' AND entry_date BETWEEN p_from_date AND p_to_date),
      'shrinkage_kg',    (SELECT COALESCE(SUM(unaccounted_loss_kg),0) FROM batch_loss_summary WHERE trader_id=p_trader_id AND calculated_at::date BETWEEN p_from_date AND p_to_date),
      'closing',         (SELECT COALESCE(available_birds,0) FROM get_available_stock(p_trader_id) LIMIT 1)
    ),
    'daily', (
      SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.dt DESC),'[]'::json) FROM (
        SELECT dates.dt,
          COALESCE((SELECT SUM(sl.quantity_birds) FROM stock_ledger sl WHERE sl.trader_id=p_trader_id AND sl.movement_type IN ('purchased','transferred_in') AND sl.entry_date=dates.dt),0) AS dc_birds,
          COALESCE((SELECT SUM(sl.quantity_kg)    FROM stock_ledger sl WHERE sl.trader_id=p_trader_id AND sl.movement_type IN ('purchased','transferred_in') AND sl.entry_date=dates.dt),0) AS dc_kg,
          COALESCE((SELECT SUM(sl.quantity_birds) FROM stock_ledger sl WHERE sl.trader_id=p_trader_id AND sl.movement_type='delivered'       AND sl.entry_date=dates.dt),0) AS del_birds,
          COALESCE((SELECT SUM(sl.quantity_kg)    FROM stock_ledger sl WHERE sl.trader_id=p_trader_id AND sl.movement_type='delivered'       AND sl.entry_date=dates.dt),0) AS del_kg,
          COALESCE((SELECT SUM(sl.quantity_birds) FROM stock_ledger sl WHERE sl.trader_id=p_trader_id AND sl.movement_type IN ('returned_in','shift_close_return') AND sl.entry_date=dates.dt),0) AS ret_birds,
          COALESCE((SELECT SUM(sl.quantity_birds) FROM stock_ledger sl WHERE sl.trader_id=p_trader_id AND sl.movement_type='mortality'        AND sl.entry_date=dates.dt),0) AS mort_birds,
          COALESCE((SELECT SUM(sl.quantity_birds) FROM stock_ledger sl WHERE sl.trader_id=p_trader_id AND sl.movement_type='transferred_out'  AND sl.entry_date=dates.dt),0) AS transfer_out
        FROM generate_series(p_from_date, p_to_date, '1 day'::interval) AS dates(dt)
      ) d)
  ) INTO v;

ELSIF p_report = 'shrinkage' THEN
  SELECT json_build_object(
    'report','shrinkage','from_date',p_from_date,'to_date',p_to_date,
    'summary', json_build_object(
      'total_dc_kg',             COALESCE(SUM(bls.dc_total_weight_kg),0),
      'total_delivered_kg',      COALESCE(SUM(bls.delivered_weight_kg),0),
      'total_returned_kg',       COALESCE(SUM(bls.returned_weight_kg),0),
      'total_mortality_kg',      COALESCE(SUM(bls.mortality_weight_kg),0),
      'total_unaccounted_kg',    COALESCE(SUM(bls.unaccounted_loss_kg),0),
      'total_shrinkage_kg',      COALESCE(SUM(bls.unaccounted_loss_kg),0),
      'avg_loss_pct',            CASE WHEN COALESCE(SUM(bls.dc_total_weight_kg),0)>0
                                   THEN ROUND(SUM(bls.unaccounted_loss_kg)/SUM(bls.dc_total_weight_kg)*100,2)
                                   ELSE 0 END,
      'high_loss_shifts',        COUNT(CASE WHEN bls.loss_percent>=2 THEN 1 END),
      'shift_count',             COUNT(bls.id),
      'total_shrinkage_loss_amount', COALESCE((
        SELECT SUM(ROUND(bls4.unaccounted_loss_kg * bc4.cost_per_kg, 2))
        FROM batch_loss_summary bls4
        JOIN delivery_shifts ds4 ON ds4.id = bls4.shift_id
        LEFT JOIN batch_costing bc4 ON bc4.batch_id = bls4.batch_id
        WHERE bls4.trader_id=p_trader_id AND DATE(ds4.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR bls4.agent_id=p_agent_id) AND bc4.cost_per_kg IS NOT NULL
      ), 0),
      'total_mortality_loss_amount', COALESCE((
        SELECT SUM(bc4.mortality_loss_amount)
        FROM batch_loss_summary bls4
        JOIN delivery_shifts ds4 ON ds4.id=bls4.shift_id
        JOIN batch_costing bc4 ON bc4.batch_id=bls4.batch_id
        WHERE bls4.trader_id=p_trader_id AND DATE(ds4.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR bls4.agent_id=p_agent_id)
      ), 0)
    ),
    'rows', (
      SELECT COALESCE(json_agg(row_to_json(r) ORDER BY r.shift_date DESC),'[]'::json) FROM (
        SELECT DATE(ds.shift_end_at) AS shift_date, da.name AS agent_name,
          bls2.dc_total_birds, bls2.dc_total_weight_kg,
          bls2.delivered_birds, bls2.delivered_weight_kg,
          bls2.returned_weight_kg, bls2.mortality_birds, bls2.mortality_weight_kg,
          bls2.unaccounted_loss_kg, bls2.unaccounted_loss_kg AS shrinkage_kg,
          bls2.mortality_loss_kg, bls2.operational_loss_kg, bls2.unexplained_loss_kg,
          bls2.loss_percent,
          bc2.mortality_loss_amount, bc2.operational_loss_amount, bc2.unexplained_loss_amount,
          CASE WHEN bc2.cost_per_kg IS NOT NULL THEN ROUND(bls2.unaccounted_loss_kg * bc2.cost_per_kg, 2) ELSE NULL END AS shrinkage_loss_amount
        FROM batch_loss_summary bls2
        JOIN delivery_shifts ds ON ds.id=bls2.shift_id
        JOIN delivery_agents da ON da.id=bls2.agent_id
        LEFT JOIN batch_costing bc2 ON bc2.batch_id=bls2.batch_id
        WHERE bls2.trader_id=p_trader_id AND DATE(ds.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR bls2.agent_id=p_agent_id)
      ) r)
  ) INTO v
  FROM batch_loss_summary bls
  JOIN delivery_shifts ds ON ds.id=bls.shift_id
  WHERE bls.trader_id=p_trader_id AND DATE(ds.shift_end_at) BETWEEN p_from_date AND p_to_date
    AND (p_agent_id IS NULL OR bls.agent_id=p_agent_id);

ELSIF p_report = 'mortality' THEN
  SELECT json_build_object(
    'report','mortality','from_date',p_from_date,'to_date',p_to_date,
    'summary', json_build_object(
      'total_mortality_birds', COALESCE((
        SELECT SUM(sl.quantity_birds) FROM stock_ledger sl
        WHERE sl.trader_id=p_trader_id AND sl.movement_type='mortality'
          AND sl.entry_date BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR sl.agent_id=p_agent_id)
      ), 0),
      'total_mortality_kg', COALESCE((
        SELECT SUM(sl.quantity_kg) FROM stock_ledger sl
        WHERE sl.trader_id=p_trader_id AND sl.movement_type='mortality'
          AND sl.entry_date BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR sl.agent_id=p_agent_id)
      ), 0),
      'total_dc_birds', COALESCE((
        SELECT SUM(sl.quantity_birds) FROM stock_ledger sl
        WHERE sl.trader_id=p_trader_id AND sl.movement_type='purchased'
          AND sl.entry_date BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR sl.agent_id=p_agent_id)
      ), 0),
      'mortality_rate_pct', CASE WHEN COALESCE((
        SELECT SUM(sl.quantity_birds) FROM stock_ledger sl
        WHERE sl.trader_id=p_trader_id AND sl.movement_type='purchased'
          AND sl.entry_date BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR sl.agent_id=p_agent_id)
      ),0) > 0
      THEN ROUND(
        COALESCE((SELECT SUM(sl2.quantity_birds) FROM stock_ledger sl2 WHERE sl2.trader_id=p_trader_id AND sl2.movement_type='mortality' AND sl2.entry_date BETWEEN p_from_date AND p_to_date AND (p_agent_id IS NULL OR sl2.agent_id=p_agent_id)),0)::numeric /
        (SELECT SUM(sl3.quantity_birds) FROM stock_ledger sl3 WHERE sl3.trader_id=p_trader_id AND sl3.movement_type='purchased' AND sl3.entry_date BETWEEN p_from_date AND p_to_date AND (p_agent_id IS NULL OR sl3.agent_id=p_agent_id))
        * 100, 2) ELSE 0 END,
      'total_mortality_loss_amount', COALESCE((
        SELECT SUM(bc4.mortality_loss_amount)
        FROM batch_costing bc4
        JOIN delivery_batches db4 ON db4.id=bc4.batch_id
        JOIN delivery_shifts ds4 ON ds4.id=db4.shift_id
        WHERE bc4.trader_id=p_trader_id
          AND DATE(ds4.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR ds4.delivery_agent_id=p_agent_id)
          AND bc4.cost_per_kg IS NOT NULL AND bc4.cost_per_kg > 0
      ), 0)
    ),
    'rows', (
      SELECT COALESCE(json_agg(row_to_json(r) ORDER BY r.del_date DESC),'[]'::json) FROM (
        SELECT DATE(d2.delivered_at) AS del_date, da.name AS agent_name,
          rt.shop_name, d2.pickup_bird_count AS dc_birds,
          d2.delivered_bird_count AS del_birds, d2.mortality_birds,
          d2.mortality_weight_kg, d2.weak_birds, d2.rejected_birds, d2.mortality_proof_url,
          'delivery' AS mortality_source,
          CASE WHEN bc2.cost_per_kg IS NOT NULL THEN ROUND(d2.mortality_weight_kg * bc2.cost_per_kg, 2) ELSE NULL END AS mortality_loss_amount
        FROM deliveries d2
        LEFT JOIN delivery_agents da ON da.id=d2.delivery_agent_id
        LEFT JOIN orders o ON o.id=d2.order_id
        LEFT JOIN retailers rt ON rt.id=o.retailer_id
        LEFT JOIN batch_costing bc2 ON bc2.batch_id=d2.batch_id
        WHERE d2.trader_id=p_trader_id AND d2.status='delivered'
          AND DATE(d2.delivered_at) BETWEEN p_from_date AND p_to_date
          AND d2.mortality_birds > 0
          AND (p_agent_id IS NULL OR d2.delivery_agent_id=p_agent_id)

        UNION ALL

        SELECT sl.entry_date AS del_date, da2.name AS agent_name,
          'Return transport' AS shop_name,
          0 AS dc_birds, 0 AS del_birds,
          sl.quantity_birds AS mortality_birds,
          sl.quantity_kg AS mortality_weight_kg,
          0 AS weak_birds, 0 AS rejected_birds, NULL AS mortality_proof_url,
          'return' AS mortality_source,
          NULL AS mortality_loss_amount
        FROM stock_ledger sl
        JOIN delivery_agents da2 ON da2.id=sl.agent_id
        WHERE sl.trader_id=p_trader_id
          AND sl.movement_type='mortality'
          AND sl.notes ILIKE '%return%'
          AND sl.entry_date BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR sl.agent_id=p_agent_id)
      ) r)
  ) INTO v;

ELSIF p_report = 'delivery_history' THEN
  SELECT json_build_object(
    'report','delivery_history','from_date',p_from_date,'to_date',p_to_date,
    'summary', json_build_object(
      'total_deliveries', COUNT(*),
      'total_dc_birds',   COALESCE(SUM(d.pickup_bird_count),0),
      'total_del_birds',  COALESCE(SUM(d.delivered_bird_count),0),
      'total_gross_wt',   COALESCE(SUM(dc.gross_weight),0),
      'total_tare_wt',    COALESCE(SUM(dc.empty_crate_weight),0),
      'total_net_del_wt', COALESCE(SUM(d.delivered_total_weight),0),
      'total_mortality',  COALESCE(SUM(d.mortality_birds),0),
      'total_returned',   COALESCE(SUM(d.returned_birds),0)
    ),
    'rows', (
      SELECT COALESCE(json_agg(row_to_json(r) ORDER BY r.del_date DESC),'[]'::json) FROM (
        SELECT DATE(d2.delivered_at) AS del_date, d2.delivered_at::text AS del_time,
          da.name AS agent_name, rt.shop_name, dc2.dc_number,
          dc2.gross_weight, dc2.empty_crate_weight AS tare_weight, dc2.net_weight,
          d2.pickup_bird_count AS dc_birds, d2.delivered_bird_count AS del_birds,
          d2.delivered_total_weight AS net_del_weight, d2.mortality_birds, d2.returned_birds,
          d2.collected_amount, d2.payment_mode, d2.avg_bird_weight_g,
          o.remarks AS order_remarks
        FROM deliveries d2
        LEFT JOIN delivery_agents da ON da.id=d2.delivery_agent_id
        LEFT JOIN orders o ON o.id=d2.order_id
        LEFT JOIN retailers rt ON rt.id=o.retailer_id
        LEFT JOIN delivery_batches db ON db.id=d2.batch_id
        LEFT JOIN delivery_challans dc2 ON dc2.batch_id=db.id
        WHERE d2.trader_id=p_trader_id AND d2.status='delivered'
          AND DATE(d2.delivered_at) BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR d2.delivery_agent_id=p_agent_id)
          AND (p_retailer_id IS NULL OR o.retailer_id=p_retailer_id)
      ) r)
  ) INTO v
  FROM deliveries d
  LEFT JOIN delivery_batches db ON db.id=d.batch_id
  LEFT JOIN delivery_challans dc ON dc.batch_id=db.id
  WHERE d.trader_id=p_trader_id AND d.status='delivered'
    AND DATE(d.delivered_at) BETWEEN p_from_date AND p_to_date
    AND (p_agent_id IS NULL OR d.delivery_agent_id=p_agent_id);

ELSIF p_report = 'agent_performance' THEN
  SELECT json_build_object(
    'report','agent_performance','from_date',p_from_date,'to_date',p_to_date,
    'agents', (
      SELECT COALESCE(json_agg(row_to_json(a) ORDER BY a.del_weight DESC),'[]'::json) FROM (
        SELECT da.id, da.name AS agent_name, da.vehicle_no,
          COUNT(d.id) AS deliveries,
          COALESCE(SUM(d.delivered_bird_count),0) AS del_birds,
          COALESCE(SUM(d.delivered_total_weight),0)::numeric AS del_weight,
          COALESCE((
            SELECT SUM(sl.quantity_birds) FROM stock_ledger sl
            WHERE sl.agent_id=da.id AND sl.movement_type='mortality'
              AND sl.entry_date BETWEEN p_from_date AND p_to_date
          ), 0) AS mortality,
          COALESCE(SUM(d.collected_amount),0) AS cash_collected,
          COALESCE(SUM(ds.total_expenses),0) AS expenses,
          COALESCE(SUM(ds.distance_km),0) AS km_driven,
          COUNT(ds.id) AS shifts,
          COALESCE((
            SELECT CASE WHEN SUM(bls.dc_total_weight_kg)>0
                        THEN ROUND(SUM(bls.unaccounted_loss_kg)/SUM(bls.dc_total_weight_kg)*100,2)
                        ELSE 0 END
            FROM batch_loss_summary bls
            JOIN delivery_shifts ds2 ON ds2.id=bls.shift_id
            WHERE bls.agent_id=da.id AND DATE(ds2.shift_end_at) BETWEEN p_from_date AND p_to_date
          ), 0) AS loss_pct,
          COALESCE((
            SELECT SUM(bls.unaccounted_loss_kg)
            FROM batch_loss_summary bls
            JOIN delivery_shifts ds2 ON ds2.id=bls.shift_id
            WHERE bls.agent_id=da.id AND DATE(ds2.shift_end_at) BETWEEN p_from_date AND p_to_date
          ), 0) AS shrinkage_kg,
          COALESCE((
            SELECT SUM(bls.operational_loss_kg)
            FROM batch_loss_summary bls
            JOIN delivery_shifts ds2 ON ds2.id=bls.shift_id
            WHERE bls.agent_id=da.id AND DATE(ds2.shift_end_at) BETWEEN p_from_date AND p_to_date
          ), 0) AS operational_loss_kg,
          COALESCE((
            SELECT SUM(bls.unexplained_loss_kg)
            FROM batch_loss_summary bls
            JOIN delivery_shifts ds2 ON ds2.id=bls.shift_id
            WHERE bls.agent_id=da.id AND DATE(ds2.shift_end_at) BETWEEN p_from_date AND p_to_date
          ), 0) AS unexplained_loss_kg
        FROM delivery_agents da
        LEFT JOIN deliveries d ON d.delivery_agent_id=da.id AND d.status='delivered'
          AND DATE(d.delivered_at) BETWEEN p_from_date AND p_to_date AND d.trader_id=p_trader_id
        LEFT JOIN delivery_shifts ds ON ds.delivery_agent_id=da.id AND ds.status='closed'
          AND DATE(ds.shift_end_at) BETWEEN p_from_date AND p_to_date
        WHERE da.trader_id=p_trader_id AND da.is_active=true
          AND (p_agent_id IS NULL OR da.id=p_agent_id)
        GROUP BY da.id, da.name, da.vehicle_no
      ) a),
    'daily', (
      SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.dt DESC),'[]'::json) FROM (
        SELECT dates.dt,
          COALESCE(SUM(d2.delivered_bird_count),0) AS del_birds,
          COALESCE(SUM(d2.delivered_total_weight),0)::numeric AS del_weight,
          COALESCE((
            SELECT SUM(sl.quantity_birds) FROM stock_ledger sl
            WHERE sl.trader_id=p_trader_id AND sl.movement_type='mortality'
              AND sl.entry_date=dates.dt
              AND (p_agent_id IS NULL OR sl.agent_id=p_agent_id)
          ), 0) AS mortality,
          COALESCE((
            SELECT SUM(bls.unaccounted_loss_kg)
            FROM batch_loss_summary bls
            JOIN delivery_shifts ds3 ON ds3.id=bls.shift_id
            WHERE bls.trader_id=p_trader_id AND DATE(ds3.shift_end_at)=dates.dt
              AND (p_agent_id IS NULL OR bls.agent_id=p_agent_id)
          ), 0) AS shrinkage,
          COALESCE(SUM(d2.collected_amount),0) AS collected
        FROM generate_series(p_from_date, p_to_date, '1 day'::interval) AS dates(dt)
        LEFT JOIN deliveries d2 ON DATE(d2.delivered_at)=dates.dt
          AND d2.trader_id=p_trader_id AND d2.status='delivered'
          AND (p_agent_id IS NULL OR d2.delivery_agent_id=p_agent_id)
        GROUP BY dates.dt
      ) d)
  ) INTO v;

ELSIF p_report = 'shift_audit' THEN
  SELECT json_build_object(
    'report','shift_audit','from_date',p_from_date,'to_date',p_to_date,
    'shifts', (
      SELECT COALESCE(json_agg(row_to_json(s) ORDER BY s.shift_date DESC),'[]'::json) FROM (
        SELECT DATE(ds.shift_end_at) AS shift_date, da.name AS agent_name, da.vehicle_no,
          ds.opening_bird_count, ds.pickup_weight AS dc_loaded_kg,
          ds.total_birds_delivered AS delivered_birds, ds.delivered_weight AS delivered_kg,
          ds.returned_weight, ds.total_mortality, ds.total_loss_kg AS shrinkage_kg,
          ds.loss_percent, ds.total_cash_collected, ds.total_expenses,
          ds.diesel_cost, ds.allowance, ds.distance_km,
          ds.odometer_start, ds.odometer_end, ds.crates_taken, ds.crates_returned,
          ds.shift_approval_status, ds.total_orders
        FROM delivery_shifts ds
        JOIN delivery_agents da ON da.id=ds.delivery_agent_id
        WHERE ds.trader_id=p_trader_id AND DATE(ds.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND ds.status='closed' AND (p_agent_id IS NULL OR ds.delivery_agent_id=p_agent_id)
      ) s)
  ) INTO v;

ELSIF p_report = 'expense' THEN
  v_pnl := get_pnl_statement(p_trader_id, p_from_date, p_to_date, 'daily');
  SELECT json_build_object(
    'report','expense','from_date',p_from_date,'to_date',p_to_date,
    'summary', json_build_object(
      'total_expenses', COALESCE((v_pnl->'summary'->>'total_expenses')::numeric, 0),
      'trip_expenses',  COALESCE((v_pnl->'summary'->>'trip_expenses')::numeric, 0),
      'trader_expenses',COALESCE((v_pnl->'summary'->>'trader_expenses')::numeric, 0),
      'fixed_expenses', COALESCE((v_pnl->'summary'->>'fixed_expenses')::numeric, 0),
      'diesel',         COALESCE(SUM(ds.diesel_cost),0),
      'allowance',      COALESCE(SUM(ds.allowance),0),
      'total_km',       COALESCE(SUM(ds.distance_km),0),
      'shift_count',    COUNT(DISTINCT ds.id),
      'per_km',         CASE WHEN COALESCE(SUM(ds.distance_km),0)>0
                          THEN ROUND(SUM(ds.total_expenses)/SUM(ds.distance_km),2) ELSE 0 END,
      'per_bird',       CASE WHEN COALESCE(SUM(ds.total_birds_delivered),0)>0
                          THEN ROUND(SUM(ds.total_expenses)/SUM(ds.total_birds_delivered),4) ELSE 0 END
    ),
    'by_agent', (
      SELECT COALESCE(json_agg(row_to_json(a) ORDER BY a.total_expenses DESC),'[]'::json) FROM (
        SELECT da.name AS agent_name,
          COALESCE(SUM(ds2.total_expenses),0) AS total_expenses,
          COALESCE(SUM(ds2.diesel_cost),0) AS diesel,
          COALESCE(SUM(ds2.allowance),0) AS allowance,
          COALESCE(SUM(ds2.distance_km),0) AS km_driven,
          COUNT(ds2.id) AS shifts
        FROM delivery_agents da
        JOIN delivery_shifts ds2 ON ds2.delivery_agent_id=da.id
          AND DATE(ds2.shift_end_at) BETWEEN p_from_date AND p_to_date AND ds2.status='closed'
        WHERE da.trader_id=p_trader_id AND (p_agent_id IS NULL OR da.id=p_agent_id)
        GROUP BY da.id, da.name
      ) a),
    'daily', (
      SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.dt DESC),'[]'::json) FROM (
        SELECT DATE(ds3.shift_end_at) AS dt, da2.name AS agent_name,
          ds3.diesel_cost, ds3.allowance, ds3.total_expenses, ds3.distance_km
        FROM delivery_shifts ds3
        JOIN delivery_agents da2 ON da2.id=ds3.delivery_agent_id
        WHERE ds3.trader_id=p_trader_id AND DATE(ds3.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND ds3.status='closed' AND (p_agent_id IS NULL OR ds3.delivery_agent_id=p_agent_id)
      ) d),
    'rows', (
      SELECT COALESCE(json_agg(row_to_json(x) ORDER BY x.business_date DESC),'[]'::json) FROM (
        SELECT 'trip'::text AS expense_type,
          NULL::uuid AS id,
          COALESCE(de.expense_type,'Trip Expense') AS category,
          de.notes AS remarks,
          COALESCE(agent_u.name, 'Agent') AS created_by,
          NULL::text AS payment_mode,
          de.amount,
          DATE(ds5.shift_end_at) AS business_date
        FROM delivery_expenses de
        JOIN delivery_shifts ds5 ON ds5.id = de.shift_id
        LEFT JOIN delivery_agents agent_u ON agent_u.id = de.agent_id
        WHERE de.trader_id = p_trader_id
          AND DATE(ds5.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND (p_agent_id IS NULL OR de.agent_id = p_agent_id)

        UNION ALL

        SELECT 'trader'::text,
          tde.id,
          COALESCE(tde.category,'General'),
          COALESCE(tde.label, tde.notes),
          COALESCE((SELECT u.email FROM auth.users u WHERE u.id = tde.created_by), 'Trader'),
          tde.payment_mode,
          tde.amount,
          tde.expense_date
        FROM trader_daily_expenses tde
        WHERE tde.trader_id = p_trader_id
          AND tde.expense_date BETWEEN p_from_date AND p_to_date
          AND tde.deleted_at IS NULL
          AND p_agent_id IS NULL

        UNION ALL

        SELECT 'fixed'::text,
          NULL::uuid,
          COALESCE(re.category,'Recurring'),
          COALESCE(re.label, re.notes),
          'System (Recurring)',
          NULL::text,
          ROUND((CASE re.frequency
            WHEN 'monthly' THEN re.amount / EXTRACT(DAY FROM (date_trunc('month', gs.dt) + interval '1 month - 1 day'))
            WHEN 'weekly'  THEN re.amount / 7.0
            WHEN 'daily'   THEN re.amount
            ELSE 0
          END)::numeric, 2),
          gs.dt
        FROM recurring_expenses re
        CROSS JOIN generate_series(p_from_date, p_to_date, '1 day'::interval) AS gs(dt)
        WHERE re.trader_id = p_trader_id
          AND re.is_active = true
          AND re.effective_from <= gs.dt
          AND (re.effective_to IS NULL OR re.effective_to >= gs.dt)
          AND p_agent_id IS NULL
      ) x),
    'category_breakdown', (
      SELECT COALESCE(json_agg(row_to_json(c) ORDER BY c.total_amount DESC),'[]'::json) FROM (
        SELECT x.expense_type, x.category,
          COUNT(*) AS entry_count,
          SUM(x.amount) AS total_amount
        FROM (
          SELECT 'trip'::text AS expense_type, COALESCE(de.expense_type,'Trip Expense') AS category, de.amount
          FROM delivery_expenses de
          JOIN delivery_shifts ds5 ON ds5.id = de.shift_id
          WHERE de.trader_id = p_trader_id
            AND DATE(ds5.shift_end_at) BETWEEN p_from_date AND p_to_date
            AND (p_agent_id IS NULL OR de.agent_id = p_agent_id)

          UNION ALL

          SELECT 'trader'::text, COALESCE(tde.category,'General'), tde.amount
          FROM trader_daily_expenses tde
          WHERE tde.trader_id = p_trader_id
            AND tde.expense_date BETWEEN p_from_date AND p_to_date
            AND tde.deleted_at IS NULL
            AND p_agent_id IS NULL

          UNION ALL

          SELECT 'fixed'::text, COALESCE(re.category,'Recurring'),
            ROUND((CASE re.frequency
              WHEN 'monthly' THEN re.amount / EXTRACT(DAY FROM (date_trunc('month', gs.dt) + interval '1 month - 1 day'))
              WHEN 'weekly'  THEN re.amount / 7.0
              WHEN 'daily'   THEN re.amount
              ELSE 0
            END)::numeric, 2)
          FROM recurring_expenses re
          CROSS JOIN generate_series(p_from_date, p_to_date, '1 day'::interval) AS gs(dt)
          WHERE re.trader_id = p_trader_id AND re.is_active = true
            AND re.effective_from <= gs.dt AND (re.effective_to IS NULL OR re.effective_to >= gs.dt)
            AND p_agent_id IS NULL
        ) x
        GROUP BY x.expense_type, x.category
      ) c)
  ) INTO v
  FROM delivery_shifts ds
  WHERE ds.trader_id=p_trader_id AND DATE(ds.shift_end_at) BETWEEN p_from_date AND p_to_date
    AND ds.status='closed' AND (p_agent_id IS NULL OR ds.delivery_agent_id=p_agent_id);

ELSIF p_report = 'collection' THEN
  -- ROOT CAUSE FIX (Cash Collection Edit/Remove — reporting visibility
  -- audit): every credit-only ("collected") aggregate below now also
  -- excludes ledger rows whose id appears as original_entry_id in
  -- retailer_payment_audit_log — i.e. a payment that was later
  -- superseded by an edit or fully removed. Debit-credit SIGNED balance
  -- aggregates (total_outstanding, retailers.outstanding) are
  -- deliberately left untouched — they already net reversals correctly
  -- and must keep including them to stay accurate.
  SELECT json_build_object(
    'report','collection','from_date',p_from_date,'to_date',p_to_date,
    'summary', json_build_object(
      'total_billed',      (SELECT COALESCE(SUM(total_amount),0)    FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced') AND (p_retailer_id IS NULL OR retailer_id=p_retailer_id)),
      'total_returns',     (SELECT COALESCE(SUM(cn.total_amount),0)
                            FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                            WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued'
                              AND cn.credit_date BETWEEN p_from_date AND p_to_date
                              AND (p_retailer_id IS NULL OR i2.retailer_id=p_retailer_id)),
      'net_billed',        (SELECT COALESCE(SUM(total_amount),0)    FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced') AND (p_retailer_id IS NULL OR retailer_id=p_retailer_id))
                          - (SELECT COALESCE(SUM(cn.total_amount),0)
                            FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                            WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued'
                              AND cn.credit_date BETWEEN p_from_date AND p_to_date
                              AND (p_retailer_id IS NULL OR i2.retailer_id=p_retailer_id)),
      'total_collected',   (SELECT COALESCE(SUM(amount),0) FROM ledger_entries le WHERE le.trader_id=p_trader_id AND le.entry_type='credit' AND le.entry_date BETWEEN p_from_date AND p_to_date AND (p_retailer_id IS NULL OR le.retailer_id=p_retailer_id)
                              AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le.id)),
      'total_pending',     (SELECT COALESCE(SUM(CASE WHEN balance_amount>0 THEN balance_amount ELSE 0 END),0) FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced') AND (p_retailer_id IS NULL OR retailer_id=p_retailer_id)),
      'total_outstanding', (SELECT COALESCE(SUM(CASE WHEN entry_type='debit' THEN amount ELSE -amount END),0) FROM ledger_entries WHERE trader_id=p_trader_id AND (p_retailer_id IS NULL OR retailer_id=p_retailer_id)),
      'cash',  (SELECT COALESCE(SUM(amount),0) FROM ledger_entries le WHERE le.trader_id=p_trader_id AND le.entry_type='credit' AND le.payment_mode='cash'  AND le.entry_date BETWEEN p_from_date AND p_to_date AND (p_retailer_id IS NULL OR le.retailer_id=p_retailer_id)
                              AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le.id)),
      'upi',   (SELECT COALESCE(SUM(amount),0) FROM ledger_entries le WHERE le.trader_id=p_trader_id AND le.entry_type='credit' AND le.payment_mode='upi'   AND le.entry_date BETWEEN p_from_date AND p_to_date AND (p_retailer_id IS NULL OR le.retailer_id=p_retailer_id)
                              AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le.id)),
      'bank',  (SELECT COALESCE(SUM(amount),0) FROM ledger_entries le WHERE le.trader_id=p_trader_id AND le.entry_type='credit' AND le.payment_mode='bank'  AND le.entry_date BETWEEN p_from_date AND p_to_date AND (p_retailer_id IS NULL OR le.retailer_id=p_retailer_id)
                              AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le.id)),
      'credit',(SELECT COALESCE(SUM(amount),0) FROM ledger_entries le WHERE le.trader_id=p_trader_id AND le.entry_type='credit' AND le.payment_mode='credit' AND le.entry_date BETWEEN p_from_date AND p_to_date AND (p_retailer_id IS NULL OR le.retailer_id=p_retailer_id)
                              AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le.id))
    ),
    'retailers', (SELECT COALESCE(json_agg(row_to_json(r) ORDER BY r.outstanding DESC),'[]'::json) FROM (
        SELECT rt.shop_name, rt.phone,
          COALESCE(SUM(le.amount) FILTER (WHERE le.entry_type='debit' AND le.source_type='invoice'),0) AS billed,
          COALESCE(SUM(le.amount) FILTER (
            WHERE le.entry_type='credit' AND le.entry_date BETWEEN p_from_date AND p_to_date
              AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le.id)
          ),0) AS collected,
          COALESCE(SUM(CASE WHEN le.entry_type='debit' THEN le.amount ELSE -le.amount END),0) AS outstanding,
          MAX(CASE WHEN le.source_type='invoice' THEN le.entry_date END) AS last_invoice,
          -- Collection by party: balance as of the report's To date
          -- (Current Balance; Old Balance = this + collected) and the
          -- payment modes used in the period.
          COALESCE(SUM(CASE WHEN le.entry_type='debit' THEN le.amount ELSE -le.amount END)
                   FILTER (WHERE le.entry_date <= p_to_date),0) AS closing_balance,
          STRING_AGG(DISTINCT le.payment_mode, ',') FILTER (
            WHERE le.entry_type='credit' AND le.entry_date BETWEEN p_from_date AND p_to_date
              AND le.payment_mode IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le.id)
          ) AS modes
        FROM retailers rt
        JOIN ledger_entries le ON le.retailer_id=rt.id AND le.trader_id=p_trader_id
        WHERE rt.trader_id=p_trader_id AND (p_retailer_id IS NULL OR rt.id=p_retailer_id)
        GROUP BY rt.id, rt.shop_name, rt.phone HAVING SUM(le.amount)>0
      ) r),
    'daily', (SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.dt DESC),'[]'::json) FROM (
        SELECT dates.dt,
          COALESCE((SELECT SUM(i3.total_amount) FROM invoices i3 WHERE i3.trader_id=p_trader_id AND i3.invoice_date=dates.dt AND i3.status IN ('approved','invoiced') AND (p_retailer_id IS NULL OR i3.retailer_id=p_retailer_id)),0) AS billed,
          COALESCE((SELECT SUM(le2.amount) FROM ledger_entries le2 WHERE le2.trader_id=p_trader_id AND le2.entry_type='credit' AND le2.entry_date=dates.dt AND (p_retailer_id IS NULL OR le2.retailer_id=p_retailer_id)
                      AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le2.id)),0) AS collected,
          COALESCE((SELECT SUM(le3.amount) FROM ledger_entries le3 WHERE le3.trader_id=p_trader_id AND le3.entry_type='credit' AND le3.payment_mode='cash' AND le3.entry_date=dates.dt AND (p_retailer_id IS NULL OR le3.retailer_id=p_retailer_id)
                      AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le3.id)),0) AS cash,
          COALESCE((SELECT SUM(le4.amount) FROM ledger_entries le4 WHERE le4.trader_id=p_trader_id AND le4.entry_type='credit' AND le4.payment_mode='upi' AND le4.entry_date=dates.dt AND (p_retailer_id IS NULL OR le4.retailer_id=p_retailer_id)
                      AND NOT EXISTS (SELECT 1 FROM retailer_payment_audit_log rpal WHERE rpal.original_entry_id = le4.id)),0) AS upi,
          COALESCE((SELECT SUM(i4.balance_amount) FROM invoices i4 WHERE i4.trader_id=p_trader_id AND i4.invoice_date=dates.dt AND i4.status IN ('approved','invoiced') AND i4.balance_amount>0 AND (p_retailer_id IS NULL OR i4.retailer_id=p_retailer_id)),0) AS pending
        FROM generate_series(p_from_date, p_to_date, '1 day'::interval) AS dates(dt)
      ) d WHERE d.billed>0 OR d.collected>0)
  ) INTO v;

ELSIF p_report = 'retailer_purchase' THEN
  WITH inv_agg AS (
    SELECT
        order_id,
        SUM(total_amount) AS total_amount,
        SUM(collected_amount) AS collected_amount,
        SUM(GREATEST(balance_amount, 0)) AS balance_amount,
        (
            ARRAY_AGG(
                price_per_kg
                ORDER BY invoice_date DESC, created_at DESC
            )
        )[1] AS price_per_kg,
        MAX(invoice_date) AS last_invoice_date
    FROM invoices
    WHERE trader_id = p_trader_id
      AND status IN ('approved', 'invoiced')
    GROUP BY order_id
),
-- Orders not invoiced yet: amount and rate from the customer rate set for
-- the shop (same preview the invoice screen uses), so the report still
-- shows Rate and Amount before the invoice is made.
est AS (
    SELECT
        o5.id AS order_id,
        SUM(pv.line_total) AS amount,
        MAX(pv.rate) AS rate
    FROM orders o5
    CROSS JOIN LATERAL get_order_rate_preview(o5.id, o5.order_date) pv
    WHERE o5.trader_id = p_trader_id
      AND o5.order_date BETWEEN p_from_date AND p_to_date
      AND o5.status NOT IN ('cancelled')
      AND NOT EXISTS (SELECT 1 FROM inv_agg ia WHERE ia.order_id = o5.id)
    GROUP BY o5.id
)
SELECT json_build_object(
    'report', 'retailer_purchase',
    'from_date', p_from_date,
    'to_date', p_to_date,

    -- Summary
    'summary', json_build_object(
        'total_orders',
            COUNT(DISTINCT o.id),

        'total_kg',
            COALESCE(SUM(o.total_quantity), 0),

        'total_birds',
            COALESCE(SUM(o.estimated_birds), 0),

        'total_billed',
            COALESCE(SUM(COALESCE(i.total_amount, e.amount)), 0),

        'total_returns',
            COALESCE((
                SELECT SUM(cn.total_amount)
                FROM credit_notes cn
                JOIN invoices i3
                    ON i3.id = cn.invoice_id
                WHERE i3.trader_id = p_trader_id
                  AND i3.status IN ('approved', 'invoiced')
                  AND cn.status = 'issued'
                  AND cn.credit_date BETWEEN p_from_date AND p_to_date
                  AND i3.order_id IN (
                      SELECT o4.id
                      FROM orders o4
                      WHERE o4.trader_id = p_trader_id
                        AND o4.order_date BETWEEN p_from_date AND p_to_date
                        AND o4.status NOT IN ('cancelled')
                        AND (
                            p_retailer_id IS NULL
                            OR o4.retailer_id = p_retailer_id
                        )
                        AND (
                            p_agent_id IS NULL
                            OR EXISTS (
                                SELECT 1
                                FROM deliveries dl
                                WHERE dl.order_id = o4.id
                                  AND dl.trader_id = p_trader_id
                                  AND dl.delivery_agent_id = p_agent_id
                            )
                        )
                  )
            ), 0),

        'total_collected',
            COALESCE(SUM(i.collected_amount), 0),

        'total_pending',
            COALESCE(SUM(i.balance_amount), 0)
    ),

    -- Retailer-wise report
    'retailers', (
        SELECT COALESCE(
            json_agg(
                row_to_json(r)
                ORDER BY r.total_kg DESC
            ),
            '[]'::json
        )
        FROM (
            SELECT
                rt.shop_name,
                rt.owner_name,
                rt.phone,

                COUNT(DISTINCT o2.id) AS orders,

                COALESCE(SUM(o2.total_quantity), 0) AS total_kg,

                COALESCE(SUM(o2.estimated_birds), 0) AS total_birds,

                STRING_AGG(DISTINCT NULLIF(btrim(o2.manual_doc_no), ''), ', ') AS doc_nos,

                STRING_AGG(DISTINCT to_char(COALESCE(i2.price_per_kg, e2.rate), 'FM999990.00'), ', ') AS rates,

                COALESCE(SUM(COALESCE(i2.total_amount, e2.amount)), 0) AS billed,

                COALESCE(SUM(i2.collected_amount), 0) AS collected,

                COALESCE(SUM(i2.balance_amount), 0) AS outstanding

            FROM retailers rt

            LEFT JOIN orders o2
                ON o2.retailer_id = rt.id
               AND o2.trader_id = p_trader_id
               AND o2.order_date BETWEEN p_from_date AND p_to_date
               AND o2.status NOT IN ('cancelled')
               AND (
                   p_agent_id IS NULL
                   OR EXISTS (
                       SELECT 1
                       FROM deliveries dl
                       WHERE dl.order_id = o2.id
                         AND dl.trader_id = p_trader_id
                         AND dl.delivery_agent_id = p_agent_id
                   )
               )

            LEFT JOIN inv_agg i2
                ON i2.order_id = o2.id

            LEFT JOIN est e2
                ON e2.order_id = o2.id

            WHERE rt.trader_id = p_trader_id
              AND rt.is_active = TRUE
              AND (
                  p_retailer_id IS NULL
                  OR rt.id = p_retailer_id
              )

            GROUP BY
                rt.id,
                rt.shop_name,
                rt.owner_name,
                rt.phone

            HAVING COUNT(o2.id) > 0
        ) r
    ),

    -- Daily order report
    'daily', (
        SELECT COALESCE(
            json_agg(
                row_to_json(d)
                ORDER BY d.order_date DESC
            ),
            '[]'::json
        )
        FROM (
            SELECT
                o3.order_date,
                rt2.shop_name,
                o3.total_quantity AS kg,
                o3.estimated_birds AS birds,

                COALESCE(i4.total_amount, e4.amount, 0) AS billed,

                COALESCE(i4.collected_amount, 0) AS collected,

                COALESCE(i4.price_per_kg, e4.rate, 0) AS rate,

                o3.remarks AS order_remarks

            FROM orders o3

            JOIN retailers rt2
                ON rt2.id = o3.retailer_id

            LEFT JOIN inv_agg i4
                ON i4.order_id = o3.id

            LEFT JOIN est e4
                ON e4.order_id = o3.id

            WHERE o3.trader_id = p_trader_id
              AND o3.order_date BETWEEN p_from_date AND p_to_date
              AND o3.status NOT IN ('cancelled')
              AND (
                  p_retailer_id IS NULL
                  OR o3.retailer_id = p_retailer_id
              )
              AND (
                  p_agent_id IS NULL
                  OR EXISTS (
                      SELECT 1
                      FROM deliveries dl
                      WHERE dl.order_id = o3.id
                        AND dl.trader_id = p_trader_id
                        AND dl.delivery_agent_id = p_agent_id
                  )
              )
        ) d
    )

)
INTO v

FROM orders o

LEFT JOIN inv_agg i
    ON i.order_id = o.id

LEFT JOIN est e
    ON e.order_id = o.id

WHERE o.trader_id = p_trader_id
  AND o.order_date BETWEEN p_from_date AND p_to_date
  AND o.status NOT IN ('cancelled')
  AND (
      p_retailer_id IS NULL
      OR o.retailer_id = p_retailer_id
  )
  AND (
      p_agent_id IS NULL
      OR EXISTS (
          SELECT 1
          FROM deliveries dl
          WHERE dl.order_id = o.id
            AND dl.trader_id = p_trader_id
            AND dl.delivery_agent_id = p_agent_id
      )
  );

ELSIF p_report = 'profitability' THEN
  v_pnl := get_pnl_statement(p_trader_id, p_from_date, p_to_date, 'daily');
  SELECT json_build_object(
    'report','profitability','from_date',p_from_date,'to_date',p_to_date,
    'summary', json_build_object(
      'gross_revenue',  COALESCE((SELECT SUM(total_amount) FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced')),0),
      'returns_amount', COALESCE((SELECT SUM(cn.total_amount) FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                          WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued'
                            AND cn.credit_date BETWEEN p_from_date AND p_to_date),0),
      'revenue',        COALESCE((SELECT SUM(total_amount) FROM invoices WHERE trader_id=p_trader_id AND invoice_date BETWEEN p_from_date AND p_to_date AND status IN ('approved','invoiced')),0)
                       - COALESCE((SELECT SUM(cn.total_amount) FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                          WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued'
                            AND cn.credit_date BETWEEN p_from_date AND p_to_date),0),
      'purchase_cost',  COALESCE((SELECT SUM(COALESCE(total_landed_cost, base_purchase_amount, 0)) FROM purchase_entries WHERE trader_id=p_trader_id AND purchase_rate_per_kg IS NOT NULL AND dc_date BETWEEN p_from_date AND p_to_date),0),
      'expenses',       COALESCE((v_pnl->'summary'->>'total_expenses')::numeric, 0),
      'trip_expenses',  COALESCE((v_pnl->'summary'->>'trip_expenses')::numeric, 0),
      'trader_expenses',COALESCE((v_pnl->'summary'->>'trader_expenses')::numeric, 0),
      'fixed_expenses', COALESCE((v_pnl->'summary'->>'fixed_expenses')::numeric, 0),
      'shrinkage_loss', COALESCE((
        SELECT SUM(COALESCE(bc.operational_loss_amount,0) + COALESCE(bc.unexplained_loss_amount,0))
        FROM batch_costing bc
        JOIN delivery_batches db ON db.id=bc.batch_id
        JOIN delivery_shifts ds ON ds.id=db.shift_id
        WHERE bc.trader_id=p_trader_id
          AND DATE(ds.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND bc.cost_per_kg IS NOT NULL AND bc.cost_per_kg > 0
          AND (p_agent_id IS NULL OR ds.delivery_agent_id=p_agent_id)
      ), 0),
      'mortality_loss', COALESCE((
        SELECT SUM(bc.mortality_loss_amount)
        FROM batch_costing bc
        JOIN delivery_batches db ON db.id=bc.batch_id
        JOIN delivery_shifts ds ON ds.id=db.shift_id
        WHERE bc.trader_id=p_trader_id
          AND DATE(ds.shift_end_at) BETWEEN p_from_date AND p_to_date
          AND bc.cost_per_kg IS NOT NULL AND bc.cost_per_kg > 0
          AND (p_agent_id IS NULL OR ds.delivery_agent_id=p_agent_id)
      ), 0)
    ),
    'daily', (
      SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.dt DESC),'[]'::json) FROM (
        SELECT dates.dt,
          COALESCE((SELECT SUM(i.total_amount) FROM invoices i WHERE i.trader_id=p_trader_id AND i.invoice_date=dates.dt AND i.status IN ('approved','invoiced')),0)
            - COALESCE((SELECT SUM(cn.total_amount) FROM credit_notes cn JOIN invoices i2 ON i2.id=cn.invoice_id
                WHERE i2.trader_id=p_trader_id AND i2.status IN ('approved','invoiced') AND cn.status='issued' AND cn.credit_date=dates.dt),0) AS revenue,
          COALESCE((SELECT SUM(COALESCE(pe.total_landed_cost, pe.base_purchase_amount, 0)) FROM purchase_entries pe WHERE pe.trader_id=p_trader_id AND pe.purchase_rate_per_kg IS NOT NULL AND pe.dc_date=dates.dt),0) AS purchase_cost,
          COALESCE((
            SELECT (b->>'total_expenses')::numeric
            FROM jsonb_array_elements(v_pnl->'buckets') b
            WHERE (b->>'period_start')::date = dates.dt
          ), 0) AS expenses,
          COALESCE((
            SELECT SUM(COALESCE(bc2.operational_loss_amount,0)+COALESCE(bc2.unexplained_loss_amount,0))
            FROM batch_costing bc2
            JOIN delivery_batches db2 ON db2.id=bc2.batch_id
            JOIN delivery_shifts ds2 ON ds2.id=db2.shift_id
            WHERE bc2.trader_id=p_trader_id AND DATE(ds2.shift_end_at)=dates.dt
              AND bc2.cost_per_kg IS NOT NULL AND bc2.cost_per_kg>0
          ),0) AS shrinkage_loss,
          COALESCE((
            SELECT SUM(bc3.mortality_loss_amount)
            FROM batch_costing bc3
            JOIN delivery_batches db3 ON db3.id=bc3.batch_id
            JOIN delivery_shifts ds3 ON ds3.id=db3.shift_id
            WHERE bc3.trader_id=p_trader_id AND DATE(ds3.shift_end_at)=dates.dt
              AND bc3.cost_per_kg IS NOT NULL AND bc3.cost_per_kg>0
          ),0) AS mortality_loss
        FROM generate_series(p_from_date, p_to_date, '1 day'::interval) AS dates(dt)
      ) d)
  ) INTO v;

ELSE
  SELECT json_build_object('report',p_report,'error','Unknown report type') INTO v;
END IF;

RETURN v;
END;$function$
;
