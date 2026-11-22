-- =====================================================================
-- Teste de isolamento · 0007 · Idempotência de place_order com duas chamadas AO MESMO TEMPO
--
-- Toque duplo ou nova tentativa com Wi-Fi ruim: duas chamadas de place_order com a mesma chave na
-- mesma mesa, uma em cima da outra. place_order tem um cadeado por (restaurante, chave)
-- (pg_advisory_xact_lock): a segunda ESPERA a primeira terminar e devolve o MESMO pedido. Sem o
-- cadeado, a segunda não enxerga o pedido ainda não gravado, tenta criar o dela e leva um erro de
-- chave única (23505) em vez do pedido.
--
-- Isso não cabe numa transação só (o pedido da primeira chamada tem de estar gravado e ainda não
-- confirmado enquanto a segunda corre), então este arquivo usa duas conexões, via dblink:
--   conexão 1 (dblink): place_order(chave) + pg_sleep(3), tudo na mesma transação; só confirma no fim
--   conexão 2 (esta):   espera a conexão 1 estar dormindo (pedido já inserido, ainda sem commit) e
--                       chama place_order com a mesma chave na mesma mesa
-- Esperado: a segunda devolve o pedido da primeira, e só existe um pedido com a chave.
--
-- Diferente dos outros testes, este grava de verdade (as duas conexões precisam enxergar os dados):
-- usa a mesa demo-table-1 e o item "Guava Pastelito" do seed.sql e APAGA o que criou no fim (também
-- quando falha). Cria o schema zz_corrida só para a extensão dblink e o apaga no fim. Precisa de
-- superusuário (create extension) e do pacote contrib do Postgres, como no CI e no banco local.
-- Falha com raise exception.
-- =====================================================================
create schema zz_corrida;
create extension dblink schema zz_corrida;

do $$
declare
  c_chave   constant text := 'chave-corrida-0007';
  c_mesa    constant text := 'demo-table-1';
  v_rest    uuid;
  v_seq     int;
  v_item    uuid;
  v_itens   jsonb;
  v_conn    text;
  v_res1    jsonb;
  v_res2    jsonb;
  v_estado  text;
  v_erro    text;
  v_n       bigint;
  v_t0      timestamptz;
  v_espera  numeric;
  v_dormindo boolean := false;
  v_falha   text;
begin
  select r.id, r.order_seq into v_rest, v_seq from public.restaurants r where r.slug = 'harbor-pine';
  select m.id into v_item from public.menu_items m
   where m.restaurant_id = v_rest and m.name = 'Guava Pastelito' and m.available;
  if v_rest is null or v_item is null then
    raise exception 'PREPARO DO TESTE: o seed.sql (restaurante harbor-pine, item Guava Pastelito) não está no banco';
  end if;
  v_itens := jsonb_build_array(jsonb_build_object('menu_item_id', v_item, 'quantity', 1));

  begin
    -- conexão 1: pelo socket local; se não der, por TCP em localhost
    v_conn := format('dbname=%s port=%s user=%s', current_database(), current_setting('port'), current_user);
    begin
      perform zz_corrida.dblink_connect('c1', v_conn);
    exception when others then
      perform zz_corrida.dblink_connect('c1', v_conn || ' host=localhost');
    end;

    if zz_corrida.dblink_send_query('c1', format(
         'select public.place_order(%L, %L::jsonb, ''counter'', 0, %L); select pg_sleep(3);',
         c_mesa, v_itens::text, c_chave)) <> 1 then
      raise exception 'PREPARO DO TESTE: o dblink não enviou a consulta da conexão 1';
    end if;

    -- espera a conexão 1 chegar no pg_sleep: nesse ponto o pedido dela está inserido e sem commit
    for i in 1..200 loop
      select exists (select 1 from pg_stat_activity
                      where datname = current_database() and pid <> pg_backend_pid()
                        and wait_event = 'PgSleep') into v_dormindo;
      exit when v_dormindo;
      perform pg_sleep(0.05);
    end loop;
    if not v_dormindo then
      raise exception 'PREPARO DO TESTE: a conexão 1 não chegou ao pg_sleep em 10 segundos';
    end if;

    -- conexão 2 (esta): mesma mesa, mesma chave, com o pedido da conexão 1 ainda sem commit
    v_t0 := clock_timestamp();
    begin
      v_res2 := public.place_order(c_mesa, v_itens, 'counter', 0, c_chave);
    exception when others then
      v_estado := sqlstate;
      v_erro := sqlerrm;
    end;
    v_espera := extract(epoch from clock_timestamp() - v_t0);

    -- resultado da conexão 1 (o primeiro resultado é o do place_order; o seguinte, o do pg_sleep)
    select r into v_res1 from zz_corrida.dblink_get_result('c1') as t(r jsonb);
    perform * from zz_corrida.dblink_get_result('c1') as t(x text);
    perform * from zz_corrida.dblink_get_result('c1') as t(x text);

    select count(*) into v_n from public.orders where restaurant_id = v_rest and idempotency_key = c_chave;

    if v_res1 is null or v_res1->>'id' is null then
      raise exception 'PREPARO DO TESTE: a conexão 1 não devolveu pedido: %', v_res1;
    end if;
    if v_erro is not null then
      raise exception 'CORRIDA: a segunda chamada com a mesma chave e a mesma mesa deveria esperar e devolver o pedido da primeira, e deu erro (%): %. O cadeado pg_advisory_xact_lock de place_order sumiu?', v_estado, v_erro;
    end if;
    if v_espera < 0.5 then
      raise exception 'CORRIDA: a segunda chamada não esperou a primeira (levou % s com a primeira ainda sem commit): sem o cadeado de place_order ela nem enxergaria o pedido.', round(v_espera, 2);
    end if;
    if v_res2->>'id' is distinct from v_res1->>'id' or v_res2->>'public_token' is distinct from v_res1->>'public_token'
       or v_res2->>'number' is distinct from v_res1->>'number' then
      raise exception 'CORRIDA: a segunda chamada devolveu outro pedido: % e %', v_res1, v_res2;
    end if;
    if v_n <> 1 then
      raise exception 'CORRIDA: esperado 1 pedido com a chave e há %', v_n;
    end if;
  exception when others then
    v_falha := sqlerrm;
  end;

  -- limpeza (sempre): fecha a conexão 1, apaga o pedido gravado e devolve a numeração do restaurante
  begin perform zz_corrida.dblink_disconnect('c1'); exception when others then null; end;
  delete from public.orders where restaurant_id = v_rest and idempotency_key = c_chave;
  update public.restaurants set order_seq = v_seq where id = v_rest;

  if v_falha is not null then
    raise exception '%', v_falha;
  end if;
end $$;

drop extension dblink;
drop schema zz_corrida;
