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

\ir _comum/dados.psql

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
  if v->'restaurant'->>'slug' is distinct from 'restaurante-a-teste' or v->'table'->>'label' is distinct from 'Mesa A1' then
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
  -- slug de um terceiro restaurante (C: existe, mas não tem mesa) com token de mesa de A
  if public.get_guest_menu('restaurante-c-teste', 'token-mesa-a1') is not null then
    raise exception 'VAZAMENTO: get_guest_menu com slug de C e token da mesa de A devolveu cardápio';
  end if;
  if public.get_guest_menu('restaurante-c-teste', 'token-mesa-b1') is not null then
    raise exception 'VAZAMENTO: get_guest_menu com slug de C e token da mesa de B devolveu cardápio';
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
  if v->>'restaurant_name' is distinct from 'Restaurante A (teste de isolamento)' or v->>'table_label' is distinct from 'Mesa A1'
     or jsonb_array_length(v->'items') <> 1 then
    raise exception 'get_guest_order(pedido A1) devolveu dados errados: %', v;
  end if;
  if pg_temp.ids_de_fora(v, 'aaaaaaaa') <> 0 then
    raise exception 'VAZAMENTO: get_guest_order(pedido A1) devolveu ids que não são do restaurante A: %', v;
  end if;

  -- O espelho em B
  v := public.get_guest_order(pg_temp.id('b', 8, 2), 'token-pedido-b2');
  if v is null or v->>'restaurant_name' is distinct from 'Restaurante B (teste de isolamento)'
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
  -- também com item de B que não exige adicional (assim nenhuma outra regra mascara o vazamento)
  v_erro := pg_temp.erro_do_pedido('token-mesa-a1', jsonb_build_array(pg_temp.linha(pg_temp.id('b', 5, 2), 1)));
  if v_erro is distinct from 'ITEM_NOT_FOUND' then
    raise exception 'place_order com mesa de A e item simples de B deveria dar ITEM_NOT_FOUND e deu: %', coalesce(v_erro, 'sucesso (VAZAMENTO: pedido criado)');
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
  if v_pedido.number is distinct from 103 or (v_res->>'number')::int is distinct from 103 then
    raise exception 'o primeiro pedido novo de A deveria ser o número 103 (sequência de A em 102) e foi %', v_pedido.number;
  end if;
  if v_pedido.subtotal_cents is distinct from 1150 or v_pedido.total_cents is distinct from v_pedido.subtotal_cents + v_pedido.tax_cents then
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
  if v_guest is null or v_guest->>'restaurant_name' is distinct from 'Restaurante A (teste de isolamento)'
     or v_guest->>'table_label' is distinct from 'Mesa A1' or (v_guest->>'number')::int is distinct from 103
     or (v_guest->>'subtotal_cents')::int is distinct from 1150 or v_guest::text like '%bbbbbbbb-%' then
    raise exception 'get_guest_order do pedido novo de A devolveu null ou dados de outro restaurante: %', v_guest;
  end if;

  -- Sequências independentes: B anda a sua, A não se mexe; um segundo pedido em A vira 104
  v_fora_de_b := pg_temp.foto_fora('bbbbbbbb');   -- tudo que não é de B (inclui o pedido novo de A)
  perform pg_temp.entrar_anon();
  v_res := public.place_order('token-mesa-b1',
             jsonb_build_array(pg_temp.linha(pg_temp.id('b', 5, 2), 1)), 'counter', 0, null);
  perform pg_temp.voltar_dono();
  select * into v_pedido from public.orders where id = (v_res->>'id')::uuid;
  if v_pedido.restaurant_id is distinct from pg_temp.id('b', 1, 1) or v_pedido.number is distinct from 503 then
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

