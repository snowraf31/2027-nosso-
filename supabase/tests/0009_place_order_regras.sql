-- =====================================================================
-- Teste de regras · 0009 · place_order: o que a migration 0010 recriou tem de continuar valendo
--
-- A 0010 recriou place_order (idempotência por mesa). Fora isso a função tem de ser IDÊNTICA à da
-- 0001; este teste prende as regras de negócio que não são de isolamento, chamando a função como o
-- visitante anônimo (papel anon, só com o token da mesa), do jeito que a API faz:
--   1. preço vem do banco: price_cents / unit_price_cents mandados na linha do pedido são ignorados
--   2. gorjeta: no balcão ('counter') vira 0; online vale; negativa ou maior que o subtotal dá BAD_TIP
--   3. imposto: round(subtotal * tax_rate), em centavos inteiros (nem floor, nem ceil); total =
--      subtotal + imposto + gorjeta
--   4. adicionais: indisponível, de outro restaurante ou fora das regras do grupo são recusados
--   5. validações e mensagens: pagamento, pedido vazio, quantidade, item inexistente, item esgotado
--   6. número do pedido sequencial por restaurante (cada um com o seu contador)
--   7. pedido recusado não deixa rastro (nem o número do contador)
--
-- Autocontido: cria os próprios dados e termina em rollback. Falha com raise exception.
-- =====================================================================
begin;

\ir _comum/dados.psql

-- Chama place_order como anon e devolve o erro (ou 'OK'). Cada chamada roda num sub-bloco: se a função
-- gravou algo antes de falhar, o Postgres desfaz.
create function pg_temp.tenta_pedido(p_token text, p_itens jsonb, p_pagamento text default 'counter',
                                     p_gorjeta int default 0, p_chave text default null)
returns text language plpgsql as $$
declare
  v_res jsonb;
begin
  perform pg_temp.entrar_anon();
  begin
    v_res := public.place_order(p_token, p_itens, p_pagamento, p_gorjeta, p_chave);
  exception when others then
    perform pg_temp.voltar_dono();
    return sqlerrm;
  end;
  perform pg_temp.voltar_dono();
  return 'OK';
end $$;

-- Faz o pedido como anon e devolve o jsonb ({id, number, public_token}); erro dentro da função sobe.
create function pg_temp.pedido(p_token text, p_itens jsonb, p_pagamento text default 'counter',
                               p_gorjeta int default 0, p_chave text default null)
returns jsonb language plpgsql as $$
declare
  v_res jsonb;
begin
  perform pg_temp.entrar_anon();
  v_res := public.place_order(p_token, p_itens, p_pagamento, p_gorjeta, p_chave);
  perform pg_temp.voltar_dono();
  return v_res;
end $$;

