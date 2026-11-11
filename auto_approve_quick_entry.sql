-- Settings → "Auto-approve Quick Entry": when on, a Quick Entry the trader
-- saves is approved straight away (invoice created). Off by default, so
-- existing traders keep today's behaviour (entries wait in Approvals).
-- Entries made by agents always wait for the trader's approval.
ALTER TABLE public.traders
  ADD COLUMN IF NOT EXISTS auto_approve_quick_entry boolean NOT NULL DEFAULT false;
