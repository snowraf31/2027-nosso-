-- =====================================================================
-- Tabletop · 0010 · Endurecer privilégios e funções security definer
-- Fecha as lacunas que os testes de isolamento (supabase/tests) só avisavam:
--   1. authenticated ainda tinha TRUNCATE, REFERENCES e TRIGGER (e, no Postgres 17,
--      MAINTAIN) nas tabelas, e o padrão das tabelas futuras seguia aberto;
--   2. as 5 funções security definer não blindavam o search_path com pg_temp;
--   3. place_order procurava a idempotency_key no banco inteiro.
-- Mais: ninguém de fora cria objeto em schema do search_path das funções definer.
-- Só acréscimos: nenhuma migration anterior foi editada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Privilégios que ignoram a RLS: TRUNCATE, REFERENCES, TRIGGER (e MAINTAIN no PG 17)
-- A 0002 só revogou INSERT, UPDATE e DELETE de authenticated, mas o privilégio
-- padrão do Supabase dá "all" nas tabelas. TRUNCATE ignora a RLS: quem conecta
-- direto no SQL esvaziaria a tabela de TODOS os restaurantes. TRIGGER roda código
-- em cima das escritas de qualquer restaurante; REFERENCES deixa criar chave
-- estrangeira para as nossas tabelas. A API (PostgREST) nunca usa os três.
-- anon já perdeu tudo na 0002; revogamos de novo por garantia.
-- ---------------------------------------------------------------------
revoke truncate, references, trigger on all tables in schema public from authenticated, anon;

-- Postgres 17: o "all" passou a incluir MAINTAIN, que deixa rodar LOCK TABLE em qualquer modo
-- (um "access exclusive" em orders trava os pedidos de TODOS os restaurantes), VACUUM FULL,
-- CLUSTER e REINDEX, também sem passar pela RLS. No Postgres 16 a palavra maintain nem existe
-- (erro de sintaxe), por isso o comando vai em SQL dinâmico e só roda a partir da versão 17.
do $$
begin
  if current_setting('server_version_num')::int >= 170000 then
    execute 'revoke maintain on all tables in schema public from authenticated, anon';
    execute 'alter default privileges in schema public revoke maintain on tables from authenticated, anon';
  end if;
end $$;

-- Objetos FUTUROS (padrão do papel que roda as migrations, no Supabase o postgres): sem isto, cada
-- tabela nova nasceria com "all" para anon e authenticated.
--   tabelas:    anon não recebe nada; authenticated só mantém o SELECT (a RLS filtra por restaurante).
--               Escrita de staff é só pelas colunas da cozinha (grant por coluna, como na 0002) ou pela API.
--   sequências: nenhum dos dois (setval/nextval pelo visitante bagunçaria numeração compartilhada).
-- Funções ficam de fora de propósito: o PUBLIC já recebe EXECUTE por padrão em toda função nova, então
-- revogar só de anon/authenticated não mudaria nada, e revogar do PUBLIC no padrão global também
-- tiraria o EXECUTE das funções que as extensões instalam. Para funções a rede de segurança é a guarda
-- do catálogo (supabase/tests/0003, item 4): função security definer nova executável por anon ou
-- authenticated derruba o CI.
alter default privileges in schema public revoke truncate, references, trigger on tables from authenticated, anon;
alter default privileges in schema public revoke insert, update, delete on tables from authenticated;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from authenticated, anon;
revoke all on all sequences in schema public from authenticated, anon;

-- Limite: "alter default privileges" só mexe nos padrões do papel que roda esta migration. No Supabase
-- real, supabase_admin também tem padrões que dão "all" a anon e authenticated no schema public, e o
-- papel postgres não consegue alterá-los. Tabela criada por supabase_admin (ou por outro papel) nasce
-- aberta: só a guarda do catálogo (supabase/tests/0003, item 3b) segura esse caso.
-- Um REVOKE sobre privilégio concedido por OUTRO papel só emite WARNING e não revoga nada. Por isso a
-- verificação no fim desta migration (bloco "0010: conferência") derruba a migration se qualquer
-- privilégio proibido continuar valendo: melhor falhar alto do que "passar" sem ter fechado a lacuna.

