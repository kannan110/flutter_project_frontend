-- Settings → "Auto-approve shift close": when on, a shift the trader closes
-- (on behalf of an agent) is approved straight away (approve_shift). Off by
-- default, so existing traders keep today's behaviour (closed shifts wait in
-- Shifts for approval). Shifts closed by agents always wait.
ALTER TABLE public.traders
  ADD COLUMN IF NOT EXISTS auto_approve_shift_close boolean NOT NULL DEFAULT false;