-- ---------------------------------------------------------------------
-- e4) Idempotência de place_order: a chave só vale dentro da MESMA MESA
-- ---------------------------------------------------------------------
-- Até a migration 0010 a chave era única no banco inteiro e place_order a procurava antes de
-- validar a mesa: reenviar a chave de um pedido de B por uma mesa de A devolvia o id e o
-- public_token do pedido de B. Agora a chave é única por restaurante (orders_restaurant_id_
-- idempotency_key_key) e só é procurada dentro da mesma mesa, depois de validar a mesa:
--   i)   mesa de A com a chave de um pedido de B: pedido NOVO de A, nunca o de B (e o inverso)
--   ii)  outra mesa do MESMO restaurante com a chave: nunca devolve o pedido da primeira mesa
--        (hoje o banco recusa com unique_violation, 23505, e nada é gravado)
--   iii) mesma chave na mesma mesa: devolve o mesmo pedido (a idempotência continua valendo)
--   iv)  mesma chave em restaurantes diferentes: dois pedidos distintos, um em cada restaurante
-- A corrida (duas chamadas ao mesmo tempo com a mesma chave) não cabe numa transação só e
-- fica coberta pelo cadeado da função (pg_advisory_xact_lock); ver comentário na migration 0010.

-- Chama place_order (1 item, balcão) e devolve o resultado, o SQLSTATE e a mensagem de erro.
-- Em caso de erro o bloco desfaz tudo o que a função fez até ali.
create function pg_temp.pedir(p_token text, p_item uuid, p_chave text,
                              out res jsonb, out estado text, out erro text)
language plpgsql as $$
begin
  res := public.place_order(p_token, jsonb_build_array(pg_temp.linha(p_item, 1)), 'counter', 0, p_chave);
exception when others then
  res := null;
  estado := sqlstate;
  erro := sqlerrm;
end $$;

do $$
declare
  r record;
  r2 record;
  v_ped public.orders%rowtype;
  v_fora_de_a text;
  v_fora_de_b text;
  v_seq_a int;
  v_seq_b int;
  v_n bigint;
  v_id_novo_a uuid;
  v_id_novo_b uuid;
