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

\ir _comum/dados.psql

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
