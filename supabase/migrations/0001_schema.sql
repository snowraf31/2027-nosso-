-- =====================================================================
-- Tabletop · 0001 · Schema
-- Multi-tenant: every row belongs to a restaurant (restaurant_id).
-- Money is always stored in integer cents.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Restaurants and staff
-- ---------------------------------------------------------------------
create table public.restaurants (
  id                uuid primary key default gen_random_uuid(),
  slug              text unique not null check (slug ~ '^[a-z0-9-]{2,60}$'),
  name              text not null,
  timezone          text not null default 'America/New_York',
  tax_rate          numeric(6,5) not null default 0.07 check (tax_rate >= 0 and tax_rate < 0.25),
  stripe_account_id text,
  order_seq         int not null default 1000,      -- last order number used
  created_at        timestamptz not null default now()
);

create table public.staff (
  user_id       uuid not null references auth.users on delete cascade,
  restaurant_id uuid not null references public.restaurants on delete cascade,
  role          text not null check (role in ('owner','manager','kitchen')),
  created_at    timestamptz not null default now(),
  primary key (user_id, restaurant_id)
);

-- ---------------------------------------------------------------------
-- Tables: each wooden plaque has its own unguessable token
-- ---------------------------------------------------------------------
create table public.tables (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants on delete cascade,
  label         text not null,                       -- "7", "Bar 2", "Patio 1"
  qr_token      text unique not null default encode(gen_random_bytes(12), 'hex'),
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  unique (restaurant_id, label)
);

-- ---------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------
create table public.menu_categories (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants on delete cascade,
  name          text not null,
  position      int not null default 0
);

create table public.menu_items (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants on delete cascade,
  category_id   uuid references public.menu_categories on delete set null,
  name          text not null,
  description   text,
  price_cents   int not null check (price_cents >= 0),
  photo_url     text,
  dietary_tags  text[] not null default '{}',   -- {'vegan','gf','nf'}
  allergens     text[] not null default '{}',   -- {'tree_nuts','dairy','gluten'}
  available     boolean not null default true,  -- the kitchen's "sold out" switch
  position      int not null default 0,
  created_at    timestamptz not null default now()
);

create table public.modifier_groups (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants on delete cascade,
  name          text not null,                  -- "Milk", "Extras"
  min_select    int not null default 0 check (min_select >= 0),
  max_select    int not null default 1 check (max_select >= 1),
  check (min_select <= max_select)
);

create table public.modifier_options (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.modifier_groups on delete cascade,
  name        text not null,
  price_cents int not null default 0 check (price_cents >= 0),
  available   boolean not null default true,
  position    int not null default 0
);

create table public.item_modifier_groups (
  item_id  uuid not null references public.menu_items on delete cascade,
  group_id uuid not null references public.modifier_groups on delete cascade,
  position int not null default 0,
  primary key (item_id, group_id)
);

-- ---------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------
create table public.orders (
  id                       uuid primary key default gen_random_uuid(),
  restaurant_id            uuid not null references public.restaurants,
  table_id                 uuid references public.tables on delete set null,
  number                   int not null,
  status                   text not null default 'new'
                           check (status in ('new','preparing','ready','served','cancelled')),
  payment_method           text not null check (payment_method in ('online','counter')),
  payment_status           text not null default 'unpaid'
                           check (payment_status in ('unpaid','paid','refunded')),
  subtotal_cents           int not null default 0,
  tax_cents                int not null default 0,
  tip_cents                int not null default 0,
  total_cents              int not null default 0,
  stripe_payment_intent_id text,
  idempotency_key          text unique,           -- stops duplicate orders on double tap
  public_token             text not null default encode(gen_random_bytes(16), 'hex'),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  unique (restaurant_id, number)
);

create index orders_board_idx on public.orders (restaurant_id, status, created_at);

-- Items keep the name and price at the moment of purchase (snapshot)
create table public.order_items (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.orders on delete cascade,
  menu_item_id     uuid references public.menu_items on delete set null,
  name_snapshot    text not null,
  unit_price_cents int not null,
  quantity         int not null check (quantity between 1 and 20),
  modifiers        jsonb not null default '[]',   -- [{"name":"Oat milk","price_cents":75}]
  note             text
);

create index order_items_order_idx on public.order_items (order_id);

