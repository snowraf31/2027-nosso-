-- =====================================================================
-- Tabletop · 0005 · Guest functions (no service_role key needed)
-- Guests call three SECURITY DEFINER functions that each require the
-- secret table token (or order token). They still cannot read or write
-- any table directly: the grants in 0002 keep anon out of every table.
-- =====================================================================

create or replace function public.get_guest_menu(p_slug text, p_token text)
returns jsonb
language sql stable security definer set search_path = public as $$
  with t as (
    select tb.label, r.id as rid, r.slug, r.name, r.tax_rate
      from tables tb join restaurants r on r.id = tb.restaurant_id
     where tb.qr_token = p_token and tb.active and r.slug = p_slug
  )
  select case when not exists (select 1 from t) then null else jsonb_build_object(
    'restaurant', (select jsonb_build_object('name', name, 'slug', slug, 'tax_rate', tax_rate) from t),
    'table',      (select jsonb_build_object('label', label) from t),
    'token',      p_token,
    'categories', coalesce((
        select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'position', c.position) order by c.position)
          from menu_categories c where c.restaurant_id = (select rid from t)), '[]'::jsonb),
    'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', i.id, 'category_id', i.category_id, 'name', i.name, 'description', i.description,
                 'price_cents', i.price_cents, 'photo_url', i.photo_url,
                 'dietary_tags', to_jsonb(i.dietary_tags), 'allergens', to_jsonb(i.allergens),
                 'available', i.available, 'position', i.position,
                 'groups', coalesce((
                    select jsonb_agg(jsonb_build_object(
                             'id', g.id, 'name', g.name, 'min_select', g.min_select, 'max_select', g.max_select,
                             'options', coalesce((
                                select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'price_cents', o.price_cents,
                                                                    'available', o.available, 'position', o.position) order by o.position)
                                  from modifier_options o where o.group_id = g.id), '[]'::jsonb)
                           ) order by img.position)
                      from item_modifier_groups img join modifier_groups g on g.id = img.group_id
                     where img.item_id = i.id), '[]'::jsonb)
               ) order by i.position)
          from menu_items i where i.restaurant_id = (select rid from t)), '[]'::jsonb)
  ) end;
$$;

create or replace function public.get_guest_order(p_order_id uuid, p_token text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'id', o.id, 'number', o.number, 'status', o.status, 'payment_method', o.payment_method,
           'subtotal_cents', o.subtotal_cents, 'tax_cents', o.tax_cents, 'tip_cents', o.tip_cents,
           'total_cents', o.total_cents, 'created_at', o.created_at,
           'table_label', tb.label, 'restaurant_name', r.name,
           'items', coalesce((
              select jsonb_agg(jsonb_build_object('id', oi.id, 'name_snapshot', oi.name_snapshot,
                                                  'unit_price_cents', oi.unit_price_cents, 'quantity', oi.quantity,
                                                  'modifiers', oi.modifiers, 'note', oi.note))
                from order_items oi where oi.order_id = o.id), '[]'::jsonb))
    from orders o
    join restaurants r on r.id = o.restaurant_id
    left join tables tb on tb.id = o.table_id
   where o.id = p_order_id and o.public_token = p_token;
$$;

revoke all on function public.get_guest_menu(text, text) from public;
revoke all on function public.get_guest_order(uuid, text) from public;
grant execute on function public.get_guest_menu(text, text)                to anon, authenticated, service_role;
grant execute on function public.get_guest_order(uuid, text)               to anon, authenticated, service_role;
grant execute on function public.place_order(text, jsonb, text, int, text) to anon, authenticated;