begin
  -- Estrutura: a chave única global sumiu; no lugar dela, única por (restaurante, chave)
  if exists (select 1 from pg_constraint c
              where c.conrelid = 'public.orders'::regclass and c.contype = 'u'
                and (select array_agg(a.attname::text order by a.attname) from pg_attribute a
                      where a.attrelid = c.conrelid and a.attnum = any (c.conkey)) = array['idempotency_key']) then
    raise exception 'orders ainda tem chave única só em idempotency_key (global): a chave de um restaurante bloqueia a de outro e place_order a procuraria no banco inteiro';
  end if;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.orders'::regclass and c.contype = 'u'
                    and (select array_agg(a.attname::text order by a.attname) from pg_attribute a
                          where a.attrelid = c.conrelid and a.attnum = any (c.conkey)) = array['idempotency_key', 'restaurant_id']) then
    raise exception 'orders deveria ter chave única em (restaurant_id, idempotency_key) e não tem';
  end if;

  -- Uma segunda mesa ATIVA de A (as de teste têm só a A1 ativa), para o caso "outra mesa do mesmo restaurante"
  insert into public.tables (id, restaurant_id, label, qr_token, active)
  values (pg_temp.id('a', 3, 3), pg_temp.id('a', 1, 1), 'Mesa A3', 'token-mesa-a3', true);

  -- ---- iii) mesma chave na mesma mesa: o mesmo pedido, nada novo ----------------------------
  select order_seq into v_seq_a from public.restaurants where id = pg_temp.id('a', 1, 1);
  select count(*) into v_n from public.orders where restaurant_id = pg_temp.id('a', 1, 1);
  v_fora_de_a := pg_temp.foto_fora('aaaaaaaa');
  perform pg_temp.entrar_anon();
  select * into r from pg_temp.pedir('token-mesa-a1', pg_temp.id('a', 5, 2), 'chave-a-1');
  perform pg_temp.voltar_dono();
  if r.erro is not null then
    raise exception 'iii) reenviar a chave do pedido A1 pela mesa A1 deu erro (%): %', r.estado, r.erro;
  end if;
  if (r.res->>'id')::uuid is distinct from pg_temp.id('a', 8, 1) or r.res->>'public_token' is distinct from 'token-pedido-a1'
     or (r.res->>'number')::int is distinct from 101 then
    raise exception 'iii) a mesma chave na mesma mesa deveria devolver o pedido original (A1, número 101) e devolveu %', r.res;
  end if;
  if (select order_seq from public.restaurants where id = pg_temp.id('a', 1, 1)) <> v_seq_a
     or (select count(*) from public.orders where restaurant_id = pg_temp.id('a', 1, 1)) <> v_n then
    raise exception 'iii) o reenvio da chave não pode criar pedido nem gastar número da sequência de A';
  end if;
  if pg_temp.foto_fora('aaaaaaaa') <> v_fora_de_a then
    raise exception 'iii) o reenvio da chave de A mexeu em linhas de outros restaurantes';
  end if;

  -- chave nova: o primeiro envio cria; o segundo devolve o mesmo e a sequência anda uma vez só
  perform pg_temp.entrar_anon();
  select * into r  from pg_temp.pedir('token-mesa-a1', pg_temp.id('a', 5, 2), 'chave-nova-a');
  select * into r2 from pg_temp.pedir('token-mesa-a1', pg_temp.id('a', 5, 2), 'chave-nova-a');
  perform pg_temp.voltar_dono();
  if r.erro is not null or r2.erro is not null then
    raise exception 'iii) dois envios com a chave nova da mesa A1 deram erro: % / %', r.erro, r2.erro;
  end if;
  if r.res->>'id' is distinct from r2.res->>'id' or r.res->>'public_token' is distinct from r2.res->>'public_token'
     or r.res->>'number' is distinct from r2.res->>'number' then
    raise exception 'iii) a mesma chave na mesma mesa gerou dois pedidos diferentes: % e %', r.res, r2.res;
  end if;
  select count(*) into v_n from public.orders
   where restaurant_id = pg_temp.id('a', 1, 1) and idempotency_key = 'chave-nova-a';
  if v_n <> 1 or (select order_seq from public.restaurants where id = pg_temp.id('a', 1, 1)) <> v_seq_a + 1 then
    raise exception 'iii) esperado 1 pedido com a chave nova e a sequência de A avançada 1 vez; há % pedido(s)', v_n;
  end if;
  select * into v_ped from public.orders where id = (r.res->>'id')::uuid;
  if v_ped.restaurant_id is distinct from pg_temp.id('a', 1, 1) or v_ped.table_id is distinct from pg_temp.id('a', 3, 1) then
    raise exception 'iii) o pedido da chave nova deveria ser da mesa A1 do restaurante A';
  end if;

  -- ---- i) mesa de A com a chave de um pedido de B: nunca devolve o de B ---------------------
  v_fora_de_a := pg_temp.foto_fora('aaaaaaaa');   -- tudo que não é de A: B tem de ficar intacto
  perform pg_temp.entrar_anon();
  select * into r  from pg_temp.pedir('token-mesa-a1', pg_temp.id('a', 5, 2), 'chave-b-1');
  select * into r2 from pg_temp.pedir('token-mesa-a1', pg_temp.id('a', 5, 2), 'chave-b-1');
  perform pg_temp.voltar_dono();
  if r.erro is null then
    if (r.res->>'id')::uuid = pg_temp.id('b', 8, 1) or r.res->>'public_token' = 'token-pedido-b1'
       or r.res->>'number' = '501' then
      raise exception 'VAZAMENTO: a mesa de A reenviou a chave do pedido de B e recebeu o pedido de B: %', r.res;
    end if;
    select * into v_ped from public.orders where id = (r.res->>'id')::uuid;
    if v_ped.restaurant_id is distinct from pg_temp.id('a', 1, 1) or v_ped.table_id is distinct from pg_temp.id('a', 3, 1) then
      raise exception 'i) a mesa A1 com a chave de B deveria criar um pedido NOVO de A na mesa A1 e criou %', row(v_ped.restaurant_id, v_ped.table_id);
    end if;
    -- a nova tentativa (mesma chave, mesma mesa A1) devolve esse mesmo pedido novo de A
    if r2.res->>'id' is distinct from r.res->>'id' then
      raise exception 'i) reenviar a chave de B pela mesa A1 duas vezes deveria devolver o mesmo pedido de A: % e %', r.res, r2.res;
    end if;
  else
    -- restaurantes diferentes podem repetir a chave: recusar aqui seria um defeito novo
    raise exception 'i) a mesa A1 com a chave de B deveria criar um pedido novo de A (restaurantes diferentes podem repetir a chave) e deu erro (%): %', r.estado, r.erro;
  end if;
  v_id_novo_a := (r.res->>'id')::uuid;
  -- o pedido de B continua como estava, com a chave dele, e nada de B mudou
  select * into v_ped from public.orders where id = pg_temp.id('b', 8, 1);
  if v_ped.idempotency_key is distinct from 'chave-b-1' or v_ped.restaurant_id is distinct from pg_temp.id('b', 1, 1)
     or v_ped.table_id is distinct from pg_temp.id('b', 3, 1) or v_ped.public_token is distinct from 'token-pedido-b1' then
    raise exception 'VAZAMENTO: o pedido B1 mudou depois que uma mesa de A reenviou a chave dele';
  end if;
  if pg_temp.foto_fora('aaaaaaaa') <> v_fora_de_a then
    raise exception 'VAZAMENTO: reenviar a chave de B por uma mesa de A alterou linhas fora de A (B ou seed)';
  end if;

  -- o espelho: mesa de B com a chave de um pedido de A
  v_fora_de_b := pg_temp.foto_fora('bbbbbbbb');
  perform pg_temp.entrar_anon();
  select * into r from pg_temp.pedir('token-mesa-b1', pg_temp.id('b', 5, 2), 'chave-a-1');
  perform pg_temp.voltar_dono();
  if r.erro is not null then
    raise exception 'i) a mesa B1 com a chave de A deveria criar um pedido novo de B e deu erro (%): %', r.estado, r.erro;
  end if;
  if (r.res->>'id')::uuid = pg_temp.id('a', 8, 1) or r.res->>'public_token' = 'token-pedido-a1' or r.res->>'number' = '101' then
    raise exception 'VAZAMENTO: a mesa de B reenviou a chave do pedido de A e recebeu o pedido de A: %', r.res;
  end if;
  select * into v_ped from public.orders where id = (r.res->>'id')::uuid;
  if v_ped.restaurant_id is distinct from pg_temp.id('b', 1, 1) or v_ped.table_id is distinct from pg_temp.id('b', 3, 1) then
    raise exception 'i) a mesa B1 com a chave de A deveria criar um pedido NOVO de B na mesa B1';
  end if;
  v_id_novo_b := (r.res->>'id')::uuid;
  if pg_temp.foto_fora('bbbbbbbb') <> v_fora_de_b then
    -- o pedido novo de B está dentro de B; só A e o seed contam como "fora de B", e nada disso pode mudar
    raise exception 'VAZAMENTO: reenviar a chave de A por uma mesa de B alterou linhas fora de B (A ou seed)';
  end if;

  -- ---- ii) outra mesa do MESMO restaurante: nunca recupera o pedido da primeira mesa ---------
  select order_seq into v_seq_a from public.restaurants where id = pg_temp.id('a', 1, 1);
  select count(*) into v_n from public.orders where restaurant_id = pg_temp.id('a', 1, 1);
  perform pg_temp.entrar_anon();
  select * into r  from pg_temp.pedir('token-mesa-a3', pg_temp.id('a', 5, 2), 'chave-a-1');       -- chave do pedido A1 da mesa A1
  select * into r2 from pg_temp.pedir('token-mesa-a3', pg_temp.id('a', 5, 2), 'chave-nova-a');    -- chave do pedido novo da mesa A1
  perform pg_temp.voltar_dono();
  if r.res is not null and ((r.res->>'id')::uuid = pg_temp.id('a', 8, 1) or r.res->>'public_token' = 'token-pedido-a1')
     or r2.res is not null and (r2.res->>'id' in (select id::text from public.orders where idempotency_key = 'chave-nova-a' and table_id = pg_temp.id('a', 3, 1))) then
    raise exception 'VAZAMENTO: outra mesa do restaurante A reenviou a chave de um pedido da mesa A1 e recebeu o pedido dela: % / %', r.res, r2.res;
  end if;
  if r.erro is null or r2.erro is null then
    raise exception 'ii) a mesa A3 com chave já usada pela mesa A1 deveria ser recusada (chave única por restaurante); resultado: % / %', r.res, r2.res;
  end if;
  if r.estado <> '23505' or r2.estado <> '23505' then
    raise exception 'ii) a recusa deveria ser unique_violation (23505) e foi % / %: % / %', r.estado, r2.estado, r.erro, r2.erro;
  end if;
  if (select order_seq from public.restaurants where id = pg_temp.id('a', 1, 1)) <> v_seq_a
     or (select count(*) from public.orders where restaurant_id = pg_temp.id('a', 1, 1)) <> v_n
     or exists (select 1 from public.orders where table_id = pg_temp.id('a', 3, 3)) then
    raise exception 'ii) a recusa não pode gravar pedido nem gastar número da sequência de A';
  end if;

  -- A mesa inválida ou inativa é validada ANTES da chave: nunca devolve pedido de ninguém
  perform pg_temp.entrar_anon();
  select * into r  from pg_temp.pedir('token-que-nao-existe', pg_temp.id('a', 5, 2), 'chave-b-1');
  select * into r2 from pg_temp.pedir('token-mesa-a2-inativa', pg_temp.id('a', 5, 2), 'chave-a-1');
  perform pg_temp.voltar_dono();
  if r.res is not null or r2.res is not null or r.erro is distinct from 'TABLE_NOT_FOUND' or r2.erro is distinct from 'TABLE_NOT_FOUND' then
    raise exception 'VAZAMENTO: place_order com mesa inexistente ou inativa deveria dar TABLE_NOT_FOUND antes de olhar a chave e deu: % (%) / % (%)',
                    r.res, r.erro, r2.res, r2.erro;
  end if;

  -- ---- iv) mesma chave em restaurantes diferentes: dois pedidos distintos --------------------
  perform pg_temp.entrar_anon();
  select * into r  from pg_temp.pedir('token-mesa-a1', pg_temp.id('a', 5, 2), 'chave-compartilhada');
  select * into r2 from pg_temp.pedir('token-mesa-b1', pg_temp.id('b', 5, 2), 'chave-compartilhada');
  perform pg_temp.voltar_dono();
  if r.erro is not null or r2.erro is not null then
    raise exception 'iv) a mesma chave em A e em B deveria funcionar nos dois restaurantes e deu erro: % / %', r.erro, r2.erro;
  end if;
  if r.res->>'id' = r2.res->>'id' or r.res->>'public_token' = r2.res->>'public_token' then
    raise exception 'VAZAMENTO: a mesma chave em A e em B devolveu o mesmo pedido: % e %', r.res, r2.res;
  end if;
  if (select restaurant_id from public.orders where id = (r.res->>'id')::uuid) is distinct from pg_temp.id('a', 1, 1)
     or (select restaurant_id from public.orders where id = (r2.res->>'id')::uuid) is distinct from pg_temp.id('b', 1, 1) then
    raise exception 'iv) cada pedido deveria ficar no restaurante da sua mesa (A e B)';
  end if;
  select count(*) into v_n from public.orders where idempotency_key = 'chave-compartilhada';
  if v_n <> 2 then
    raise exception 'iv) esperado 2 pedidos com a chave compartilhada (um por restaurante) e há %', v_n;
  end if;
  -- e o reenvio em cada restaurante devolve o pedido do PRÓPRIO restaurante
  perform pg_temp.entrar_anon();
  select * into r from pg_temp.pedir('token-mesa-a1', pg_temp.id('a', 5, 2), 'chave-compartilhada') ;
  select * into r2 from pg_temp.pedir('token-mesa-b1', pg_temp.id('b', 5, 2), 'chave-compartilhada');
  perform pg_temp.voltar_dono();
  if (select restaurant_id from public.orders where id = (r.res->>'id')::uuid) is distinct from pg_temp.id('a', 1, 1)
     or (select restaurant_id from public.orders where id = (r2.res->>'id')::uuid) is distinct from pg_temp.id('b', 1, 1)
     or (select count(*) from public.orders where idempotency_key = 'chave-compartilhada') <> 2 then
    raise exception 'iv) o reenvio da chave compartilhada deveria devolver o pedido do próprio restaurante, sem criar outro';
  end if;

  -- Sanidade do banco: a chave única por restaurante também vale para quem escreve direto
  begin
    insert into public.orders (restaurant_id, table_id, number, payment_method, idempotency_key)
    values (pg_temp.id('a', 1, 1), pg_temp.id('a', 3, 1), 9001, 'counter', 'chave-a-1');
    raise exception 'o banco aceitou duas chaves iguais no mesmo restaurante (orders_restaurant_id_idempotency_key_key)';
  exception when unique_violation then null;
  end;
end $$;

rollback;
