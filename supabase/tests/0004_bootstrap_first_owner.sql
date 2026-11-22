-- =====================================================================
-- Teste de isolamento · 0004 · Quem se cadastra depois não ganha acesso a restaurante nenhum
--
-- O gatilho bootstrap_first_owner (0006) só promove a dono o PRIMEIRO usuário criado,
-- e só numa instalação com exatamente 1 restaurante e staff vazio. Se alguém afrouxar
-- essa regra, qualquer estranho que se cadastrar vira dono. Casos:
--
--   1. nenhum restaurante: o usuário criado não vira staff
--   2. 2 ou mais restaurantes e staff vazio: o usuário criado não vira staff
--   3. 1 restaurante e staff vazio: o primeiro usuário vira owner DESSE restaurante,
--      o segundo não vira nada
--   4. 1 restaurante e staff já preenchido (à mão): o usuário novo não vira nada
--
-- Autocontido: esvazia as tabelas dentro da transação (o rollback devolve tudo) e
-- monta o cenário de cada caso. Falha com raise exception.
-- =====================================================================
begin;

-- Começa do zero: sem restaurantes (a cascata leva staff, mesas, cardápio e pedidos) e sem usuários.
-- (o aviso de cascata é só ruído, por isso o client_min_messages)
set local client_min_messages = warning;
truncate public.restaurants cascade;
delete from auth.users;

create function pg_temp.vinculos(p_usuario uuid) returns int
language sql as $$ select count(*)::int from public.staff where user_id = p_usuario $$;

-- 1. nenhum restaurante --------------------------------------------------
do $$
begin
  begin
    insert into auth.users (id, email) values
      ('dddddddd-0002-0000-0000-000000000001', 'sem-restaurante-nenhum@exemplo.test');
  exception when others then
    -- sem a guarda "exatamente 1 restaurante" o gatilho tentaria vincular o usuário a restaurante nenhum
    raise exception 'GATILHO: com 0 restaurantes, criar usuário falhou (%): o bootstrap_first_owner perdeu a guarda de "exatamente 1 restaurante"', sqlerrm;
  end;
  if (select count(*) from public.staff) <> 0 then
    raise exception 'GATILHO: com 0 restaurantes, criar usuário gerou vínculo de staff (%)', (select count(*) from public.staff);
  end if;
end $$;

-- 2. dois restaurantes, staff vazio --------------------------------------
insert into public.restaurants (id, slug, name) values
  ('dddddddd-0001-0000-0000-000000000001', 'bootstrap-um', 'Bootstrap Um (teste)'),
  ('dddddddd-0001-0000-0000-000000000002', 'bootstrap-dois', 'Bootstrap Dois (teste)');
insert into auth.users (id, email) values
  ('dddddddd-0002-0000-0000-000000000002', 'com-dois-restaurantes@exemplo.test');
do $$
begin
  if (select count(*) from public.staff) <> 0 then
    raise exception 'GATILHO: com 2 restaurantes, o primeiro usuário virou staff (não pode: não dá para saber de qual restaurante ele seria dono)';
  end if;
end $$;

-- 3. um restaurante, staff vazio ------------------------------------------
delete from public.restaurants where id = 'dddddddd-0001-0000-0000-000000000002';
-- dois INSERTs separados: o cenário "primeiro, depois o segundo" fica explícito
insert into auth.users (id, email) values
  ('dddddddd-0002-0000-0000-000000000003', 'primeiro-dono@exemplo.test');
insert into auth.users (id, email) values
  ('dddddddd-0002-0000-0000-000000000004', 'estranho-depois@exemplo.test');
do $$
declare
  v_papel text;
  v_restaurante uuid;
begin
  select role, restaurant_id into v_papel, v_restaurante from public.staff
   where user_id = 'dddddddd-0002-0000-0000-000000000003';
  if v_papel is distinct from 'owner' or v_restaurante is distinct from 'dddddddd-0001-0000-0000-000000000001' then
    raise exception 'GATILHO: o primeiro usuário de uma instalação com 1 restaurante deveria virar owner dele (papel %, restaurante %)', v_papel, v_restaurante;
  end if;
  if pg_temp.vinculos('dddddddd-0002-0000-0000-000000000004') <> 0 then
    raise exception 'ACESSO INDEVIDO: o segundo usuário cadastrado virou staff de um restaurante (só o primeiro vira dono; os outros entram pelo staff explicitamente)';
  end if;
  if (select count(*) from public.staff) <> 1 then
    raise exception 'GATILHO: esperado exatamente 1 vínculo de staff após os dois cadastros, há %', (select count(*) from public.staff);
  end if;
end $$;

-- 4. um restaurante, staff preenchido à mão (sem passar pelo gatilho) -------
delete from public.staff;
insert into public.staff (user_id, restaurant_id, role) values
  ('dddddddd-0002-0000-0000-000000000004', 'dddddddd-0001-0000-0000-000000000001', 'kitchen');
insert into auth.users (id, email) values
  ('dddddddd-0002-0000-0000-000000000005', 'outro-estranho@exemplo.test');
do $$
begin
  if pg_temp.vinculos('dddddddd-0002-0000-0000-000000000005') <> 0 then
    raise exception 'ACESSO INDEVIDO: com staff já preenchido, um usuário novo virou staff (a guarda "exists staff" do bootstrap_first_owner foi perdida)';
  end if;
  if (select count(*) from public.staff) <> 1 then
    raise exception 'GATILHO: o cadastro de um usuário novo mexeu na tabela staff (esperado 1 vínculo, há %)', (select count(*) from public.staff);
  end if;
end $$;

rollback;
