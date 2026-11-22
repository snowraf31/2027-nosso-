-- =====================================================================
-- Teste de isolamento · 0006 · Privilégios padrão das tabelas FUTURAS
--
-- A guarda do catálogo (0003, item 3b) olha as tabelas que existem. Este teste olha o padrão
-- (default privileges) que a migration 0010 ajustou: uma tabela criada depois, pelo mesmo papel
-- que roda as migrations, não pode nascer com TRUNCATE, REFERENCES ou TRIGGER para authenticated
-- nem para anon. Estrito: a tabela de teste é criada e desfeita no rollback.
--
-- Fora do alcance deste teste (e da 0010): tabela criada por OUTRO papel (no Supabase real,
-- por exemplo supabase_admin) segue os default privileges desse papel. Para esse caso a rede de
-- segurança é a guarda do catálogo do 0003, que derruba o CI se a tabela chegar ao banco de teste
-- com esses privilégios.
--
-- Autocontido. Falha com raise exception.
-- =====================================================================
begin;

create table public.tabela_futura_de_teste (id uuid primary key default gen_random_uuid());

do $$
declare
  v_lista text;
begin
  select string_agg(r || ' (' || p || ')', ', ' order by r, p) into v_lista
    from unnest(array['authenticated', 'anon']) r
    cross join unnest(array['truncate', 'references', 'trigger']) p
   where has_table_privilege(r, 'public.tabela_futura_de_teste'::regclass, p);
  if v_lista is not null then
    raise exception 'Tabela nova do public nasce com privilégio que ignora a RLS: %. O default privilege perdeu o revoke da migration 0010 (alter default privileges in schema public revoke truncate, references, trigger on tables from authenticated, anon).', v_lista;
  end if;
end $$;

rollback;
