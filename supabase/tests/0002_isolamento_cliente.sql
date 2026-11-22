-- =====================================================================
-- Teste de isolamento · 0002 · Funções do cliente (visitante anônimo com token)
--
-- O cliente não lê tabelas: só chama get_guest_menu, get_guest_order e place_order
-- (security definer, 0001/0005/0009). Estas funções rodam sem RLS, então o filtro
-- por restaurante e por token é a única barreira. Aqui o visitante é o papel "anon".
--
--   e) cardápio: slug de um restaurante com token de mesa de outro, mesa inativa,
--      token inexistente; só categorias e itens do restaurante da mesa
--      pedido: token errado, token de outro pedido, token de mesa
--      place_order: item ou opção de outro restaurante, mesa inativa, número
--      sequencial por restaurante, nada muda fora do restaurante da mesa
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

-- Entra como visitante sem login (papel "anon"), como o cliente no celular.
create function pg_temp.entrar_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
end $$;

-- Quantas linhas o papel atual enxerga (RLS vale). Com prefixo, só as do restaurante daquele prefixo.
create function pg_temp.contar(p_tabela text, p_prefixo text default null) returns bigint
language plpgsql as $$
declare
  v_n bigint;
begin
  if p_prefixo is null then
    execute format('select count(*) from public.%I', p_tabela) into v_n;
  else
    execute format('select count(*) from public.%I where %I::text like %L',
                   p_tabela, pg_temp.chave(p_tabela), p_prefixo || '-%') into v_n;
  end if;
  return v_n;
end $$;

-- Impressão digital de TUDO que não é do restaurante do prefixo (todas as colunas das 10 tabelas).
-- Chamar como dono do banco. Se mudar entre dois momentos, alguma linha de fora foi alterada.
create function pg_temp.foto_fora(p_prefixo text) returns text
language plpgsql as $$
declare
  t record;
  v_parte text;
  v_tudo text := '';
begin
  for t in select tabela from pg_temp.tabelas() order by tabela loop
    execute format($q$select coalesce(string_agg(x::text, '|' order by x::text), '') from public.%I x where coalesce((%s)::text, '') not like %L$q$,
                   t.tabela, pg_temp.dono_sql(t.tabela), p_prefixo || '-%') into v_parte;
    v_tudo := v_tudo || t.tabela || '=' || v_parte || E'\n';
  end loop;
  return md5(v_tudo);
end $$;

-- Roda um UPDATE e devolve quantas linhas ele atingiu.
create function pg_temp.atualizar(p_sql text) returns bigint
language plpgsql as $$
declare
  v_n bigint;
begin
  execute p_sql;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- Quantos UUIDs do JSON NÃO começam com o prefixo do restaurante (qualquer id de fora é vazamento).
create function pg_temp.ids_de_fora(p_json jsonb, p_prefixo text) returns bigint
language sql immutable as $$
  select count(*)
    from regexp_matches(p_json::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'g') m
   where m[1] not like p_prefixo || '-%'
$$;

-- Chama place_order como o papel atual e devolve a mensagem de erro (null se deu certo).
-- Em caso de erro o bloco desfaz tudo o que a função fez até ali.
create function pg_temp.erro_do_pedido(p_token_mesa text, p_itens jsonb) returns text
language plpgsql as $$
begin
  perform public.place_order(p_token_mesa, p_itens, 'counter', 0, null);
  return null;
exception when others then
  return sqlerrm;
end $$;

-- Monta o JSON de itens: um só item, com quantidade e opções.
create function pg_temp.linha(p_item uuid, p_qtd int, p_opcoes uuid[] default '{}') returns jsonb
language sql immutable as $$
  select jsonb_build_object('menu_item_id', p_item, 'quantity', p_qtd, 'option_ids', to_jsonb(p_opcoes))
$$;

-- ---------------------------------------------------------------------
-- e1) get_guest_menu
-- ---------------------------------------------------------------------
do $$
declare
  v jsonb;