-- Quem de fora não cria objetos nos schemas do search_path das funções definer. Com pg_temp por último
-- (item 2) a tabela temporária não engana mais, mas um objeto criado em public ou extensions (por
-- exemplo uma função com o mesmo nome e tipos exatos de uma chamada) ainda seria achado antes do
-- objeto de verdade e rodaria com o poder do dono. Projetos antigos podem ter herdado CREATE para o
-- PUBLIC no schema public.
revoke create on schema public from public, anon, authenticated;
-- Os dois a seguir podem não caber ao papel que roda a migration (no Supabase o schema extensions
-- e o banco pertencem a outro papel): então o REVOKE só avisa. Quem decide é a conferência no fim
-- desta migration, que olha o resultado (has_schema_privilege e has_database_privilege) e falha se
-- anon ou authenticated ainda puder criar objeto em public, em extensions ou no banco. A guarda de
-- supabase/tests/0003 (item 3d) repete a conferência no banco do CI.
do $$
begin
  if to_regnamespace('extensions') is not null then
    execute 'revoke create on schema extensions from public, anon, authenticated';
  end if;
exception when others then
  raise warning '0010: não foi possível revogar CREATE no schema extensions (%). Confira à mão com has_schema_privilege.', sqlerrm;
end $$;
do $$
begin
  execute format('revoke create on database %I from public, anon, authenticated', current_database());
exception when others then
  raise warning '0010: não foi possível revogar CREATE no banco (%). Confira à mão com has_database_privilege.', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- 2. search_path das funções security definer, com pg_temp por último
-- O Postgres procura tabela sem schema primeiro em pg_temp (as tabelas temporárias
-- da sessão). Sem pg_temp declarado por último, uma tabela temporária criada pelo
-- chamador (pg_temp.staff, pg_temp.tables, pg_temp.orders...) esconde a tabela do
-- public e engana a função, que roda com o poder do dono e ignora a RLS.
-- alter function mantém corpo e grants; só troca a configuração.
-- ---------------------------------------------------------------------
alter function public.is_staff(uuid, text[])        set search_path = public, pg_temp;
alter function public.get_guest_menu(text, text)    set search_path = public, pg_temp;
alter function public.get_guest_order(uuid, text)   set search_path = public, pg_temp;
alter function public.bootstrap_first_owner()       set search_path = public, pg_temp;
-- place_order é recriada logo abaixo (item 3), já com o search_path certo.

-- ---------------------------------------------------------------------
-- 3. Idempotência por mesa, não pelo banco inteiro
-- Antes: orders.idempotency_key era única no banco todo e place_order a procurava
-- antes de validar a mesa. Quem tinha o token de QUALQUER mesa e reenviasse a chave
-- de um pedido de outro restaurante recebia o id e o public_token dele.
-- Agora: a chave é única por restaurante, e place_order só a procura dentro da MESMA
-- MESA, depois de validar a mesa. Chave igual em restaurantes diferentes são pedidos
-- diferentes. Chave igual em outra mesa do MESMO restaurante nunca devolve o pedido
-- alheio: a função tenta criar um pedido novo e o banco recusa (unique_violation,
-- 23505), sem gravar nada (a transação inteira é desfeita, inclusive o order_seq).
-- ---------------------------------------------------------------------
alter table public.orders drop constraint orders_idempotency_key_key;
alter table public.orders
  add constraint orders_restaurant_id_idempotency_key_key unique (restaurant_id, idempotency_key);

