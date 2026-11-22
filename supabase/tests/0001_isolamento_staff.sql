-- =====================================================================
-- Teste de isolamento · 0001 · Staff de um restaurante não enxerga nem mexe em outro
--
-- Cobre as 10 tabelas multi-restaurante de 0001_schema.sql com a RLS e os grants
-- de 0002_security.sql, simulando os papéis do Supabase:
--   set local role authenticated + set_config('request.jwt.claims', ...)
--
--   a) staff de A vê as linhas de A (prova positiva) e nenhuma de B, e vice-versa
--   b) staff de A não altera B; colunas fora do grant, INSERT e DELETE dão erro de permissão
--   c) usuário logado sem staff (ou sem "sub" no JWT) não vê nada
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

-- Entra como usuário logado (papel "authenticated"), igual ao Supabase: o JWT diz quem é.
create function pg_temp.entrar_como(p_usuario uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     jsonb_build_object('sub', p_usuario, 'role', 'authenticated')::text, true);
  set local role authenticated;
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
    execute format('select coalesce(string_agg(x::text, ''|'' order by x::text), '''') from public.%I x where %I::text not like %L',
                   t.tabela, pg_temp.chave(t.tabela), p_prefixo || '-%') into v_parte;
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
-- a) Visão: cada staff vê só o próprio restaurante, em todas as tabelas
-- ---------------------------------------------------------------------
-- Para cada tabela confere três coisas:
--   1. zero linhas do outro restaurante (VAZAMENTO),
--   2. todas as linhas do próprio (senão o teste passaria "vendo nada"),
--   3. o total visível é igual ao do próprio (nada de seed, de C ou de terceiros).
-- Em staff cada um vê só a própria linha (política staff_read_own), por isso 1.
create procedure pg_temp.checar_visao(p_usuario uuid, p_proprio text, p_outro text, p_quem text)
language plpgsql as $$
declare
  t record;
  v_esperado bigint;
  v_outras bigint;
  v_proprias bigint;
  v_total bigint;
begin
  perform pg_temp.entrar_como(p_usuario);
  for t in select * from pg_temp.tabelas() loop
    v_esperado := case when t.tabela = 'staff' then 1 else t.linhas end;

    v_outras := pg_temp.contar(t.tabela, p_outro);
    if v_outras <> 0 then
      raise exception 'VAZAMENTO: % enxerga % linha(s) do restaurante % em public.%', p_quem, v_outras, upper(left(p_outro, 1)), t.tabela;
    end if;

    v_proprias := pg_temp.contar(t.tabela, p_proprio);
    if v_proprias <> v_esperado then
      raise exception 'VISÃO QUEBRADA: % deveria ver % linha(s) do próprio restaurante em public.%, mas vê %', p_quem, v_esperado, t.tabela, v_proprias;
    end if;

    v_total := pg_temp.contar(t.tabela);
    if v_total <> v_proprias then
      raise exception 'VAZAMENTO: % enxerga % linha(s) de outros restaurantes em public.% (além das % próprias)', p_quem, v_total - v_proprias, t.tabela, v_proprias;
    end if;
  end loop;
  perform pg_temp.voltar_dono();
end $$;

call pg_temp.checar_visao(pg_temp.id('a', 2, 1), 'aaaaaaaa', 'bbbbbbbb', 'o dono do restaurante A');
call pg_temp.checar_visao(pg_temp.id('a', 2, 2), 'aaaaaaaa', 'bbbbbbbb', 'a cozinha do restaurante A');
call pg_temp.checar_visao(pg_temp.id('b', 2, 1), 'bbbbbbbb', 'aaaaaaaa', 'o dono do restaurante B');
call pg_temp.checar_visao(pg_temp.id('b', 2, 2), 'bbbbbbbb', 'aaaaaaaa', 'a cozinha do restaurante B');

-- is_staff: responde certo para o restaurante e para o papel
do $$
begin
  perform pg_temp.entrar_como(pg_temp.id('a', 2, 1));   -- dono de A
  if not public.is_staff(pg_temp.id('a', 1, 1)) then
    raise exception 'is_staff devolveu falso para o dono de A no restaurante A';
  end if;
  if public.is_staff(pg_temp.id('b', 1, 1)) then
    raise exception 'VAZAMENTO: is_staff devolveu verdadeiro para o dono de A no restaurante B';
  end if;
  if not public.is_staff(pg_temp.id('a', 1, 1), array['owner']) then
    raise exception 'is_staff(A, owner) devolveu falso para o dono de A';
  end if;
  if public.is_staff(pg_temp.id('a', 1, 1), array['kitchen']) then
    raise exception 'is_staff(A, kitchen) devolveu verdadeiro para o dono de A, que não é da cozinha';
  end if;

  perform pg_temp.entrar_como(pg_temp.id('a', 2, 2));   -- cozinha de A
  if public.is_staff(pg_temp.id('a', 1, 1), array['owner', 'manager']) then
    raise exception 'is_staff(A, owner/manager) devolveu verdadeiro para a cozinha de A';
  end if;
  perform pg_temp.voltar_dono();
end $$;

-- ---------------------------------------------------------------------
-- c) Usuário logado sem staff não vê nada (nem o seed, nem A, nem B)
-- ---------------------------------------------------------------------
create procedure pg_temp.checar_vazio(p_usuario uuid, p_quem text)
language plpgsql as $$
declare
  t record;
  v_n bigint;
begin
  perform pg_temp.entrar_como(p_usuario);
  for t in select * from pg_temp.tabelas() loop
    v_n := pg_temp.contar(t.tabela);
    if v_n <> 0 then
      raise exception 'VAZAMENTO: % enxerga % linha(s) em public.% mas não pertence a nenhum restaurante', p_quem, v_n, t.tabela;
    end if;
  end loop;

  if public.is_staff(pg_temp.id('a', 1, 1)) or public.is_staff(pg_temp.id('b', 1, 1)) then
    raise exception 'VAZAMENTO: is_staff devolveu verdadeiro para %', p_quem;
  end if;

  v_n := pg_temp.atualizar($q$update public.orders set status = 'cancelled'$q$);
  if v_n <> 0 then
    raise exception 'VAZAMENTO: % alterou % pedido(s) sem ser staff', p_quem, v_n;
  end if;
  v_n := pg_temp.atualizar($q$update public.menu_items set available = false$q$);
  if v_n <> 0 then
    raise exception 'VAZAMENTO: % alterou % item(ns) do cardápio sem ser staff', p_quem, v_n;
  end if;
  v_n := pg_temp.atualizar($q$update public.modifier_options set available = false$q$);
  if v_n <> 0 then
    raise exception 'VAZAMENTO: % alterou % opção(ões) de adicional sem ser staff', p_quem, v_n;
  end if;
  perform pg_temp.voltar_dono();
end $$;

call pg_temp.checar_vazio('cccccccc-0002-0000-0000-000000000001', 'o usuário logado sem restaurante');
call pg_temp.checar_vazio(null, 'um JWT "authenticated" sem sub');

-- ---------------------------------------------------------------------
-- b) Escrita: staff de A não altera B (UPDATE só atinge o próprio restaurante)
-- ---------------------------------------------------------------------
create procedure pg_temp.checar_updates(p_usuario uuid, p_proprio text, p_outro text, p_quem text)
language plpgsql as $$
declare
  v_fora_antes text;
  v_fora_depois text;
  v_n bigint;
begin
  v_fora_antes := pg_temp.foto_fora(p_proprio);
  perform pg_temp.entrar_como(p_usuario);

  -- 1. Mirando direto nas linhas do outro restaurante: 0 linhas atingidas
  v_n := pg_temp.atualizar(format($q$update public.orders set status = 'ready' where id::text like %L$q$, p_outro || '-%'));
  if v_n <> 0 then
    raise exception 'VAZAMENTO: % alterou % pedido(s) do restaurante % (orders.status)', p_quem, v_n, upper(left(p_outro, 1));
  end if;
  v_n := pg_temp.atualizar(format($q$update public.menu_items set available = false where id::text like %L$q$, p_outro || '-%'));
  if v_n <> 0 then
    raise exception 'VAZAMENTO: % alterou % item(ns) do cardápio do restaurante % (menu_items.available)', p_quem, v_n, upper(left(p_outro, 1));
  end if;
  v_n := pg_temp.atualizar(format($q$update public.modifier_options set available = false where id::text like %L$q$, p_outro || '-%'));
  if v_n <> 0 then
    raise exception 'VAZAMENTO: % alterou % opção(ões) de adicional do restaurante % (modifier_options.available)', p_quem, v_n, upper(left(p_outro, 1));
  end if;

  -- 2. Sem filtro nenhum: só as linhas do próprio restaurante (prova positiva do UPDATE permitido)
  v_n := pg_temp.atualizar($q$update public.orders set status = 'cancelled'$q$);
  if v_n <> 2 then
    raise exception 'UPDATE sem filtro em orders por %: esperava atingir só os 2 pedidos do próprio restaurante e atingiu %', p_quem, v_n;
  end if;
  v_n := pg_temp.atualizar($q$update public.menu_items set available = false$q$);
  if v_n <> 2 then
    raise exception 'UPDATE sem filtro em menu_items por %: esperava atingir só os 2 itens do próprio restaurante e atingiu %', p_quem, v_n;
  end if;
  v_n := pg_temp.atualizar($q$update public.modifier_options set available = false$q$);
  if v_n <> 4 then
    raise exception 'UPDATE sem filtro em modifier_options por %: esperava atingir só as 4 opções do próprio restaurante e atingiu %', p_quem, v_n;
  end if;

  perform pg_temp.voltar_dono();

  -- 3. Conferência como dono do banco: nada fora do restaurante mudou (nenhuma coluna de nenhuma tabela)
  v_fora_depois := pg_temp.foto_fora(p_proprio);
  if v_fora_antes <> v_fora_depois then
    raise exception 'VAZAMENTO: linhas de outros restaurantes foram alteradas por %', p_quem;
  end if;
  -- ...e o próprio restaurante mudou de fato, senão o teste acima não provaria nada
  if (select count(*) from public.orders where id::text like p_proprio || '-%' and status = 'cancelled') <> 2
     or (select count(*) from public.menu_items where id::text like p_proprio || '-%' and not available) <> 2
     or (select count(*) from public.modifier_options where id::text like p_proprio || '-%' and not available) <> 4 then
    raise exception 'O UPDATE permitido de % no próprio restaurante não surtiu efeito', p_quem;
  end if;
end $$;

call pg_temp.checar_updates(pg_temp.id('a', 2, 1), 'aaaaaaaa', 'bbbbbbbb', 'o dono do restaurante A');
call pg_temp.checar_updates(pg_temp.id('b', 2, 2), 'bbbbbbbb', 'aaaaaaaa', 'a cozinha do restaurante B');

-- ---------------------------------------------------------------------
-- b) Escrita: colunas fora do grant, INSERT e DELETE dão erro de permissão
-- ---------------------------------------------------------------------
-- authenticated só pode UPDATE em orders(status), menu_items(available) e
-- modifier_options(available). Todo o resto é negado, inclusive em linhas do próprio restaurante.
create procedure pg_temp.checar_negados(p_usuario uuid, p_proprio text, p_outro text, p_quem text)
language plpgsql as $$
declare
  v_comando text;
  t record;
  v_letra text;
begin
  perform pg_temp.entrar_como(p_usuario);

  -- UPDATE de colunas fora do grant: mover linha para o outro restaurante, mexer em preço, subir de cargo...
  foreach v_comando in array array[
    format('update public.orders set restaurant_id = %L where id = %L', pg_temp.id(p_outro, 1, 1), pg_temp.id(p_proprio, 8, 1)),
    format('update public.orders set total_cents = 0 where id = %L', pg_temp.id(p_proprio, 8, 1)),
    format('update public.orders set table_id = null where id = %L', pg_temp.id(p_proprio, 8, 1)),
    format('update public.menu_items set restaurant_id = %L where id = %L', pg_temp.id(p_outro, 1, 1), pg_temp.id(p_proprio, 5, 1)),
    format('update public.menu_items set price_cents = 1 where id = %L', pg_temp.id(p_proprio, 5, 1)),
    format('update public.modifier_options set group_id = %L where id = %L', pg_temp.id(p_outro, 6, 1), pg_temp.id(p_proprio, 7, 1)),
    format('update public.modifier_options set price_cents = 0 where id = %L', pg_temp.id(p_proprio, 7, 2)),
    format('update public.restaurants set name = ''Nome trocado'' where id = %L', pg_temp.id(p_proprio, 1, 1)),
    format('update public.restaurants set order_seq = 1 where id = %L', pg_temp.id(p_proprio, 1, 1)),
    format('update public.staff set role = ''owner'' where user_id = %L', pg_temp.id(p_proprio, 2, 2)),
    format('update public.staff set restaurant_id = %L where user_id = %L', pg_temp.id(p_outro, 1, 1), p_usuario),
    format('update public.tables set qr_token = ''token-trocado'' where id = %L', pg_temp.id(p_proprio, 3, 1)),
    format('update public.tables set active = false where id = %L', pg_temp.id(p_proprio, 3, 1)),
    format('update public.menu_categories set name = ''Nome trocado'' where id = %L', pg_temp.id(p_proprio, 4, 1)),
    format('update public.modifier_groups set name = ''Nome trocado'' where id = %L', pg_temp.id(p_proprio, 6, 1)),
    format('update public.item_modifier_groups set position = 9 where item_id = %L', pg_temp.id(p_proprio, 5, 1)),
    format('update public.order_items set quantity = 2 where id = %L', pg_temp.id(p_proprio, 9, 1))
  ] loop
    perform pg_temp.exige_negado(v_comando, p_quem || ' alterou coluna que o grant não permite');
  end loop;

  -- INSERT e DELETE nas 10 tabelas, no próprio restaurante e no outro
  foreach v_letra in array array[p_proprio, p_outro] loop
    foreach v_comando in array array[
      format('insert into public.restaurants (slug, name) values (%L, ''Invasor'')', 'invasor-' || left(v_letra, 1)),
      -- auto-promoção: pôr um usuário qualquer como dono do restaurante
      format('insert into public.staff (user_id, restaurant_id, role) values (%L, %L, ''owner'')', 'cccccccc-0002-0000-0000-000000000001'::uuid, pg_temp.id(v_letra, 1, 1)),
      format('insert into public.tables (restaurant_id, label) values (%L, ''Mesa invasora'')', pg_temp.id(v_letra, 1, 1)),
      format('insert into public.menu_categories (restaurant_id, name) values (%L, ''Categoria invasora'')', pg_temp.id(v_letra, 1, 1)),
      format('insert into public.menu_items (restaurant_id, name, price_cents) values (%L, ''Item invasor'', 1)', pg_temp.id(v_letra, 1, 1)),
      format('insert into public.modifier_groups (restaurant_id, name) values (%L, ''Grupo invasor'')', pg_temp.id(v_letra, 1, 1)),
      format('insert into public.modifier_options (group_id, name) values (%L, ''Opção invasora'')', pg_temp.id(v_letra, 6, 1)),
      format('insert into public.item_modifier_groups (item_id, group_id) values (%L, %L)', pg_temp.id(v_letra, 5, 2), pg_temp.id(v_letra, 6, 1)),
      format('insert into public.orders (restaurant_id, number, payment_method) values (%L, 9999, ''counter'')', pg_temp.id(v_letra, 1, 1)),
      format('insert into public.order_items (order_id, name_snapshot, unit_price_cents, quantity) values (%L, ''Item invasor'', 1, 1)', pg_temp.id(v_letra, 8, 1))
    ] loop
      perform pg_temp.exige_negado(v_comando, p_quem || ' conseguiu inserir linha (restaurante ' || upper(left(v_letra, 1)) || ')');
    end loop;

    for t in select tabela from pg_temp.tabelas() loop
      perform pg_temp.exige_negado(
        format('delete from public.%I where %I::text like %L', t.tabela, pg_temp.chave(t.tabela), v_letra || '-%'),
        p_quem || ' conseguiu apagar linha de public.' || t.tabela || ' (restaurante ' || upper(left(v_letra, 1)) || ')');
    end loop;
  end loop;

  perform pg_temp.voltar_dono();
end $$;

call pg_temp.checar_negados(pg_temp.id('a', 2, 1), 'aaaaaaaa', 'bbbbbbbb', 'o dono do restaurante A');
call pg_temp.checar_negados(pg_temp.id('a', 2, 2), 'aaaaaaaa', 'bbbbbbbb', 'a cozinha do restaurante A');
call pg_temp.checar_negados(pg_temp.id('b', 2, 1), 'bbbbbbbb', 'aaaaaaaa', 'o dono do restaurante B');

rollback;
