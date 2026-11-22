-- =====================================================================
-- Teste de isolamento · 0003 · Visitante anônimo e guarda do catálogo do banco
--
--   d) anon: nenhum privilégio nas tabelas (SELECT, INSERT, UPDATE e DELETE dão erro de
--      permissão) e não executa is_staff nem bootstrap_first_owner
--   f) guarda do catálogo (vale para objetos FUTUROS): toda tabela do schema public tem RLS
--      ligada; anon não tem privilégio nenhum em tabela ou view do public; authenticated só
--      escreve nas 3 colunas da cozinha; view, view materializada e tabela externa legíveis
--      por authenticated não podem furar a RLS; só as funções security definer conhecidas
--      (por assinatura) são executáveis por anon e por authenticated; tabela do Realtime
--      tem RLS. Objeto novo sem RLS, ou com grant aberto demais, derruba o CI aqui.
--
-- LACUNA CONHECIDA (não é falha deste teste, é aviso): o 0002_security.sql só revoga
-- INSERT, UPDATE e DELETE de authenticated; ele continua com TRUNCATE (que ignora a RLS e
-- esvaziaria as tabelas de todos os restaurantes), TRIGGER e REFERENCES nas 10 tabelas.
-- Pela API (PostgREST) ninguém dispara isso, mas quem conecta direto no SQL sim. A correção
-- é uma migration à parte: revoke truncate, references, trigger on all tables in schema
-- public from authenticated. Enquanto ela não existe, a guarda 3b só avisa, e SÓ no estado
-- legado exato (as 10 tabelas, os 3 privilégios, nada além). Com a migration aplicada, ou em
-- qualquer outro estado (tabela nova, privilégio em parte das tabelas), a guarda derruba o CI.
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
  v_legado text[] := array['restaurants', 'staff', 'tables', 'menu_categories', 'menu_items',
                           'modifier_groups', 'modifier_options', 'item_modifier_groups',
                           'orders', 'order_items'];
  v_total int;
  v_conhecidos int;
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

  -- 3b. authenticated: TRUNCATE, REFERENCES e TRIGGER ignoram a RLS (TRUNCATE esvazia a tabela
  --     de todos os restaurantes; um TRIGGER roda em cima das escritas de qualquer um deles).
  select string_agg(c.relname || ' (' || p || ')', ', ' order by c.relname, p),
         count(*), count(*) filter (where c.relname = any (v_legado))
    into v_lista, v_total, v_conhecidos
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join unnest(array['truncate', 'references', 'trigger']) p
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
     and has_table_privilege('authenticated', c.oid, p);
  if v_lista is not null then
    if v_total = 3 * cardinality(v_legado) and v_conhecidos = v_total then
      raise warning 'LACUNA CONHECIDA (ainda sem migration): o papel authenticated (staff) tem TRUNCATE, REFERENCES e TRIGGER nas 10 tabelas, e TRUNCATE ignora a RLS. Corrigir com: revoke truncate, references, trigger on all tables in schema public from authenticated.';
    else
      raise exception 'O papel authenticated (staff) tem TRUNCATE, REFERENCES ou TRIGGER em: %. Esses privilégios ignoram a RLS (TRUNCATE esvazia a tabela de todos os restaurantes). Faça revoke truncate, references, trigger ... from authenticated.', v_lista;
    end if;
  end if;

  -- 3c. View, view materializada e tabela externa rodam com o poder do DONO e ignoram a RLS:
  --     se authenticated lê uma delas, só vale view com security_invoker = true (RLS de quem consulta).
  select string_agg(c.relname || ' (' || case c.relkind when 'v' then 'view' when 'm' then 'view materializada' else 'tabela externa' end || ')',
                    ', ' order by c.relname) into v_lista
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('v', 'm', 'f')
     and (has_table_privilege('authenticated', c.oid, 'select')
          or has_any_column_privilege('authenticated', c.oid, 'select'))
     and not (c.relkind = 'v' and exists (select 1 from unnest(coalesce(c.reloptions, '{}'::text[])) o
                                           where o ~ '^security_invoker(=(true|on|yes|1|t))?$'))
     and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e');
  if v_lista is not null then
    raise exception 'Objeto legível por authenticated que ignora a RLS: %. Crie a view com WITH (security_invoker = true), ou faça revoke select ... from authenticated (view materializada e tabela externa nunca respeitam a RLS).', v_lista;
  end if;

  -- 4. Funções security definer ignoram a RLS. Só estas (por assinatura, não só pelo nome, para
  --    uma sobrecarga nova não escapar) podem ser executadas por anon / authenticated:
  --      as 3 funções do cliente (exigem token) e is_staff (só olha auth.uid()).
  select string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ') [' ||
                    concat_ws(' e ', case when has_function_privilege('anon', p.oid, 'execute') then 'anon' end,
                                     case when has_function_privilege('authenticated', p.oid, 'execute') then 'authenticated' end) || ']',
                    ', ' order by p.proname) into v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and (   (has_function_privilege('anon', p.oid, 'execute')
              and p.proname || '(' || oidvectortypes(p.proargtypes) || ')' not in (
                    'get_guest_menu(text, text)', 'get_guest_order(uuid, text)',
                    'place_order(text, jsonb, text, integer, text)'))
          or (has_function_privilege('authenticated', p.oid, 'execute')
              and p.proname || '(' || oidvectortypes(p.proargtypes) || ')' not in (
                    'get_guest_menu(text, text)', 'get_guest_order(uuid, text)',
                    'place_order(text, jsonb, text, integer, text)', 'is_staff(uuid, text[])')));
  if v_lista is not null then
    raise exception 'Função security definer executável por quem não devia (ela ignora a RLS e precisa filtrar por restaurante/token): %. Faça revoke execute ... from public, anon, authenticated (padrão do 0004/0006) ou, se for função do cliente com token ou checagem só de auth.uid(), revise o filtro e inclua a assinatura na lista desta guarda.', v_lista;
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
    raise warning 'Tabela(s) nova(s) no schema public sem teste de isolamento dedicado: %. Acrescente em pg_temp.tabelas() e nos dados de _comum/dados.psql (valem para os testes 0001 a 0003).', v_lista;
  end if;
end $$;

rollback;
