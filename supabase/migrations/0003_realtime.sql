-- =====================================================================
-- Tabletop · 0003 · Realtime
-- The kitchen screen listens to these tables. Realtime respects RLS,
-- so each kitchen only receives its own restaurant's changes.
-- =====================================================================
alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.menu_items;