-- ---------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger orders_touch before update on public.orders
for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- place_order: the ONLY way an order is created.
-- The phone sends ids and quantities; prices come from the database.
-- Runs in one transaction, so the kitchen never sees a half-written order.
-- ---------------------------------------------------------------------
create or replace function public.place_order(
  p_table_token     text,
  p_items           jsonb,           -- [{"menu_item_id":uuid,"quantity":int,"option_ids":[uuid],"note":text}]
  p_payment_method  text default 'counter',
  p_tip_cents       int  default 0,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_existing  orders%rowtype;
  v_table     tables%rowtype;
  v_rest      restaurants%rowtype;
  v_order_id  uuid;
  v_number    int;
  v_line      jsonb;
  v_item      menu_items%rowtype;
  v_qty       int;
  v_unit      int;
  v_mods      jsonb;
  v_opt_ids   uuid[];
  v_group     record;
  v_opt       record;
  v_count     int;
  v_note      text;
  v_subtotal  int := 0;
  v_tax       int;
  v_tip       int := coalesce(p_tip_cents, 0);
  v_public    text;
begin
  -- Same key twice (double tap, retry on bad Wi-Fi): return the first order
  if p_idempotency_key is not null then
    select * into v_existing from orders where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('id', v_existing.id, 'number', v_existing.number,
                                'public_token', v_existing.public_token);
    end if;
  end if;

  select * into v_table from tables where qr_token = p_table_token and active;
  if not found then raise exception 'TABLE_NOT_FOUND'; end if;

  select * into v_rest from restaurants where id = v_table.restaurant_id;

  if p_payment_method not in ('online','counter') then raise exception 'BAD_PAYMENT'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'EMPTY_ORDER';
  end if;
  if jsonb_array_length(p_items) > 40 then raise exception 'TOO_MANY_ITEMS'; end if;

  -- Per-restaurant sequential number; the row lock serialises concurrent orders
  update restaurants set order_seq = order_seq + 1
   where id = v_rest.id
   returning order_seq into v_number;

  insert into orders (restaurant_id, table_id, number, payment_method, idempotency_key)
  values (v_rest.id, v_table.id, v_number, p_payment_method, p_idempotency_key)
  returning id, public_token into v_order_id, v_public;

  for v_line in select value from jsonb_array_elements(p_items) loop
    v_qty := coalesce((v_line->>'quantity')::int, 0);
    if v_qty < 1 or v_qty > 20 then raise exception 'BAD_QUANTITY'; end if;

    select * into v_item from menu_items
     where id = (v_line->>'menu_item_id')::uuid and restaurant_id = v_rest.id;
    if not found then raise exception 'ITEM_NOT_FOUND'; end if;
    if not v_item.available then raise exception 'ITEM_SOLD_OUT:%', v_item.name; end if;

    v_opt_ids := coalesce(array(
      select distinct jsonb_array_elements_text(coalesce(v_line->'option_ids', '[]'::jsonb))::uuid
    ), '{}');

    -- Every option must belong to a group attached to this item, and be available
    if exists (
      select 1 from unnest(v_opt_ids) as chosen(oid)
       where not exists (
         select 1 from modifier_options mo
           join item_modifier_groups img on img.group_id = mo.group_id
          where mo.id = chosen.oid and img.item_id = v_item.id and mo.available)
    ) then
      raise exception 'BAD_MODIFIER';
    end if;

    -- Respect min/max per group ("choose 1 milk")
    for v_group in
      select mg.* from modifier_groups mg
        join item_modifier_groups img on img.group_id = mg.id
       where img.item_id = v_item.id
    loop
      select count(*) into v_count from modifier_options
       where group_id = v_group.id and id = any(v_opt_ids);
      if v_count < v_group.min_select or v_count > v_group.max_select then
        raise exception 'MODIFIER_RULE:%', v_group.name;
      end if;
    end loop;

    v_unit := v_item.price_cents;
    v_mods := '[]'::jsonb;
    for v_opt in
      select mo.name, mo.price_cents from modifier_options mo
        join item_modifier_groups img on img.group_id = mo.group_id and img.item_id = v_item.id
       where mo.id = any(v_opt_ids)
       order by img.position, mo.position
    loop
      v_unit := v_unit + v_opt.price_cents;
      v_mods := v_mods || jsonb_build_object('name', v_opt.name, 'price_cents', v_opt.price_cents);
    end loop;

    v_note := nullif(left(btrim(coalesce(v_line->>'note', '')), 200), '');

    insert into order_items (order_id, menu_item_id, name_snapshot, unit_price_cents, quantity, modifiers, note)
    values (v_order_id, v_item.id, v_item.name, v_unit, v_qty, v_mods, v_note);

    v_subtotal := v_subtotal + v_unit * v_qty;
  end loop;

  v_tax := round(v_subtotal * v_rest.tax_rate);
  if p_payment_method = 'counter' then v_tip := 0; end if;   -- tips at the counter are handled there
  if v_tip < 0 or v_tip > v_subtotal then raise exception 'BAD_TIP'; end if;

  update orders
     set subtotal_cents = v_subtotal,
         tax_cents      = v_tax,
         tip_cents      = v_tip,
         total_cents    = v_subtotal + v_tax + v_tip
   where id = v_order_id;

  return jsonb_build_object('id', v_order_id, 'number', v_number, 'public_token', v_public);
end $$;

-- Only the server (service role) may call it; the phone goes through /api/orders
revoke all on function public.place_order(text, jsonb, text, int, text) from public, anon, authenticated;
grant execute on function public.place_order(text, jsonb, text, int, text) to service_role;
