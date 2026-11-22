-- =====================================================================
-- Tabletop · 0002 · Row Level Security
-- Guests never touch the database directly: their requests go through
-- the Next.js API, which uses the service role on the server.
-- Staff (logged in) only see rows of restaurants they belong to.
-- =====================================================================

-- Helper: is the current user staff of this restaurant (optionally with these roles)?
create or replace function public.is_staff(p_restaurant uuid, p_roles text[] default null)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from staff
     where user_id = auth.uid()
       and restaurant_id = p_restaurant
       and (p_roles is null or role = any(p_roles))
  );
$$;

alter table public.restaurants          enable row level security;
alter table public.staff                enable row level security;
alter table public.tables               enable row level security;
alter table public.menu_categories      enable row level security;
alter table public.menu_items           enable row level security;
alter table public.modifier_groups      enable row level security;
alter table public.modifier_options     enable row level security;
alter table public.item_modifier_groups enable row level security;
alter table public.orders               enable row level security;
alter table public.order_items          enable row level security;

-- Column privileges: anonymous visitors get nothing; logged-in staff can read,
-- and can only change the few columns the kitchen screen needs.
revoke all on all tables in schema public from anon;
revoke insert, update, delete on all tables in schema public from authenticated;
grant update (status)    on public.orders           to authenticated;
grant update (available) on public.menu_items       to authenticated;
grant update (available) on public.modifier_options to authenticated;

-- Read policies
create policy staff_read_own on public.staff
  for select using (user_id = auth.uid());

create policy staff_read_restaurant on public.restaurants
  for select using (public.is_staff(id));

create policy staff_read_tables on public.tables
  for select using (public.is_staff(restaurant_id));

create policy staff_read_categories on public.menu_categories
  for select using (public.is_staff(restaurant_id));

create policy staff_read_items on public.menu_items
  for select using (public.is_staff(restaurant_id));

create policy staff_read_groups on public.modifier_groups
  for select using (public.is_staff(restaurant_id));

create policy staff_read_options on public.modifier_options
  for select using (exists (
    select 1 from public.modifier_groups g
     where g.id = group_id and public.is_staff(g.restaurant_id)));

create policy staff_read_item_groups on public.item_modifier_groups
  for select using (exists (
    select 1 from public.menu_items i
     where i.id = item_id and public.is_staff(i.restaurant_id)));

create policy staff_read_orders on public.orders
  for select using (public.is_staff(restaurant_id));

create policy staff_read_order_items on public.order_items
  for select using (exists (
    select 1 from public.orders o
     where o.id = order_id and public.is_staff(o.restaurant_id)));

-- Write policies (columns already limited by the grants above)
create policy staff_update_orders on public.orders
  for update using (public.is_staff(restaurant_id))
  with check (public.is_staff(restaurant_id));

create policy staff_update_items on public.menu_items
  for update using (public.is_staff(restaurant_id))
  with check (public.is_staff(restaurant_id));

create policy staff_update_options on public.modifier_options
  for update using (exists (
    select 1 from public.modifier_groups g
     where g.id = group_id and public.is_staff(g.restaurant_id)));