begin
  perform pg_temp.entrar_anon();

  -- A com token de A: só categorias e itens de A
  v := public.get_guest_menu('restaurante-a-teste', 'token-mesa-a1');
  if v is null then
    raise exception 'get_guest_menu(A, mesa A1) devolveu null; deveria devolver o cardápio de A';
  end if;
  if v->'restaurant'->>'slug' <> 'restaurante-a-teste' or v->'table'->>'label' <> 'Mesa A1' then
    raise exception 'get_guest_menu(A, mesa A1) devolveu restaurante/mesa errados: %', v->'restaurant';
  end if;
  if jsonb_array_length(v->'categories') <> 2 or jsonb_array_length(v->'items') <> 2 then
    raise exception 'get_guest_menu(A, mesa A1) deveria devolver 2 categorias e 2 itens e devolveu % e %',
                    jsonb_array_length(v->'categories'), jsonb_array_length(v->'items');
  end if;
  if pg_temp.ids_de_fora(v, 'aaaaaaaa') <> 0 then
    raise exception 'VAZAMENTO: get_guest_menu(A, mesa A1) devolveu ids que não são do restaurante A: %', v;
  end if;
  if v::text like '%Restaurante B%' or v::text like '% B"%' then
    raise exception 'VAZAMENTO: get_guest_menu(A, mesa A1) devolveu nome de dado do restaurante B: %', v;
  end if;

  -- B com token de B: o espelho
  v := public.get_guest_menu('restaurante-b-teste', 'token-mesa-b1');
  if v is null or jsonb_array_length(v->'categories') <> 2 or jsonb_array_length(v->'items') <> 2 then
    raise exception 'get_guest_menu(B, mesa B1) deveria devolver o cardápio de B (2 categorias, 2 itens): %', v;
  end if;
  if pg_temp.ids_de_fora(v, 'bbbbbbbb') <> 0 then
    raise exception 'VAZAMENTO: get_guest_menu(B, mesa B1) devolveu ids que não são do restaurante B: %', v;
  end if;

  -- Slug de um restaurante com token de mesa de outro: null
  if public.get_guest_menu('restaurante-b-teste', 'token-mesa-a1') is not null then
    raise exception 'VAZAMENTO: get_guest_menu com slug de B e token da mesa de A devolveu cardápio';
  end if;
  if public.get_guest_menu('restaurante-a-teste', 'token-mesa-b1') is not null then
    raise exception 'VAZAMENTO: get_guest_menu com slug de A e token da mesa de B devolveu cardápio';
  end if;
  if public.get_guest_menu('harbor-pine', 'token-mesa-a1') is not null then
    raise exception 'VAZAMENTO: get_guest_menu com slug do restaurante do seed e token da mesa de A devolveu cardápio';
  end if;

  -- Mesa inativa: null (mesmo com o slug certo)
  if public.get_guest_menu('restaurante-a-teste', 'token-mesa-a2-inativa') is not null then
    raise exception 'get_guest_menu devolveu cardápio para uma mesa inativa de A';
  end if;
  if public.get_guest_menu('restaurante-b-teste', 'token-mesa-b2-inativa') is not null then
    raise exception 'get_guest_menu devolveu cardápio para uma mesa inativa de B';
  end if;

  -- Token inexistente, vazio ou nulo: null
  if public.get_guest_menu('restaurante-a-teste', 'token-que-nao-existe') is not null
     or public.get_guest_menu('restaurante-a-teste', '') is not null
     or public.get_guest_menu('restaurante-a-teste', null) is not null
     or public.get_guest_menu(null, 'token-mesa-a1') is not null then
    raise exception 'get_guest_menu devolveu cardápio com token ou slug inválido';
  end if;

  perform pg_temp.voltar_dono();
end $$;

