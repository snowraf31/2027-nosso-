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

\ir _comum/dados.psql

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
create procedure pg_temp.checar_vazio(p_usuario uuid, p_quem text, p_jwt_sem_chave_sub boolean default false)
language plpgsql as $$
declare
  t record;
  v_n bigint;
begin
  if p_jwt_sem_chave_sub then
    -- JWT "authenticated" que nem traz a chave "sub" (diferente de "sub": null)
    perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
    set local role authenticated;
  else
    perform pg_temp.entrar_como(p_usuario);
  end if;
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
call pg_temp.checar_vazio(null, 'um JWT "authenticated" com sub nulo');
call pg_temp.checar_vazio(null, 'um JWT "authenticated" sem a chave sub', true);

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

    -- DELETE: a regra é no nível do GRANT (authenticated não tem DELETE em tabela nenhuma). Por isso
    -- um DELETE aceito que atingiu 0 linhas só porque a RLS filtrou também derruba o teste, de propósito:
    -- um grant de DELETE já é um erro, mesmo com a RLS segurando.
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

-- ---------------------------------------------------------------------
-- b) TRUNCATE: ignora a RLS e esvaziaria a tabela de TODOS os restaurantes
-- ---------------------------------------------------------------------
-- O 0002 só revoga INSERT, UPDATE e DELETE de authenticated, então TRUNCATE (e REFERENCES e
-- TRIGGER) continua liberado nas 10 tabelas. Cada tentativa roda num sub-bloco que é desfeito
-- à força (P0777), para o teste não apagar nada de verdade. LACUNA CONHECIDA, sem migration ainda
-- (revoke truncate, references, trigger on all tables in schema public from authenticated):
-- no estado legado exato só avisa; com a migration aplicada, ou em qualquer outro estado, derruba o CI.
create procedure pg_temp.checar_truncate(p_usuario uuid, p_quem text)
language plpgsql as $$
declare
  t record;
  v_truncou text := '';
begin
  set local client_min_messages = warning;   -- sem o aviso "truncate cascades to table ..."
  perform pg_temp.entrar_como(p_usuario);
  for t in select tabela from pg_temp.tabelas() order by tabela loop
    begin
      execute format('truncate public.%I cascade', t.tabela);   -- cascade: as tabelas filhas seguram o truncate simples
      raise exception using errcode = 'P0777', message = 'desfazer o truncate de teste';
    exception
      when insufficient_privilege then null;                      -- barrado: é o esperado
      when sqlstate 'P0777' then v_truncou := v_truncou || t.tabela || ' ';   -- passou, e o bloco desfez
    end;
  end loop;
  perform pg_temp.voltar_dono();

  if v_truncou <> '' then
    if pg_temp.truncate_legado() then
      raise warning 'LACUNA CONHECIDA (ainda sem migration): % consegue dar TRUNCATE (que ignora a RLS e esvazia a tabela de todos os restaurantes) em: %. Corrigir com: revoke truncate, references, trigger on all tables in schema public from authenticated.', p_quem, btrim(v_truncou);
    else
      raise exception 'FALHA DE SEGURANÇA: % consegue dar TRUNCATE (ignora a RLS e esvazia a tabela de todos os restaurantes) em: %', p_quem, btrim(v_truncou);
    end if;
  end if;
  -- o truncate de teste foi desfeito: os dados continuam lá
  if (select count(*) from public.orders where id::text like 'aaaaaaaa-%') <> 2 then
    raise exception 'PREPARO DO TESTE: o TRUNCATE de teste não foi desfeito';
  end if;
end $$;

call pg_temp.checar_truncate(pg_temp.id('a', 2, 1), 'o dono do restaurante A');
call pg_temp.checar_truncate(pg_temp.id('a', 2, 2), 'a cozinha do restaurante A');

rollback;
