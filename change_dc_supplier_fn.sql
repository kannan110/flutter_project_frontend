-- Purchase Management → Change Supplier: move one DC's purchase to another
-- supplier (farm). Same steps as change_dc_supplier.sql, as one function the
-- app calls, so it can't half-apply:
--   * purchase_entries   farm_id, farmer_name, payment_due_date (new
--                        supplier's credit days, when set)
--   * delivery_challans  farmer_name
--   * stock_ledger       "… DC: <no> — <supplier>" note text
--   * supplier_ledger    rows already posted for this purchase (purchase debit,
--                        payments) move to the new supplier/company
--   * purchase_audit_log one 'supplier_changed' row (old → new)
-- Retailer deliveries, birds, weights, stock quantities and amounts are not
-- touched. Locked purchases can't be changed. Runs as the caller (RLS applies).
CREATE OR REPLACE FUNCTION public.change_dc_supplier(p_purchase_entry_id uuid, p_new_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pe  purchase_entries%ROWTYPE;
  v_old farms%ROWTYPE;
  v_new farms%ROWTYPE;
  v_sl  int := 0;
BEGIN
  SELECT * INTO v_pe FROM purchase_entries WHERE id = p_purchase_entry_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase entry not found.';
  END IF;
  IF v_pe.status = 'locked' THEN
    RAISE EXCEPTION 'This purchase is locked. Reopen it before changing the supplier.';
  END IF;

  SELECT * INTO v_new FROM farms WHERE id = p_new_farm_id AND trader_id = v_pe.trader_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supplier not found for this trader.';
  END IF;
  IF v_pe.farm_id IS NOT DISTINCT FROM p_new_farm_id THEN
    RETURN jsonb_build_object('changed', false, 'supplier', v_new.farmer_name);
  END IF;
  SELECT * INTO v_old FROM farms WHERE id = v_pe.farm_id;  -- may be none

  UPDATE purchase_entries
     SET farm_id          = p_new_farm_id,
         farmer_name      = v_new.farmer_name,
         payment_due_date = CASE WHEN v_new.credit_days IS NOT NULL AND v_pe.dc_date IS NOT NULL
                                 THEN v_pe.dc_date + v_new.credit_days
                                 ELSE payment_due_date END
   WHERE id = p_purchase_entry_id;

  IF v_pe.challan_id IS NOT NULL THEN
    UPDATE delivery_challans SET farmer_name = v_new.farmer_name WHERE id = v_pe.challan_id;
  END IF;

  IF v_old.id IS NOT NULL AND v_pe.batch_id IS NOT NULL THEN
    UPDATE stock_ledger
       SET notes = replace(notes, ' — ' || v_old.farmer_name, ' — ' || v_new.farmer_name)
     WHERE trader_id = v_pe.trader_id AND reference_id = v_pe.batch_id
       AND notes LIKE '%DC: ' || v_pe.dc_number || ' — ' || v_old.farmer_name;
  END IF;

  UPDATE supplier_ledger
     SET farm_id = p_new_farm_id, company_id = v_new.company_id
   WHERE purchase_entry_id = p_purchase_entry_id
     AND farm_id IS DISTINCT FROM p_new_farm_id;
  GET DIAGNOSTICS v_sl = ROW_COUNT;

  INSERT INTO purchase_audit_log(trader_id, purchase_entry_id, action, old_value, new_value, changed_by, notes)
  VALUES (v_pe.trader_id, p_purchase_entry_id, 'supplier_changed',
          jsonb_build_object('farm_id', v_pe.farm_id, 'farmer_name', v_old.farmer_name),
          jsonb_build_object('farm_id', p_new_farm_id, 'farmer_name', v_new.farmer_name),
          auth.uid(),
          'DC ' || coalesce(v_pe.dc_number, '?') || ': supplier changed');

  RETURN jsonb_build_object(
    'changed', true,
    'old_supplier', v_old.farmer_name,
    'supplier', v_new.farmer_name,
    'supplier_ledger_rows_moved', v_sl);
END;
$function$;