-- ---------------------------------------------------------------------
-- e2) get_guest_order
-- ---------------------------------------------------------------------
do $$
declare
  v jsonb;
begin
  perform pg_temp.entrar_anon();

  -- Pedido de A com o token do próprio pedido: só dados de A
  v := public.get_guest_order(pg_temp.id('a', 8, 1), 'token-pedido-a1');
  if v is null then
    raise exception 'get_guest_order(pedido A1, token do pedido A1) devolveu null';
  end if;
  if v->>'restaurant_name' <> 'Restaurante A (teste de isolamento)' or v->>'table_label' <> 'Mesa A1'
     or jsonb_array_length(v->'items') <> 1 then
    raise exception 'get_guest_order(pedido A1) devolveu dados errados: %', v;
  end if;
  if pg_temp.ids_de_fora(v, 'aaaaaaaa') <> 0 then
    raise exception 'VAZAMENTO: get_guest_order(pedido A1) devolveu ids que não são do restaurante A: %', v;
  end if;

  -- O espelho em B
  v := public.get_guest_order(pg_temp.id('b', 8, 2), 'token-pedido-b2');
  if v is null or v->>'restaurant_name' <> 'Restaurante B (teste de isolamento)'
     or pg_temp.ids_de_fora(v, 'bbbbbbbb') <> 0 then
    raise exception 'get_guest_order(pedido B2, token do pedido B2) devolveu dados errados: %', v;
  end if;

  -- Token errado, de outro pedido do mesmo restaurante, de pedido de outro restaurante,
  -- da mesa, vazio ou nulo: null
  if public.get_guest_order(pg_temp.id('a', 8, 1), 'token-errado') is not null then
    raise exception 'VAZAMENTO: get_guest_order abriu o pedido A1 com token errado';
  end if;
  if public.get_guest_order(pg_temp.id('a', 8, 1), 'token-pedido-a2') is not null then
    raise exception 'VAZAMENTO: get_guest_order abriu o pedido A1 com o token do pedido A2';
  end if;
  if public.get_guest_order(pg_temp.id('a', 8, 1), 'token-pedido-b1') is not null then
    raise exception 'VAZAMENTO: get_guest_order abriu o pedido A1 com o token de um pedido de B';
  end if;
  if public.get_guest_order(pg_temp.id('b', 8, 1), 'token-pedido-a1') is not null then
    raise exception 'VAZAMENTO: get_guest_order abriu o pedido B1 com o token de um pedido de A';
  end if;
  if public.get_guest_order(pg_temp.id('a', 8, 1), 'token-mesa-a1') is not null then
    raise exception 'VAZAMENTO: get_guest_order abriu o pedido A1 com o token da mesa (QR) em vez do token do pedido';
  end if;
  if public.get_guest_order(pg_temp.id('a', 8, 1), '') is not null
     or public.get_guest_order(pg_temp.id('a', 8, 1), null) is not null then
    raise exception 'VAZAMENTO: get_guest_order abriu o pedido A1 com token vazio ou nulo';
  end if;
  -- Pedido que não existe, com um token que existe
  if public.get_guest_order(pg_temp.id('c', 8, 1), 'token-pedido-a1') is not null then
    raise exception 'get_guest_order devolveu algo para um pedido inexistente';
  end if;

  perform pg_temp.voltar_dono();
end $$;

-- ---------------------------------------------------------------------
-- e3) place_order: o que NÃO pode acontecer
-- ---------------------------------------------------------------------
-- Cada erro tem de vir da validação certa, e uma tentativa que falha não pode deixar
-- rastro: nem pedido novo, nem número consumido na sequência do restaurante.
do $$
declare
  v_fora_antes text;
  v_erro text;
  v_seq_a int;
  v_seq_b int;
