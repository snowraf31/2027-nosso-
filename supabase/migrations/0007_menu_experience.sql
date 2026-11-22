-- =====================================================================
-- Tabletop · 0007 · Menu experience
-- Optional fields that give the guest menu its personality. All are
-- editable per restaurant; the menu works fine when they are empty.
-- =====================================================================

alter table public.restaurants
  add column if not exists tagline text check (char_length(tagline) <= 90);

alter table public.menu_categories
  add column if not exists note text check (char_length(note) <= 40),   -- "Pulled to order"
  add column if not exists icon text check (icon in ('cup','egg','sandwich','pastry','leaf','bowl','fork','glass'));

alter table public.menu_items
  add column if not exists badge      text   check (char_length(badge) <= 24),   -- "House favorite"
  add column if not exists story      text   check (char_length(story) <= 160),  -- a line from the counter
  add column if not exists moods      text[] not null default '{}',              -- {'coffee','light','hearty','sweet'}
  add column if not exists pairs_with uuid[] not null default '{}';              -- "goes well with"

-- The guest menu now returns the new fields
create or replace function public.get_guest_menu(p_slug text, p_token text)
returns jsonb
language sql stable security definer set search_path = public as $$
  with t as (
    select tb.label, r.id as rid, r.slug, r.name, r.tax_rate, r.tagline
      from tables tb join restaurants r on r.id = tb.restaurant_id
     where tb.qr_token = p_token and tb.active and r.slug = p_slug
  )
  select case when not exists (select 1 from t) then null else jsonb_build_object(
    'restaurant', (select jsonb_build_object('name', name, 'slug', slug, 'tax_rate', tax_rate, 'tagline', tagline) from t),
    'table',      (select jsonb_build_object('label', label) from t),
    'token',      p_token,
    'categories', coalesce((
        select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'position', c.position,
                                            'note', c.note, 'icon', c.icon) order by c.position)
          from menu_categories c where c.restaurant_id = (select rid from t)), '[]'::jsonb),
    'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', i.id, 'category_id', i.category_id, 'name', i.name, 'description', i.description,
                 'price_cents', i.price_cents, 'photo_url', i.photo_url,
                 'dietary_tags', to_jsonb(i.dietary_tags), 'allergens', to_jsonb(i.allergens),
                 'available', i.available, 'position', i.position,
                 'badge', i.badge, 'story', i.story,
                 'moods', to_jsonb(i.moods), 'pairs_with', to_jsonb(i.pairs_with),
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

revoke all on function public.get_guest_menu(text, text) from public;
grant execute on function public.get_guest_menu(text, text) to anon, authenticated, service_role;
