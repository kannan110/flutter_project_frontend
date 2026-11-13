-- DC upload: refuse a DC number that is already on the same batch.
--
-- Two DCs with the same number on one batch can't be told apart by Delete DC
-- (it finds a DC's stock by its number), so deleting one reversed the stock
-- of both. This trigger blocks the duplicate when it is created — on every
-- path: pickup_batch (first DC), add_batch_dc (more DCs), create_dc_for_batch,
-- and an agent changing the number with edit_dc_open_shift.
--
-- Numbers are compared ignoring case and surrounding spaces ("dc12 " = "DC12").
-- Existing duplicates are left as they are (a unique index would fail on
-- them); saving other changes to those old DCs still works.

CREATE OR REPLACE FUNCTION public.fn_guard_dc_number_unique_in_batch()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.batch_id IS NULL OR NEW.dc_number IS NULL OR btrim(NEW.dc_number) = '' THEN
    RETURN NEW;
  END IF;
  -- An update that keeps the same number and batch is fine (old duplicates).
  IF TG_OP = 'UPDATE'
     AND upper(btrim(NEW.dc_number)) = upper(btrim(COALESCE(OLD.dc_number, '')))
     AND NEW.batch_id IS NOT DISTINCT FROM OLD.batch_id THEN
    RETURN NEW;
  END IF;

  -- Serialise DC saves per batch so two at once can't both pass the check.
  PERFORM pg_advisory_xact_lock(hashtext('dc_number:' || NEW.batch_id::text));

  IF EXISTS (
    SELECT 1 FROM delivery_challans
    WHERE batch_id = NEW.batch_id
      AND id IS DISTINCT FROM NEW.id
      AND upper(btrim(dc_number)) = upper(btrim(NEW.dc_number))
  ) THEN
    RAISE EXCEPTION 'DC number % is already added to this batch. Check the DC number and enter a different one.',
      btrim(NEW.dc_number)
      USING ERRCODE = 'unique_violation';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dc_number_unique_in_batch ON public.delivery_challans;
CREATE TRIGGER trg_dc_number_unique_in_batch
  BEFORE INSERT OR UPDATE OF dc_number, batch_id ON public.delivery_challans
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_dc_number_unique_in_batch();