begin
  v_fora_antes := pg_temp.foto_fora('zzzzzzzz');   -- foto de tudo: nenhuma linha começa com 'z'
  perform pg_temp.entrar_anon();

  -- item de B pedido pela mesa de A (e o espelho)
  v_erro := pg_temp.erro_do_pedido('token-mesa-a1', jsonb_build_array(pg_temp.linha(pg_temp.id('b', 5, 1), 1)));
  if v_erro is distinct from 'ITEM_NOT_FOUND' then
    raise exception 'place_order com mesa de A e item de B deveria dar ITEM_NOT_FOUND e deu: %', coalesce(v_erro, 'sucesso (VAZAMENTO: pedido criado)');
  end if;
  v_erro := pg_temp.erro_do_pedido('token-mesa-b1', jsonb_build_array(pg_temp.linha(pg_temp.id('a', 5, 1), 1)));
  if v_erro is distinct from 'ITEM_NOT_FOUND' then
    raise exception 'place_order com mesa de B e item de A deveria dar ITEM_NOT_FOUND e deu: %', coalesce(v_erro, 'sucesso (VAZAMENTO: pedido criado)');
  end if;

  -- item de A válido com opção do grupo de B; opção de B num item de A sem opções; e o espelho
  v_erro := pg_temp.erro_do_pedido('token-mesa-a1', jsonb_build_array(
              pg_temp.linha(pg_temp.id('a', 5, 1), 1, array[pg_temp.id('b', 7, 2)])));
  if v_erro is distinct from 'BAD_MODIFIER' then
    raise exception 'place_order com item de A e opção do grupo de B deveria dar BAD_MODIFIER e deu: %', coalesce(v_erro, 'sucesso (VAZAMENTO: pedido criado)');
  end if;
  v_erro := pg_temp.erro_do_pedido('token-mesa-a1', jsonb_build_array(
              pg_temp.linha(pg_temp.id('a', 5, 2), 1, array[pg_temp.id('b', 7, 3)])));
  if v_erro is distinct from 'BAD_MODIFIER' then
    raise exception 'place_order com item de A e opção extra de B deveria dar BAD_MODIFIER e deu: %', coalesce(v_erro, 'sucesso (VAZAMENTO: pedido criado)');
  end if;
  v_erro := pg_temp.erro_do_pedido('token-mesa-b1', jsonb_build_array(
              pg_temp.linha(pg_temp.id('b', 5, 1), 1, array[pg_temp.id('a', 7, 2)])));
  if v_erro is distinct from 'BAD_MODIFIER' then
    raise exception 'place_order com item de B e opção do grupo de A deveria dar BAD_MODIFIER e deu: %', coalesce(v_erro, 'sucesso (VAZAMENTO: pedido criado)');
  end if;

  -- pedido misto: primeira linha boa de A, segunda de B. Tudo ou nada.
  v_erro := pg_temp.erro_do_pedido('token-mesa-a1', jsonb_build_array(
              pg_temp.linha(pg_temp.id('a', 5, 1), 1, array[pg_temp.id('a', 7, 1)]),
              pg_temp.linha(pg_temp.id('b', 5, 2), 1)));
  if v_erro is distinct from 'ITEM_NOT_FOUND' then
    raise exception 'place_order com uma linha de A e outra de B deveria dar ITEM_NOT_FOUND e deu: %', coalesce(v_erro, 'sucesso (VAZAMENTO: pedido criado)');
  end if;

  -- mesa inativa e token inexistente
  v_erro := pg_temp.erro_do_pedido('token-mesa-a2-inativa', jsonb_build_array(pg_temp.linha(pg_temp.id('a', 5, 2), 1)));
  if v_erro is distinct from 'TABLE_NOT_FOUND' then
    raise exception 'place_order em mesa inativa de A deveria dar TABLE_NOT_FOUND e deu: %', coalesce(v_erro, 'sucesso (pedido criado em mesa inativa)');
  end if;
  v_erro := pg_temp.erro_do_pedido('token-que-nao-existe', jsonb_build_array(pg_temp.linha(pg_temp.id('a', 5, 2), 1)));
  if v_erro is distinct from 'TABLE_NOT_FOUND' then
    raise exception 'place_order com token de mesa inexistente deveria dar TABLE_NOT_FOUND e deu: %', coalesce(v_erro, 'sucesso (pedido criado)');
  end if;

  perform pg_temp.voltar_dono();

  -- Nenhuma tentativa falha deixou rastro: o banco inteiro está igual e as sequências não andaram
  if pg_temp.foto_fora('zzzzzzzz') <> v_fora_antes then
    raise exception 'place_order com erro deixou rastro no banco (pedido, item de pedido ou número da sequência)';
  end if;
  select order_seq into v_seq_a from public.restaurants where id = pg_temp.id('a', 1, 1);
  select order_seq into v_seq_b from public.restaurants where id = pg_temp.id('b', 1, 1);
  if v_seq_a <> 102 or v_seq_b <> 502 then
    raise exception 'place_order com erro consumiu número de pedido: sequência de A = % (esperado 102), de B = % (esperado 502)', v_seq_a, v_seq_b;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- e4) place_order: pedido da mesa de A fica em A, com a sequência de A
