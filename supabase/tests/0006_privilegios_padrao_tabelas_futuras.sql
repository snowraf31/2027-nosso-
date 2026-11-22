-- =====================================================================
-- Teste de isolamento · 0006 · Privilégios padrão dos objetos FUTUROS (tabelas e sequências)
--
-- A guarda do catálogo (0003, itens 2b e 3b) olha os objetos que existem. Este teste olha o padrão
-- (default privileges) que a migration 0010 ajustou: uma tabela ou sequência criada depois, pelo
-- mesmo papel que roda as migrations, não pode nascer aberta.
--   tabelas:    anon sem privilégio nenhum; authenticated só com SELECT (sem INSERT, UPDATE, DELETE,
--               TRUNCATE, REFERENCES, TRIGGER nem, no Postgres 17, MAINTAIN)
--   sequências: anon e authenticated sem USAGE, SELECT nem UPDATE
-- O MAINTAIN só é conferido no Postgres 17 ou mais novo (no 16 o privilégio não existe e
-- has_table_privilege dá erro). Estrito: os objetos de teste são criados e desfeitos no rollback.
--
-- Fora do alcance deste teste (e da 0010): objeto criado por OUTRO papel (no Supabase real, por
-- exemplo supabase_admin) segue os default privileges desse papel, que o papel postgres não consegue
-- alterar. Para esse caso a rede de segurança é a guarda do catálogo do 0003, que derruba o CI se
-- o objeto chegar ao banco de teste com esses privilégios. Funções novas também ficam para a guarda
-- do 0003 (item 4): o PUBLIC já recebe EXECUTE por padrão e um default por papel não o tira.
--
-- Autocontido. Falha com raise exception.
-- =====================================================================
begin;

create table public.tabela_futura_de_teste (id uuid primary key default gen_random_uuid());
create sequence public.sequencia_futura_de_teste;

do $$
declare
  v_lista text;
  v_extra text[] := case when current_setting('server_version_num')::int >= 170000
                         then array['maintain'] else '{}'::text[] end;
begin
  -- anon: nada de nada na tabela nova
  select string_agg('anon (' || p || ')', ', ' order by p) into v_lista
    from unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] || v_extra) p
   where has_table_privilege('anon', 'public.tabela_futura_de_teste'::regclass, p);
  -- authenticated: tudo menos o SELECT (que a RLS filtra por restaurante)
  select nullif(concat_ws(', ', v_lista, (
           select string_agg('authenticated (' || p || ')', ', ' order by p)
             from unnest(array['insert', 'update', 'delete', 'truncate', 'references', 'trigger'] || v_extra) p
            where has_table_privilege('authenticated', 'public.tabela_futura_de_teste'::regclass, p))), '')
    into v_lista;
  if v_lista is not null then
    raise exception 'Tabela nova do public nasce aberta demais: %. O default privilege perdeu os revokes da migration 0010 (alter default privileges in schema public revoke ... on tables from authenticated, anon).', v_lista;
  end if;

  -- sequência nova: nenhum dos dois
  select string_agg(r || ' (' || p || ')', ', ' order by r, p) into v_lista
    from unnest(array['anon', 'authenticated']) r
    cross join unnest(array['usage', 'select', 'update']) p
   where has_sequence_privilege(r, 'public.sequencia_futura_de_teste'::regclass, p);
  if v_lista is not null then
    raise exception 'Sequência nova do public nasce com privilégio para a API: %. O default privilege perdeu o revoke da migration 0010 (alter default privileges in schema public revoke all on sequences from authenticated, anon).', v_lista;
  end if;

  -- sanidade: o papel de serviço (service_role) continua com o padrão aberto, senão a API de servidor quebra
  if not has_table_privilege('service_role', 'public.tabela_futura_de_teste'::regclass, 'select,insert,update,delete') then
    raise exception 'PREPARO DO TESTE: service_role deveria continuar com acesso às tabelas novas (padrão do Supabase).';
  end if;
end $$;

rollback;