-- Igual à 0001, com 3 mudanças (marcadas com "0010"): search_path com pg_temp, a mesa
-- é validada antes da chave, e a chave só vale dentro da mesma mesa.
create or replace function public.place_order(
  p_table_token     text,
  p_items           jsonb,           -- [{"menu_item_id":uuid,"quantity":int,"option_ids":[uuid],"note":text}]
  p_payment_method  text default 'counter',
  p_tip_cents       int  default 0,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp   -- 0010: pg_temp por último
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
  -- 0010: a mesa é validada primeiro; sem token de mesa válido nada mais é consultado
  select * into v_table from tables where qr_token = p_table_token and active;
  if not found then raise exception 'TABLE_NOT_FOUND'; end if;

  select * into v_rest from restaurants where id = v_table.restaurant_id;

  if p_idempotency_key is not null then
    -- 0010: duas chamadas ao mesmo tempo com a mesma chave (toque duplo) esperam uma pela
    -- outra: a segunda, quando entra, já enxerga o pedido da primeira e o devolve, em vez
    -- de falhar na chave única. O cadeado é por restaurante + chave e some no fim da transação.
    perform pg_advisory_xact_lock(hashtextextended(v_rest.id::text || ':' || p_idempotency_key, 0));

    -- Mesma chave na MESMA MESA (toque duplo, nova tentativa com Wi-Fi ruim): devolve o primeiro pedido.
    -- 0010: a busca é só nesta mesa (restaurant_id entra para usar o índice único).
    select * into v_existing from orders
     where restaurant_id = v_rest.id and table_id = v_table.id and idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('id', v_existing.id, 'number', v_existing.number,
                                'public_token', v_existing.public_token);
    end if;
  end if;

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

-- Os grants não mudam: create or replace preserva os da 0001 (service_role) e da 0005
-- (anon e authenticated); public continua sem execute. Os testes conferem.

-- ---------------------------------------------------------------------
-- 0010: conferência
-- Um REVOKE de privilégio dado por outro papel só emite WARNING e não revoga nada. Aqui a migration
-- confere o resultado e falha (a transação inteira é desfeita) se alguma lacuna continuar aberta.
-- ---------------------------------------------------------------------
do $$
declare
  v_lista text;
  v_extra text[] := case when current_setting('server_version_num')::int >= 170000
                         then array['maintain'] else '{}'::text[] end;
begin
  -- tabelas existentes: anon e authenticated sem os privilégios que ignoram a RLS
  select string_agg(c.relname || ' (' || r || ': ' || p || ')', ', ' order by c.relname, r, p) into v_lista
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join unnest(array['anon', 'authenticated']) r
    cross join unnest(array['truncate', 'references', 'trigger'] || v_extra) p
   where n.nspname = 'public' and c.relkind in ('r', 'p')
     and has_table_privilege(r, c.oid, p);
  if v_lista is not null then
    raise exception '0010: privilégio que ignora a RLS continua valendo (o REVOKE não pegou; rode a migration com o papel dono das tabelas): %', v_lista;
  end if;

  -- padrões futuros do papel que roda a migration, no schema public
  select string_agg(case d.defaclobjtype when 'r' then 'tabelas' else 'sequências' end || ': ' ||
                    g.rolname || ' ' || a.privilege_type, ', ' order by d.defaclobjtype, g.rolname, a.privilege_type)
    into v_lista
    from pg_default_acl d
    cross join lateral aclexplode(d.defaclacl) a
    join pg_roles g on g.oid = a.grantee
   where d.defaclrole = (select oid from pg_roles where rolname = current_user)
     and d.defaclnamespace = 'public'::regnamespace
     and g.rolname in ('anon', 'authenticated')
     and (   (d.defaclobjtype = 'r' and (g.rolname = 'anon'
              or a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN')))
          or d.defaclobjtype = 'S');
  if v_lista is not null then
    raise exception '0010: o padrão de privilégios das tabelas/sequências futuras continua aberto: %', v_lista;
  end if;

  -- CREATE nos schemas do search_path das funções definer e no banco: has_*_privilege já inclui o que
  -- vem do PUBLIC. O REVOKE acima só avisa quando o privilégio foi dado por outro papel; aqui falha alto.
  select string_agg(alvo || ' (' || r || ')', ', ' order by alvo, r) into v_lista
    from unnest(array['anon', 'authenticated']) r
    cross join lateral (
      select 'schema ' || n.nspname as alvo
        from pg_namespace n
       where n.nspname in ('public', 'extensions') and has_schema_privilege(r, n.oid, 'create')
      union all
      select 'banco ' || current_database()
       where has_database_privilege(r, current_database(), 'create')
    ) x;
  if v_lista is not null then
    raise exception '0010: quem é de fora ainda pode criar objetos em: % (o REVOKE de CREATE não pegou; rode com o papel dono do schema/banco)', v_lista;
  end if;
end $$;