-- ---------------------------------------------------------------------
do $$
declare
  v_fora_de_a text;
  v_fora_de_b text;
  v_res jsonb;
  v_pedido public.orders%rowtype;
  v_item public.order_items%rowtype;
  v_guest jsonb;
  v_n int;
begin
  v_fora_de_a := pg_temp.foto_fora('aaaaaaaa');   -- tudo que não é de A: restaurante B, seed...

  perform pg_temp.entrar_anon();
  -- 2 x Café A com leite de aveia (500 + 75) = 1150
  v_res := public.place_order('token-mesa-a1',
             jsonb_build_array(pg_temp.linha(pg_temp.id('a', 5, 1), 2, array[pg_temp.id('a', 7, 2)])),
             'counter', 0, null);
  perform pg_temp.voltar_dono();

  select * into v_pedido from public.orders where id = (v_res->>'id')::uuid;
  if v_pedido.restaurant_id is distinct from pg_temp.id('a', 1, 1) then
    raise exception 'VAZAMENTO: pedido da mesa de A foi gravado no restaurante % (esperado A)', v_pedido.restaurant_id;
  end if;
  if v_pedido.table_id is distinct from pg_temp.id('a', 3, 1) then
    raise exception 'pedido da mesa A1 foi gravado na mesa %', v_pedido.table_id;
  end if;
  if v_pedido.number <> 103 or (v_res->>'number')::int <> 103 then
    raise exception 'o primeiro pedido novo de A deveria ser o número 103 (sequência de A em 102) e foi %', v_pedido.number;
  end if;
  if v_pedido.subtotal_cents <> 1150 or v_pedido.total_cents <> v_pedido.subtotal_cents + v_pedido.tax_cents then
    raise exception 'preço do pedido errado: subtotal % (esperado 1150), total %', v_pedido.subtotal_cents, v_pedido.total_cents;
  end if;

  select * into v_item from public.order_items where order_id = v_pedido.id;
  if v_item.menu_item_id is distinct from pg_temp.id('a', 5, 1) or v_item.unit_price_cents <> 575
     or v_item.quantity <> 2 or v_item.modifiers::text not like '%Leite de aveia A%' then
    raise exception 'item do pedido de A gravado errado: %', to_jsonb(v_item);
  end if;
  select count(*) into v_n from public.order_items where order_id = v_pedido.id;
  if v_n <> 1 then
    raise exception 'o pedido de A deveria ter 1 item e tem %', v_n;
  end if;

  -- A sequência de A andou; nada fora de A mexeu (nem a sequência de B, que mora na linha de B)
  if (select order_seq from public.restaurants where id = pg_temp.id('a', 1, 1)) <> 103 then
    raise exception 'a sequência de A deveria estar em 103';
  end if;
  if (select order_seq from public.restaurants where id = pg_temp.id('b', 1, 1)) <> 502 then
    raise exception 'VAZAMENTO: pedido da mesa de A mexeu na sequência de B (order_seq de B mudou)';
  end if;
  if pg_temp.foto_fora('aaaaaaaa') <> v_fora_de_a then
    raise exception 'VAZAMENTO: pedido da mesa de A alterou linhas de outros restaurantes';
  end if;
  if (select count(*) from public.orders where restaurant_id = pg_temp.id('b', 1, 1)) <> 2 then
    raise exception 'VAZAMENTO: apareceu ou sumiu pedido do restaurante B depois de um pedido da mesa de A';
  end if;

  -- O cliente acompanha o pedido com o token devolvido, e só vê dados de A
  perform pg_temp.entrar_anon();
  v_guest := public.get_guest_order(v_pedido.id, v_res->>'public_token');
  perform pg_temp.voltar_dono();
  -- (o pedido novo tem id aleatório, então a conferência é por nome, mesa, número e valor)
  if v_guest is null or v_guest->>'restaurant_name' <> 'Restaurante A (teste de isolamento)'
     or v_guest->>'table_label' <> 'Mesa A1' or (v_guest->>'number')::int <> 103
     or (v_guest->>'subtotal_cents')::int <> 1150 or v_guest::text like '%bbbbbbbb-%' then
    raise exception 'get_guest_order do pedido novo de A devolveu null ou dados de outro restaurante: %', v_guest;
  end if;

  -- Sequências independentes: B anda a sua, A não se mexe; um segundo pedido em A vira 104
  v_fora_de_b := pg_temp.foto_fora('bbbbbbbb');   -- tudo que não é de B (inclui o pedido novo de A)
  perform pg_temp.entrar_anon();
  v_res := public.place_order('token-mesa-b1',
             jsonb_build_array(pg_temp.linha(pg_temp.id('b', 5, 2), 1)), 'counter', 0, null);
  perform pg_temp.voltar_dono();
  select * into v_pedido from public.orders where id = (v_res->>'id')::uuid;
  if v_pedido.restaurant_id is distinct from pg_temp.id('b', 1, 1) or v_pedido.number <> 503 then
    raise exception 'o primeiro pedido novo de B deveria ser o número 503 no restaurante B e foi o % em %', v_pedido.number, v_pedido.restaurant_id;
  end if;
  if pg_temp.foto_fora('bbbbbbbb') <> v_fora_de_b then
    raise exception 'VAZAMENTO: pedido da mesa de B alterou linhas de outros restaurantes (A ou seed)';
  end if;

  perform pg_temp.entrar_anon();
  v_res := public.place_order('token-mesa-a1',
             jsonb_build_array(pg_temp.linha(pg_temp.id('a', 5, 2), 1)), 'counter', 0, null);
  perform pg_temp.voltar_dono();
  select number into v_n from public.orders where id = (v_res->>'id')::uuid;
  if v_n <> 104 then
    raise exception 'o segundo pedido novo de A deveria ser o número 104 e foi %', v_n;
  end if;
  if (select order_seq from public.restaurants where id = pg_temp.id('b', 1, 1)) <> 503 then
    raise exception 'VAZAMENTO: pedido da mesa de A mexeu na sequência de B (esperado 503)';
  end if;
end $$;

-- LACUNA CONHECIDA (de propósito, sem teste): place_order procura a idempotency_key no banco
-- inteiro, não por restaurante. Reenviar a chave de um pedido de B ('chave-b-1') por uma mesa
-- de A devolveria o id e o public_token do pedido de B. A correção pede uma migration nova
-- (por exemplo, chave única por restaurante) e fica para outro PR. Quando corrigir, acrescente
-- aqui o teste: place_order('token-mesa-a1', ..., 'chave-b-1') não pode devolver o pedido de B.

rollback;
