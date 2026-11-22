-- =====================================================================
-- Teste · 0010 · Índices das chaves estrangeiras e auth.uid() nas políticas de RLS
--
-- Trava dois avisos de desempenho do Supabase para não voltarem:
--
--   1. Toda chave estrangeira do schema public tem um índice cuja primeira coluna é a coluna da
--      FK (nas FKs de várias colunas, as primeiras colunas do índice são as da FK). Sem isso,
--      apagar ou atualizar a linha "pai" varre a tabela "filha" inteira. Um índice parcial ou
--      inválido não conta.
--   2. Nenhuma política de RLS do schema public chama auth.uid() solto. Tem de ser
--      (select auth.uid()), que o Postgres calcula uma vez por consulta em vez de uma vez por
--      linha. Lê pg_policies.qual e with_check.
--
-- Autocontido: só lê o catálogo. Falha com raise exception.
-- =====================================================================
begin;

do $$
declare
  v_fk     record;
  v_pol    record;
  v_expr   text;
  v_resto  text;
  v_erros  text := '';
begin
  -- 1. FKs sem índice -------------------------------------------------
  for v_fk in
    select c.oid,
           c.conname,
           c.conrelid,
           c.conrelid::regclass::text as tabela,
           c.conkey,
           cardinality(c.conkey) as n,
           (select string_agg(a.attname::text, ', ' order by k.ord)
              from unnest(c.conkey) with ordinality k(attnum, ord)
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum) as colunas
      from pg_constraint c
     where c.contype = 'f'
       and c.connamespace = 'public'::regnamespace
     order by 4, 2
  loop
    -- Índice válido, não parcial, cujas n primeiras colunas são as da FK (em qualquer ordem).
    if not exists (
      select 1
        from pg_index i
       where i.indrelid = v_fk.conrelid
         and i.indisvalid
         and i.indpred is null
         and i.indnkeyatts >= v_fk.n
         and (select array_agg(x order by x)
                from unnest((i.indkey::int2[])[0:v_fk.n - 1]) x)
             = (select array_agg(x order by x) from unnest(v_fk.conkey) x)
    ) then
      v_erros := v_erros || format(
        E'\n  - FK %s em %s (%s) sem índice. Corrija com uma migration nova: create index if not exists %s_%s_idx on %s (%s);',
        v_fk.conname, v_fk.tabela, v_fk.colunas,
        v_fk.tabela, replace(v_fk.colunas, ', ', '_'), v_fk.tabela, v_fk.colunas);
    end if;
  end loop;

  if v_erros <> '' then
    raise exception E'Chaves estrangeiras sem índice (apagar/atualizar a linha pai varre a tabela filha inteira):%', v_erros;
  end if;

  -- 2. auth.uid() solto nas políticas de RLS ---------------------------
  for v_pol in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname = 'public'
     order by tablename, policyname
  loop
    foreach v_expr in array array[v_pol.qual, v_pol.with_check]
    loop
      continue when v_expr is null;
      -- Tira os usos corretos: "(select auth.uid())", que o Postgres mostra como
      -- "( SELECT auth.uid() AS uid)". O que sobrar com auth.uid() é uso solto.
      v_resto := regexp_replace(
        v_expr, '\(\s*select\s+auth\.uid\(\)(\s+as\s+\w+)?\s*\)', '', 'gi');
      if v_resto ~* 'auth\.uid\(\)' then
        v_erros := v_erros || format(
          E'\n  - política %s em %s.%s chama auth.uid() solto. Corrija com uma migration nova: drop policy + create policy trocando auth.uid() por (select auth.uid()).',
          v_pol.policyname, v_pol.schemaname, v_pol.tablename);
      end if;
    end loop;
  end loop;

  if v_erros <> '' then
    raise exception E'Políticas de RLS com auth.uid() fora de (select auth.uid()) (reavaliado a cada linha):%', v_erros;
  end if;

  -- Trava de sanidade: a política que motivou o teste existe e usa a forma correta.
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'staff' and policyname = 'staff_read_own'
       and qual ~* 'select\s+auth\.uid\(\)'
  ) then
    raise exception 'A política public.staff_read_own não existe ou não usa (select auth.uid()). Ela é a única que lê auth.uid() hoje: recrie-a com (select auth.uid()).';
  end if;
end
$$;

rollback;
