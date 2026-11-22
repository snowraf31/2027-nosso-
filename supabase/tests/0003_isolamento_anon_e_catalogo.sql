-- =====================================================================
-- Teste de isolamento · 0003 · Visitante anônimo e guarda do catálogo do banco
--
--   d) anon: nenhum privilégio nas tabelas (SELECT, INSERT, UPDATE e DELETE dão erro de
--      permissão) e não executa is_staff nem bootstrap_first_owner
--   f) guarda do catálogo (vale para tabelas FUTURAS): toda tabela do schema public tem RLS
--      ligada; anon não tem privilégio nenhum em tabela ou view do public; authenticated só
--      escreve nas 3 colunas da cozinha; anon só executa as 3 funções do cliente entre as
--      security definer; tabela do Realtime tem RLS.
--      Tabela nova sem RLS, ou com grant aberto demais, derruba o CI aqui.
--
-- Autocontido: cria os próprios dados e termina em rollback. Falha com raise exception.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- Dados de teste (tudo é desfeito pelo rollback no fim do arquivo)
--
-- UUIDs fixos e legíveis: <restaurante>-<tipo>-0000-0000-<número>
--   restaurante: aaaaaaaa = A, bbbbbbbb = B, cccccccc = usuário sem restaurante
--   tipo: 0001 restaurante, 0002 usuário, 0003 mesa, 0004 categoria, 0005 item,
--         0006 grupo de adicionais, 0007 opção, 0008 pedido, 0009 item do pedido
-- Assim, qualquer linha de B que apareça numa consulta de A é fácil de achar.
--
-- Cada restaurante tem 2 mesas (a 2 é inativa), 2 categorias, 2 itens, 2 grupos,
-- 4 opções, 2 vínculos item-grupo, 2 pedidos e 2 itens de pedido, mais um dono
-- e um usuário da cozinha. Os restaurantes entram ANTES dos usuários para o
-- gatilho bootstrap_first_owner (0006) não promover ninguém por acidente.
-- ---------------------------------------------------------------------

-- Restaurante A -------------------------------------------------------
insert into public.restaurants (id, slug, name, order_seq) values
  ('aaaaaaaa-0001-0000-0000-000000000001', 'restaurante-a-teste', 'Restaurante A (teste de isolamento)', 102);

