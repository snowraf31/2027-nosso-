-- =====================================================================
-- Tabletop · 0004 · Restrict the is_staff helper
-- Anonymous visitors never need it. Signed-in staff keep EXECUTE
-- because the row level security policies call it on their behalf.
-- =====================================================================
revoke execute on function public.is_staff(uuid, text[]) from public, anon;
grant execute on function public.is_staff(uuid, text[]) to authenticated;
