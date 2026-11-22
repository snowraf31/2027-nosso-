-- =====================================================================
-- Tabletop · 0006 · First user becomes the owner
-- The very first user created in the project becomes the owner of the
-- restaurant (only when exactly one restaurant exists). Every later user
-- must be added to staff explicitly, so strangers who sign up get no access.
-- =====================================================================
create or replace function public.bootstrap_first_owner()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_rest uuid;
begin
  if exists (select 1 from staff) then
    return new;
  end if;
  if (select count(*) from restaurants) <> 1 then
    return new;
  end if;
  select id into v_rest from restaurants limit 1;
  insert into staff (user_id, restaurant_id, role) values (new.id, v_rest, 'owner')
  on conflict do nothing;
  return new;
end $$;

revoke all on function public.bootstrap_first_owner() from public, anon, authenticated;

create trigger on_auth_user_created_bootstrap
after insert on auth.users
for each row execute function public.bootstrap_first_owner();