-- Linha de pedido: item, quantidade e opções (e campos extras, para o teste de preço).
create function pg_temp.linha(p_item uuid, p_qtd int, p_opcoes uuid[] default '{}', p_extra jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object('menu_item_id', p_item, 'quantity', p_qtd, 'option_ids', to_jsonb(p_opcoes)) || p_extra
$$;

create function pg_temp.exige_erro(p_esperado text, p_obtido text, p_caso text) returns void
language plpgsql as $$
begin
  if p_obtido is distinct from p_esperado then
    raise exception 'place_order, caso "%": esperava o erro % e veio %', p_caso, p_esperado, p_obtido;
  end if;
end $$;

create function pg_temp.exige_valores(p_pedido jsonb, p_sub int, p_imposto int, p_gorjeta int, p_caso text)
returns void language plpgsql as $$
declare
  o public.orders%rowtype;
begin
  select * into o from public.orders where id = (p_pedido->>'id')::uuid;
  if o.subtotal_cents is distinct from p_sub or o.tax_cents is distinct from p_imposto
     or o.tip_cents is distinct from p_gorjeta or o.total_cents is distinct from p_sub + p_imposto + p_gorjeta then
    raise exception 'place_order, caso "%": esperava subtotal/imposto/gorjeta/total = %/%/%/% e veio %/%/%/%', p_caso,
      p_sub, p_imposto, p_gorjeta, p_sub + p_imposto + p_gorjeta,
      o.subtotal_cents, o.tax_cents, o.tip_cents, o.total_cents;
  end if;
end $$;

-- Os dados do restaurante A: Café A (500, grupo "Leite": escolher exatamente 1), Prato A (1500, grupo
-- "Extras": 0 a 2). Taxa de A: 8,75% (como dono, fora de qualquer papel restrito).
update public.restaurants set tax_rate = 0.0875 where id = pg_temp.id('a', 1, 1);

do $$
declare
  c_mesa_a constant text := 'token-mesa-a1';
  c_mesa_b constant text := 'token-mesa-b1';
  v_cafe  constant uuid := pg_temp.id('a', 5, 1);
  v_prato constant uuid := pg_temp.id('a', 5, 2);
  v_integral constant uuid := pg_temp.id('a', 7, 1);
  v_aveia    constant uuid := pg_temp.id('a', 7, 2);
  v_queijo   constant uuid := pg_temp.id('a', 7, 3);
  v_bacon    constant uuid := pg_temp.id('a', 7, 4);
  v_res jsonb;
  v_res2 jsonb;
  v_unit int;
  v_antes int;
begin
  -- 1. O preço vem do banco, nunca da linha do pedido -----------------------------------------
  v_res := pg_temp.pedido(c_mesa_a, jsonb_build_array(
             pg_temp.linha(v_prato, 1, '{}', '{"price_cents":1,"unit_price_cents":1,"price":1,"name":"Grátis"}')));
  select unit_price_cents into v_unit from public.order_items where order_id = (v_res->>'id')::uuid;
  if v_unit is distinct from 1500 then
    raise exception 'place_order aceitou preço vindo do pedido: unit_price_cents = % (devia ser 1500, o preço do banco)', v_unit;
  end if;
  perform pg_temp.exige_valores(v_res, 1500, 131, 0, 'preço ignorado do cliente');   -- 1500 * 0,0875 = 131,25
  if (select name_snapshot from public.order_items where order_id = (v_res->>'id')::uuid) <> 'Prato A' then
    raise exception 'place_order aceitou o nome do item vindo do pedido';
  end if;

  -- preço com adicionais: base + opções do banco (Café 500 + leite de aveia 75), com quantidade 2
  v_res := pg_temp.pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_cafe, 2, array[v_aveia])));
  select unit_price_cents into v_unit from public.order_items where order_id = (v_res->>'id')::uuid;
  if v_unit is distinct from 575 then
    raise exception 'place_order: preço unitário com adicional = % (devia ser 575)', v_unit;
  end if;
  perform pg_temp.exige_valores(v_res, 1150, 101, 0, 'quantidade 2 com adicional');   -- 1150 * 0,0875 = 100,625 -> 101

  -- 2. Gorjeta ---------------------------------------------------------------------------------
  -- no balcão a gorjeta é tratada lá: vira 0, mesmo que o celular mande 300
  v_res := pg_temp.pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)), 'counter', 300);
  perform pg_temp.exige_valores(v_res, 1500, 131, 0, 'gorjeta no balcão vira zero');
  -- online a gorjeta vale
  v_res := pg_temp.pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)), 'online', 300);
  perform pg_temp.exige_valores(v_res, 1500, 131, 300, 'gorjeta online');
  -- online: gorjeta igual ao subtotal ainda vale; acima dele, ou negativa, dá BAD_TIP
  v_res := pg_temp.pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)), 'online', 1500);
  perform pg_temp.exige_valores(v_res, 1500, 131, 1500, 'gorjeta igual ao subtotal');
  perform pg_temp.exige_erro('BAD_TIP', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)), 'online', 1501), 'gorjeta acima do subtotal');
  perform pg_temp.exige_erro('BAD_TIP', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)), 'online', -1), 'gorjeta negativa');

  -- 3. Imposto: round(subtotal * taxa), centavos inteiros --------------------------------------
  -- Prato 1500 + Bacon 200 = 1700; 1700 * 0,0875 = 148,75 -> 149 (floor daria 148)
  v_res := pg_temp.pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1, array[v_bacon])));
  perform pg_temp.exige_valores(v_res, 1700, 149, 0, 'imposto 148,75 arredonda para 149');
  -- Café 500 + aveia 75 = 575; 575 * 0,0875 = 50,3125 -> 50 (ceil daria 51)
  v_res := pg_temp.pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_cafe, 1, array[v_aveia])));
  perform pg_temp.exige_valores(v_res, 575, 50, 0, 'imposto 50,3125 arredonda para 50');
  -- duas linhas no mesmo pedido: 575 + (1500 + 100 + 200) = 2375; 2375 * 0,0875 = 207,8125 -> 208
  v_res := pg_temp.pedido(c_mesa_a, jsonb_build_array(
             pg_temp.linha(v_cafe, 1, array[v_aveia]),
             pg_temp.linha(v_prato, 1, array[v_queijo, v_bacon])));
  perform pg_temp.exige_valores(v_res, 2375, 208, 0, 'duas linhas com adicionais');
  -- o restaurante B usa a taxa dele (7%, o padrão): 1500 * 0,07 = 105
  v_res := pg_temp.pedido(c_mesa_b, jsonb_build_array(pg_temp.linha(pg_temp.id('b', 5, 2), 1)));
  perform pg_temp.exige_valores(v_res, 1500, 105, 0, 'taxa do restaurante B');

  -- 4. Adicionais ------------------------------------------------------------------------------
  -- opção desligada pelo restaurante: recusada
  update public.modifier_options set available = false where id = v_bacon;
  perform pg_temp.exige_erro('BAD_MODIFIER', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1, array[v_bacon]))), 'opção indisponível');
  perform pg_temp.exige_erro('OK', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1, array[v_queijo]))), 'opção disponível do mesmo grupo');
  update public.modifier_options set available = true where id = v_bacon;
  -- opção de OUTRO restaurante: recusada
  perform pg_temp.exige_erro('BAD_MODIFIER', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1, array[pg_temp.id('b', 7, 3)]))), 'opção de outro restaurante');
  -- opção de grupo que não pertence ao item (leite no prato): recusada
  perform pg_temp.exige_erro('BAD_MODIFIER', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1, array[v_aveia]))), 'opção de grupo que não é do item');
  -- regra do grupo: "Leite" pede exatamente 1 (nenhuma ou duas dão erro)
  perform pg_temp.exige_erro('MODIFIER_RULE:Leite A', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_cafe, 1))), 'grupo obrigatório sem escolha');
  perform pg_temp.exige_erro('MODIFIER_RULE:Leite A', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_cafe, 1, array[v_integral, v_aveia]))), 'grupo com escolha demais');
  -- opção repetida na lista conta uma vez só ("Extras" aceita até 2: queijo, bacon e queijo de novo = 2)
  perform pg_temp.exige_erro('OK', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1, array[v_queijo, v_bacon, v_queijo]))), 'opção repetida conta uma vez');

  -- 5. Validações e mensagens de erro ------------------------------------------------------------
  perform pg_temp.exige_erro('TABLE_NOT_FOUND', pg_temp.tenta_pedido('token-que-nao-existe', jsonb_build_array(pg_temp.linha(v_prato, 1))), 'mesa inexistente');
  perform pg_temp.exige_erro('TABLE_NOT_FOUND', pg_temp.tenta_pedido('token-mesa-a2-inativa', jsonb_build_array(pg_temp.linha(v_prato, 1))), 'mesa inativa');
  perform pg_temp.exige_erro('BAD_PAYMENT', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)), 'cheque'), 'forma de pagamento inválida');
  perform pg_temp.exige_erro('EMPTY_ORDER', pg_temp.tenta_pedido(c_mesa_a, '[]'::jsonb), 'pedido vazio');
  perform pg_temp.exige_erro('EMPTY_ORDER', pg_temp.tenta_pedido(c_mesa_a, '{}'::jsonb), 'itens que não são lista');
  perform pg_temp.exige_erro('TOO_MANY_ITEMS', pg_temp.tenta_pedido(c_mesa_a, (select jsonb_agg(pg_temp.linha(v_cafe, 1, array[v_integral])) from generate_series(1, 41))), 'mais de 40 linhas');
  perform pg_temp.exige_erro('BAD_QUANTITY', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 0))), 'quantidade zero');
  perform pg_temp.exige_erro('BAD_QUANTITY', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 21))), 'quantidade acima de 20');
  perform pg_temp.exige_erro('OK', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 20))), 'quantidade 20 vale');
  perform pg_temp.exige_erro('ITEM_NOT_FOUND', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(pg_temp.id('b', 5, 2), 1))), 'item de outro restaurante');
  update public.menu_items set available = false where id = v_prato;
  perform pg_temp.exige_erro('ITEM_SOLD_OUT:Prato A', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1))), 'item esgotado');
  update public.menu_items set available = true where id = v_prato;

  -- 6. Número sequencial por restaurante: o contador de A (102) e o de B (502) andam separados ---
  select order_seq into v_antes from public.restaurants where id = pg_temp.id('a', 1, 1);
  v_res  := pg_temp.pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)));
  v_res2 := pg_temp.pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)));
  if (v_res2->>'number')::int <> (v_res->>'number')::int + 1 or (v_res->>'number')::int <> v_antes + 1 then
    raise exception 'Numeração de A fora de ordem: contador estava em %, pedidos % e %', v_antes, v_res->>'number', v_res2->>'number';
  end if;
  select order_seq into v_antes from public.restaurants where id = pg_temp.id('b', 1, 1);
  v_res := pg_temp.pedido(c_mesa_b, jsonb_build_array(pg_temp.linha(pg_temp.id('b', 5, 2), 1)));
  if (v_res->>'number')::int <> v_antes + 1 then
    raise exception 'Numeração de B deveria seguir o contador de B (esperava %, veio %)', v_antes + 1, v_res->>'number';
  end if;

  -- 7. Pedido recusado não deixa rastro: nem pedido, nem número gasto --------------------------
  select order_seq into v_antes from public.restaurants where id = pg_temp.id('a', 1, 1);
  perform pg_temp.exige_erro('BAD_TIP', pg_temp.tenta_pedido(c_mesa_a, jsonb_build_array(pg_temp.linha(v_prato, 1)), 'online', 99999), 'recusa por gorjeta');
  if (select order_seq from public.restaurants where id = pg_temp.id('a', 1, 1)) <> v_antes then
    raise exception 'Pedido recusado (BAD_TIP) gastou um número do contador do restaurante';
  end if;
end $$;

rollback;
