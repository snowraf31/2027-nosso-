-- =====================================================================
-- Teste de isolamento · 0005 · Função security definer não pode ser enganada por tabela temporária
--
-- is_staff, get_guest_menu, get_guest_order e place_order são security definer: rodam com o poder
-- do dono do banco e ignoram a RLS. O Postgres procura tabela sem schema primeiro em pg_temp
-- (as tabelas temporárias da sessão) e só depois no search_path da função. Se o search_path da
-- função não tem pg_temp POR ÚLTIMO, quem consegue criar uma tabela temporária (qualquer usuário
-- logado ou visitante: o papel tem TEMP no banco) esconde public.staff, public.tables,
-- public.orders ou public.menu_items atrás de uma tabela forjada:
--   - is_staff passa a dizer "sim" para quem não é staff, e a RLS inteira abre;
--   - get_guest_menu / get_guest_order entregam dados sem o token real;
--   - place_order grava pedido em outro restaurante, ou com o preço que o atacante inventar.
--
--   1. guarda do catálogo: toda função security definer do public tem search_path terminando
--      em pg_temp (ou vazio). Função nova fora da lista legada derruba o CI.
--   2. comportamento: o atacante cria a tabela temporária forjada e chama a função.
--
-- LACUNA CONHECIDA, sem migration ainda: hoje as 5 funções têm search_path = public (place_order:
-- public, extensions), sem pg_temp no fim. Corrigir (migration à parte) com
--   alter function ... set search_path = public, pg_temp   (place_order: public, extensions, pg_temp)
-- Enquanto a migration não existe, o ataque funciona e este teste só AVISA (raise warning), função
-- por função. Depois da migration o mesmo teste passa a derrubar o CI sozinho se alguma função
-- voltar a ser enganada.
--
-- Este arquivo roda numa sessão própria e os casos de place_order vêm primeiro; entre um caso e
-- outro o teste usa DISCARD PLANS, para o plano guardado de um caso não esconder a tabela forjada
-- do seguinte (um atacante real chega numa sessão nova, sem plano guardado).
-- Autocontido: cria os próprios dados e termina em rollback. Falha com raise exception.
-- =====================================================================
begin;

\ir _comum/dados.psql

-- ---------------------------------------------------------------------
-- 1. Guarda do catálogo
-- ---------------------------------------------------------------------
do $$
declare
  v_novas text;
  v_legadas text;
  v_legado text[] := array['bootstrap_first_owner()', 'get_guest_menu(text, text)',
                           'get_guest_order(uuid, text)', 'is_staff(uuid, text[])',
                           'place_order(text, jsonb, text, integer, text)'];
begin
  with f as (
    select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as assinatura
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
       and not pg_temp.search_path_blindado(p.oid::regprocedure)
  )
  select string_agg(assinatura, ', ' order by assinatura) filter (where assinatura <> all (v_legado)),
         string_agg(assinatura, ', ' order by assinatura) filter (where assinatura = any (v_legado))
    into v_novas, v_legadas
    from f;

  if v_novas is not null then
    raise exception 'Função security definer sem pg_temp por último no search_path: %. Uma tabela temporária criada pelo chamador esconde a tabela do public e engana a função. Use: set search_path = public, pg_temp.', v_novas;
  end if;
  if v_legadas is not null then
    raise warning 'LACUNA CONHECIDA (ainda sem migration): security definer sem pg_temp por último no search_path: %. Corrigir com: alter function ... set search_path = public, pg_temp (place_order: public, extensions, pg_temp).', v_legadas;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. place_order: tabela "tables" forjada (visitante anônimo)
-- ---------------------------------------------------------------------
-- O atacante forja a mesa B1 (mesmo id, QR que ele escolheu). A função não pode
-- aceitar: o token da mesa tem de existir em public.tables.
do $$
declare
  v_erro text;
  v_vazou boolean := false;
begin
  perform pg_temp.entrar_anon();
  begin
    execute format('create temp table tables (%s)', pg_temp.colunas('tables'));
    insert into pg_temp.tables (id, restaurant_id, label, qr_token, active)
    values (pg_temp.id('b', 3, 1), pg_temp.id('b', 1, 1), 'Mesa forjada', 'token-forjado', true);   -- id real da mesa B1, QR inventado

    begin
      perform public.place_order('token-forjado',
                jsonb_build_array(jsonb_build_object('menu_item_id', pg_temp.id('b', 5, 2), 'quantity', 1)),
                'counter', 0, null);
      raise exception using errcode = 'P0777', message = 'desfazer o pedido de teste';
    exception
      when sqlstate 'P0777' then v_vazou := true;
      when others then v_erro := sqlerrm;
    end;
    drop table pg_temp.tables;
  exception when insufficient_privilege then
    v_erro := 'TABLE_NOT_FOUND';   -- sem permissão para criar tabela temporária: o ataque nem começa
  end;
  perform pg_temp.voltar_dono();

  if v_vazou then
    perform pg_temp.vazamento_de_funcao('public.place_order(text, jsonb, text, integer, text)'::regprocedure,
      'place_order aceitou o token de uma mesa que só existe numa tabela temporária forjada e gravou pedido no restaurante B.');
  elsif v_erro is distinct from 'TABLE_NOT_FOUND' then
    raise exception 'PREPARO DO TESTE: place_order com mesa forjada deveria dar TABLE_NOT_FOUND e deu: %', v_erro;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. place_order: tabela "menu_items" forjada com preço inventado (mesa de A, token real)
-- ---------------------------------------------------------------------
-- O preço nunca vem do celular. Uma tabela temporária menu_items com o mesmo id do "Prato A"
-- e preço de 1 centavo não pode mudar o valor do pedido (1500).
do $$
declare
  v_erro text;
  v_subtotal int;
  v_res jsonb;
  v_tentou boolean := false;