insert into public.tables (id, restaurant_id, label, qr_token, active) values
  ('aaaaaaaa-0003-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'Mesa A1', 'token-mesa-a1', true),
  ('aaaaaaaa-0003-0000-0000-000000000002', 'aaaaaaaa-0001-0000-0000-000000000001', 'Mesa A2 (inativa)', 'token-mesa-a2-inativa', false);

insert into public.menu_categories (id, restaurant_id, name, position) values
  ('aaaaaaaa-0004-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'Bebidas A', 1),
  ('aaaaaaaa-0004-0000-0000-000000000002', 'aaaaaaaa-0001-0000-0000-000000000001', 'Pratos A', 2);

insert into public.menu_items (id, restaurant_id, category_id, name, price_cents, position) values
  ('aaaaaaaa-0005-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'aaaaaaaa-0004-0000-0000-000000000001', 'Café A', 500, 1),
  ('aaaaaaaa-0005-0000-0000-000000000002', 'aaaaaaaa-0001-0000-0000-000000000001', 'aaaaaaaa-0004-0000-0000-000000000002', 'Prato A', 1500, 1);

insert into public.modifier_groups (id, restaurant_id, name, min_select, max_select) values
  ('aaaaaaaa-0006-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'Leite A', 1, 1),
  ('aaaaaaaa-0006-0000-0000-000000000002', 'aaaaaaaa-0001-0000-0000-000000000001', 'Extras A', 0, 2);

insert into public.modifier_options (id, group_id, name, price_cents, position) values
  ('aaaaaaaa-0007-0000-0000-000000000001', 'aaaaaaaa-0006-0000-0000-000000000001', 'Leite integral A', 0, 1),
  ('aaaaaaaa-0007-0000-0000-000000000002', 'aaaaaaaa-0006-0000-0000-000000000001', 'Leite de aveia A', 75, 2),
  ('aaaaaaaa-0007-0000-0000-000000000003', 'aaaaaaaa-0006-0000-0000-000000000002', 'Queijo extra A', 100, 1),
  ('aaaaaaaa-0007-0000-0000-000000000004', 'aaaaaaaa-0006-0000-0000-000000000002', 'Bacon extra A', 200, 2);

insert into public.item_modifier_groups (item_id, group_id, position) values
  ('aaaaaaaa-0005-0000-0000-000000000001', 'aaaaaaaa-0006-0000-0000-000000000001', 1),
  ('aaaaaaaa-0005-0000-0000-000000000002', 'aaaaaaaa-0006-0000-0000-000000000002', 1);

insert into public.orders (id, restaurant_id, table_id, number, status, payment_method,
                           subtotal_cents, tax_cents, total_cents, idempotency_key, public_token) values
  ('aaaaaaaa-0008-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'aaaaaaaa-0003-0000-0000-000000000001', 101, 'new',       'counter',  575,  40,  615, 'chave-a-1', 'token-pedido-a1'),
  ('aaaaaaaa-0008-0000-0000-000000000002', 'aaaaaaaa-0001-0000-0000-000000000001', 'aaaaaaaa-0003-0000-0000-000000000001', 102, 'preparing', 'counter', 1500, 105, 1605, null,           'token-pedido-a2');

insert into public.order_items (id, order_id, menu_item_id, name_snapshot, unit_price_cents, quantity, modifiers) values
  ('aaaaaaaa-0009-0000-0000-000000000001', 'aaaaaaaa-0008-0000-0000-000000000001', 'aaaaaaaa-0005-0000-0000-000000000001', 'Café A',  575, 1, '[{"name":"Leite de aveia A","price_cents":75}]'),
  ('aaaaaaaa-0009-0000-0000-000000000002', 'aaaaaaaa-0008-0000-0000-000000000002', 'aaaaaaaa-0005-0000-0000-000000000002', 'Prato A', 1500, 1, '[]');

-- Restaurante B -------------------------------------------------------
insert into public.restaurants (id, slug, name, order_seq) values
  ('bbbbbbbb-0001-0000-0000-000000000001', 'restaurante-b-teste', 'Restaurante B (teste de isolamento)', 502);

insert into public.tables (id, restaurant_id, label, qr_token, active) values
  ('bbbbbbbb-0003-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'Mesa B1', 'token-mesa-b1', true),
  ('bbbbbbbb-0003-0000-0000-000000000002', 'bbbbbbbb-0001-0000-0000-000000000001', 'Mesa B2 (inativa)', 'token-mesa-b2-inativa', false);

insert into public.menu_categories (id, restaurant_id, name, position) values
  ('bbbbbbbb-0004-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'Bebidas B', 1),
  ('bbbbbbbb-0004-0000-0000-000000000002', 'bbbbbbbb-0001-0000-0000-000000000001', 'Pratos B', 2);

insert into public.menu_items (id, restaurant_id, category_id, name, price_cents, position) values
  ('bbbbbbbb-0005-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'Café B', 500, 1),
  ('bbbbbbbb-0005-0000-0000-000000000002', 'bbbbbbbb-0001-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000002', 'Prato B', 1500, 1);

insert into public.modifier_groups (id, restaurant_id, name, min_select, max_select) values
  ('bbbbbbbb-0006-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'Leite B', 1, 1),
  ('bbbbbbbb-0006-0000-0000-000000000002', 'bbbbbbbb-0001-0000-0000-000000000001', 'Extras B', 0, 2);

insert into public.modifier_options (id, group_id, name, price_cents, position) values
  ('bbbbbbbb-0007-0000-0000-000000000001', 'bbbbbbbb-0006-0000-0000-000000000001', 'Leite integral B', 0, 1),
  ('bbbbbbbb-0007-0000-0000-000000000002', 'bbbbbbbb-0006-0000-0000-000000000001', 'Leite de aveia B', 75, 2),
  ('bbbbbbbb-0007-0000-0000-000000000003', 'bbbbbbbb-0006-0000-0000-000000000002', 'Queijo extra B', 100, 1),
  ('bbbbbbbb-0007-0000-0000-000000000004', 'bbbbbbbb-0006-0000-0000-000000000002', 'Bacon extra B', 200, 2);

insert into public.item_modifier_groups (item_id, group_id, position) values
  ('bbbbbbbb-0005-0000-0000-000000000001', 'bbbbbbbb-0006-0000-0000-000000000001', 1),
  ('bbbbbbbb-0005-0000-0000-000000000002', 'bbbbbbbb-0006-0000-0000-000000000002', 1);

insert into public.orders (id, restaurant_id, table_id, number, status, payment_method,
                           subtotal_cents, tax_cents, total_cents, idempotency_key, public_token) values
  ('bbbbbbbb-0008-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'bbbbbbbb-0003-0000-0000-000000000001', 501, 'new',       'counter',  575,  40,  615, 'chave-b-1', 'token-pedido-b1'),
  ('bbbbbbbb-0008-0000-0000-000000000002', 'bbbbbbbb-0001-0000-0000-000000000001', 'bbbbbbbb-0003-0000-0000-000000000001', 502, 'preparing', 'counter', 1500, 105, 1605, null,           'token-pedido-b2');

insert into public.order_items (id, order_id, menu_item_id, name_snapshot, unit_price_cents, quantity, modifiers) values
  ('bbbbbbbb-0009-0000-0000-000000000001', 'bbbbbbbb-0008-0000-0000-000000000001', 'bbbbbbbb-0005-0000-0000-000000000001', 'Café B',  575, 1, '[{"name":"Leite de aveia B","price_cents":75}]'),
  ('bbbbbbbb-0009-0000-0000-000000000002', 'bbbbbbbb-0008-0000-0000-000000000002', 'bbbbbbbb-0005-0000-0000-000000000002', 'Prato B', 1500, 1, '[]');

-- Usuários (e-mails fictícios). O gatilho do 0006 não deve criar vínculo nenhum.
insert into auth.users (id, email) values
  ('aaaaaaaa-0002-0000-0000-000000000001', 'dono-a@exemplo.test'),
  ('aaaaaaaa-0002-0000-0000-000000000002', 'cozinha-a@exemplo.test'),
  ('bbbbbbbb-0002-0000-0000-000000000001', 'dono-b@exemplo.test'),
  ('bbbbbbbb-0002-0000-0000-000000000002', 'cozinha-b@exemplo.test'),
  ('cccccccc-0002-0000-0000-000000000001', 'sem-restaurante@exemplo.test');

do $$
begin
  if exists (select 1 from public.staff where user_id::text like 'aaaaaaaa-%'
                                           or user_id::text like 'bbbbbbbb-%'
                                           or user_id::text like 'cccccccc-%') then
    raise exception 'PREPARO DO TESTE: o gatilho bootstrap_first_owner criou vínculo de staff para um usuário de teste';
  end if;
end $$;

insert into public.staff (user_id, restaurant_id, role) values
  ('aaaaaaaa-0002-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'owner'),
  ('aaaaaaaa-0002-0000-0000-000000000002', 'aaaaaaaa-0001-0000-0000-000000000001', 'kitchen'),
  ('bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'owner'),
  ('bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0001-0000-0000-000000000001', 'kitchen');
-- ---------------------------------------------------------------------
-- Ferramentas do teste (funções temporárias: somem junto com a transação)
-- ---------------------------------------------------------------------

-- UUID de teste: pg_temp.id('a', 5, 1) = item 1 do restaurante A (ver convenção acima).
-- Só a primeira letra de p_letra conta, então também aceita o prefixo 'aaaaaaaa'.
create function pg_temp.id(p_letra text, p_tipo int, p_n int) returns uuid
language sql immutable as $$
  select format('%s-%s-0000-0000-%s', repeat(left(p_letra, 1), 8), lpad(p_tipo::text, 4, '0'), lpad(p_n::text, 12, '0'))::uuid
$$;

-- Volta ao papel do dono do banco (sem RLS) para montar e conferir dados.
create function pg_temp.voltar_dono() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;

-- As 10 tabelas multi-restaurante e quantas linhas cada restaurante de teste tem.
create function pg_temp.tabelas() returns table (tabela text, linhas int)
language sql as $$
  select * from (values
    ('restaurants', 1), ('staff', 2), ('tables', 2), ('menu_categories', 2), ('menu_items', 2),
    ('modifier_groups', 2), ('modifier_options', 4), ('item_modifier_groups', 2),
    ('orders', 2), ('order_items', 2)
  ) v (tabela, linhas)
$$;

-- Coluna cujo texto começa com o prefixo do restaurante (a, b ou c) em cada tabela.
create function pg_temp.chave(p_tabela text) returns text
language sql immutable as $$
  select case p_tabela when 'staff' then 'restaurant_id' when 'item_modifier_groups' then 'item_id' else 'id' end
$$;

-- Expressão SQL (alias x) com o restaurante dono da linha, mesmo nas tabelas filhas.
-- Serve para fotografar "tudo que não é do restaurante X", inclusive linhas criadas com id aleatório.
create function pg_temp.dono_sql(p_tabela text) returns text
language sql immutable as $$
  select case p_tabela
    when 'restaurants' then 'x.id'
    when 'modifier_options' then '(select g.restaurant_id from public.modifier_groups g where g.id = x.group_id)'
    when 'item_modifier_groups' then '(select i.restaurant_id from public.menu_items i where i.id = x.item_id)'
    when 'order_items' then '(select o.restaurant_id from public.orders o where o.id = x.order_id)'
    else 'x.restaurant_id'
  end
$$;

-- Entra como usuário logado (papel "authenticated"), igual ao Supabase: o JWT diz quem é.
create function pg_temp.entrar_como(p_usuario uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     jsonb_build_object('sub', p_usuario, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;

-- Entra como visitante sem login (papel "anon"), como o cliente no celular.
create function pg_temp.entrar_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
end $$;

-- Exige que o banco recuse o comando por PERMISSÃO (SQLSTATE 42501, que cobre tanto
-- "permission denied" quanto "violates row-level security policy"). Se o comando passar,
-- ou falhar por outro motivo (o que mostra que a permissão deixou passar), o teste cai.
create function pg_temp.exige_negado(p_sql text, p_o_que_vazou text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception
    when insufficient_privilege then
      return;
    when others then
      raise exception 'FALHA DE SEGURANÇA: % (não foi barrado por permissão; erro: %). Comando: %',
                      p_o_que_vazou, sqlerrm, p_sql;
  end;
  raise exception 'FALHA DE SEGURANÇA: % (o banco aceitou o comando). Comando: %', p_o_que_vazou, p_sql;
end $$;

-- ---------------------------------------------------------------------
-- d) anon não tem privilégio em tabela nenhuma
-- ---------------------------------------------------------------------
do $$
declare
  t record;
  v_coluna text;
begin
  perform pg_temp.entrar_anon();
  for t in select tabela from pg_temp.tabelas() loop
    perform pg_temp.exige_negado(format('select count(*) from public.%I', t.tabela),
                                 'o visitante anônimo leu public.' || t.tabela);
    perform pg_temp.exige_negado(format('insert into public.%I default values', t.tabela),
                                 'o visitante anônimo inseriu em public.' || t.tabela);
    perform pg_temp.exige_negado(format('delete from public.%I where false', t.tabela),
                                 'o visitante anônimo apagou de public.' || t.tabela);
    -- primeira coluna da tabela, só para o UPDATE ter o que atualizar
    select a.attname into v_coluna from pg_attribute a
     where a.attrelid = ('public.' || t.tabela)::regclass and a.attnum > 0 and not a.attisdropped
     order by a.attnum limit 1;
    perform pg_temp.exige_negado(format('update public.%I set %I = %I where false', t.tabela, v_coluna, v_coluna),
                                 'o visitante anônimo atualizou public.' || t.tabela);
  end loop;

  -- as colunas que o staff pode atualizar também não valem para anon
  perform pg_temp.exige_negado($q$update public.orders set status = 'ready' where false$q$,
                               'o visitante anônimo mudou o status de pedido');
  perform pg_temp.exige_negado($q$update public.menu_items set available = false where false$q$,
                               'o visitante anônimo desligou item do cardápio');
  perform pg_temp.exige_negado($q$update public.modifier_options set available = false where false$q$,
                               'o visitante anônimo desligou opção de adicional');

  -- funções internas: anon não executa
  perform pg_temp.exige_negado(format('select public.is_staff(%L)', pg_temp.id('a', 1, 1)),
                               'o visitante anônimo executou is_staff');
  perform pg_temp.exige_negado('select public.bootstrap_first_owner()',
                               'o visitante anônimo executou bootstrap_first_owner');
  perform pg_temp.voltar_dono();

  -- nem o usuário logado executa bootstrap_first_owner (só o gatilho de auth.users)
  perform pg_temp.entrar_como(pg_temp.id('a', 2, 1));
  perform pg_temp.exige_negado('select public.bootstrap_first_owner()',
                               'o dono de A executou bootstrap_first_owner');
  perform pg_temp.voltar_dono();

  if has_function_privilege('anon', 'public.is_staff(uuid, text[])', 'execute')
     or has_function_privilege('anon', 'public.bootstrap_first_owner()', 'execute')
     or has_function_privilege('authenticated', 'public.bootstrap_first_owner()', 'execute') then
    raise exception 'catálogo: is_staff (anon) ou bootstrap_first_owner (anon, authenticated) ganhou EXECUTE';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- f) Guarda do catálogo: pega tabela nova esquecida
-- ---------------------------------------------------------------------
do $$
declare
  v_lista text;
begin
  -- 1. Toda tabela do public tem RLS ligada
  select string_agg(c.relname, ', ' order by c.relname) into v_lista
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity;
  if v_lista is not null then
    raise exception 'TABELA SEM RLS no schema public: %. Ligue com alter table ... enable row level security e crie as políticas (padrão do 0002_security.sql).', v_lista;
  end if;

  -- 2. anon não tem privilégio nenhum em tabela, view ou tabela externa do public
  --    (nível da tabela ou de coluna; qualquer um dos privilégios listados já conta)
  select string_agg(c.relname, ', ' order by c.relname) into v_lista
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
     and (has_table_privilege('anon', c.oid, 'select,insert,update,delete,truncate,references,trigger')
          or has_any_column_privilege('anon', c.oid, 'select,insert,update,references'));
  if v_lista is not null then
    raise exception 'O papel anon (visitante) tem privilégio em: %. O cliente só pode usar as funções com token; faça revoke all on ... from anon.', v_lista;
  end if;

  -- 3. authenticated: sem INSERT/DELETE em lugar nenhum; UPDATE só nas 3 colunas da cozinha
  select string_agg(c.relname, ', ' order by c.relname) into v_lista
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
     and (has_table_privilege('authenticated', c.oid, 'insert,delete')
          or has_any_column_privilege('authenticated', c.oid, 'insert'));
  if v_lista is not null then
    raise exception 'O papel authenticated (staff) pode inserir ou apagar em: %. Escrita de staff só pelas 3 colunas da cozinha; o resto passa por rota de API.', v_lista;
  end if;

  select string_agg(c.relname || '.' || a.attname, ', ' order by c.relname, a.attname) into v_lista
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
     and has_column_privilege('authenticated', c.oid, a.attnum, 'update')
     and (c.relname || '.' || a.attname) not in ('orders.status', 'menu_items.available', 'modifier_options.available');
  if v_lista is not null then
    raise exception 'O papel authenticated (staff) pode atualizar colunas fora da lista da cozinha: %. Permitidas: orders.status, menu_items.available, modifier_options.available (se a nova coluna é intencional, atualize esta lista com o dev-backend).', v_lista;
  end if;

  -- 4. Funções security definer ignoram a RLS: anon só pode executar as 3 funções do cliente
  select string_agg(p.oid::regprocedure::text, ', ' order by p.proname) into v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname not in ('get_guest_menu', 'get_guest_order', 'place_order')
     and has_function_privilege('anon', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');
  if v_lista is not null then
    raise exception 'Função security definer executável pelo visitante anônimo: %. Faça revoke execute ... from public, anon (padrão do 0004), ou, se for função do cliente com token, inclua na lista deste teste.', v_lista;
  end if;

  -- 5. O Realtime respeita a RLS só se ela estiver ligada na tabela publicada
  select string_agg(pt.tablename, ', ' order by pt.tablename) into v_lista
    from pg_publication_tables pt
    join pg_class c on c.relname = pt.tablename
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = pt.schemaname
   where pt.pubname = 'supabase_realtime' and pt.schemaname = 'public' and not c.relrowsecurity;
  if v_lista is not null then
    raise exception 'Tabela publicada no Realtime sem RLS: %', v_lista;
  end if;

  -- 6. Aviso (não derruba o CI): tabela nova ainda sem teste de isolamento dedicado
  select string_agg(c.relname, ', ' order by c.relname) into v_lista
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
     and c.relname not in (select tabela from pg_temp.tabelas());
  if v_lista is not null then
    raise warning 'Tabela(s) nova(s) no schema public sem teste de isolamento dedicado: %. Acrescente em pg_temp.tabelas() e nos dados de 0001_isolamento_staff.sql.', v_lista;
  end if;
end $$;

rollback;