begin
  discard plans;   -- como numa sessão nova: sem plano de place_order guardado do caso anterior
  perform pg_temp.entrar_anon();
  begin
    execute format('create temp table menu_items (%s)', pg_temp.colunas('menu_items'));
    insert into pg_temp.menu_items (id, restaurant_id, category_id, name, price_cents, available)
    values (pg_temp.id('a', 5, 2), pg_temp.id('a', 1, 1), pg_temp.id('a', 4, 2), 'Prato A', 1, true);
    v_tentou := true;

    begin
      v_res := public.place_order('token-mesa-a1',
                 jsonb_build_array(jsonb_build_object('menu_item_id', pg_temp.id('a', 5, 2), 'quantity', 1)),
                 'counter', 0, null);
      v_subtotal := (public.get_guest_order((v_res->>'id')::uuid, v_res->>'public_token')->>'subtotal_cents')::int;
      raise exception using errcode = 'P0777', message = 'desfazer o pedido de teste';
    exception
      when sqlstate 'P0777' then null;
      when others then v_erro := sqlerrm;
    end;
    drop table pg_temp.menu_items;
  exception when insufficient_privilege then
    v_tentou := false;   -- sem permissão para criar tabela temporária: o ataque nem começa
  end;
  perform pg_temp.voltar_dono();

  if v_tentou then
    if v_erro is not null then
      raise exception 'PREPARO DO TESTE: place_order de item válido da mesa A1 falhou com a tabela forjada: %', v_erro;
    end if;
    if v_subtotal is distinct from 1500 then
      perform pg_temp.vazamento_de_funcao('public.place_order(text, jsonb, text, integer, text)'::regprocedure,
        format('place_order usou o preço de uma tabela temporária forjada (subtotal %s em vez de 1500): o visitante escolheu o preço do pedido.', v_subtotal));
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. get_guest_menu: tabela "tables" forjada (visitante anônimo, sem o token real)
-- ---------------------------------------------------------------------
do $$
declare
  v jsonb;
begin
  perform pg_temp.entrar_anon();
  begin
    execute format('create temp table tables (%s)', pg_temp.colunas('tables'));
    insert into pg_temp.tables (id, restaurant_id, label, qr_token, active)
    values (gen_random_uuid(), pg_temp.id('a', 1, 1), 'Mesa forjada', 'token-forjado', true);
    v := public.get_guest_menu('restaurante-a-teste', 'token-forjado');
    drop table pg_temp.tables;
  exception when insufficient_privilege then
    v := null;   -- sem permissão para criar tabela temporária: o ataque nem começa
  end;
  perform pg_temp.voltar_dono();

  if v is not null then
    perform pg_temp.vazamento_de_funcao('public.get_guest_menu(text, text)'::regprocedure,
      'get_guest_menu entregou o cardápio de A com um QR que só existe numa tabela temporária forjada (sem o token real da mesa).');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. get_guest_order: tabela "orders" forjada (visitante anônimo, sem o token real do pedido)
-- ---------------------------------------------------------------------
do $$
declare
  v jsonb;
begin
  perform pg_temp.entrar_anon();
  begin
    execute format('create temp table orders (%s)', pg_temp.colunas('orders'));
    insert into pg_temp.orders (id, restaurant_id, number, status, payment_method, public_token)
    values (pg_temp.id('a', 8, 1), pg_temp.id('a', 1, 1), 101, 'new', 'counter', 'token-forjado');
    v := public.get_guest_order(pg_temp.id('a', 8, 1), 'token-forjado');
    drop table pg_temp.orders;
  exception when insufficient_privilege then
    v := null;   -- sem permissão para criar tabela temporária: o ataque nem começa
  end;
  perform pg_temp.voltar_dono();

  if v is not null then
    perform pg_temp.vazamento_de_funcao('public.get_guest_order(uuid, text)'::regprocedure,
      'get_guest_order entregou os itens do pedido A1 com um token que só existe numa tabela temporária forjada (sem o token real do pedido).');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 6. is_staff: tabela "staff" forjada por um usuário logado que não é de restaurante nenhum
-- ---------------------------------------------------------------------
-- Toda política de RLS passa por is_staff. O usuário C cria uma tabela temporária staff dizendo
-- que ele é dono de A. Ele não pode passar a ver (nem alterar) nada de A.
do $$
declare
  v_pedidos bigint := 0;
  v_staff boolean := false;
  v_alterados bigint := 0;
begin
  perform pg_temp.entrar_como(pg_temp.id('c', 2, 1));
  begin
    execute format('create temp table staff (%s)', pg_temp.colunas('staff'));
    insert into pg_temp.staff (user_id, restaurant_id, role)
    values (pg_temp.id('c', 2, 1), pg_temp.id('a', 1, 1), 'owner');

    v_staff := public.is_staff(pg_temp.id('a', 1, 1));
    v_pedidos := pg_temp.contar('orders', 'aaaaaaaa');
    v_alterados := pg_temp.atualizar($q$update public.orders set status = 'cancelled'$q$);
    drop table pg_temp.staff;
  exception when insufficient_privilege then
    null;   -- sem permissão para criar tabela temporária: o ataque nem começa
  end;
  perform pg_temp.voltar_dono();

  if v_staff or v_pedidos > 0 or v_alterados > 0 then
    perform pg_temp.vazamento_de_funcao('public.is_staff(uuid, text[])'::regprocedure,
      format('um usuário sem restaurante criou uma tabela temporária staff e virou dono de A: is_staff = %s, viu %s pedido(s) de A e alterou %s.', v_staff, v_pedidos, v_alterados));
  end if;
end $$;

rollback;
