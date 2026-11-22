-- =====================================================================
-- Teste de isolamento · 0008 · Quem pode executar cada função security definer
--
-- As 5 funções security definer rodam com o poder do dono e ignoram a RLS: quem pode chamá-las
-- é parte da segurança. Este teste trava a matriz EXATA de EXECUTE (o que as migrations 0001, 0004,
-- 0005 e 0006 concederam e a 0010 preservou ao recriar place_order):
--
--   função                                      PUBLIC  anon  authenticated  service_role
--   place_order(text, jsonb, text, int, text)     não    sim       sim           sim
--   get_guest_menu(text, text)                    não    sim       sim           sim
--   get_guest_order(uuid, text)                   não    sim       sim           sim
--   is_staff(uuid, text[])                        não    não       sim           sim
--   bootstrap_first_owner()                       não    não       não           sim
--
-- "PUBLIC" é o papel que todo mundo herda: EXECUTE para PUBLIC abre a função para qualquer papel
-- do cluster. service_role é o que o servidor Next.js usa: perder o EXECUTE dele quebra o app.
-- Os dois sentidos derrubam o CI (a matriz é conferida por igualdade, não só por "não tem demais").
--
-- Autocontido: só lê o catálogo. Falha com raise exception.
-- =====================================================================
begin;

do $$
declare
  v_func   record;
  v_papel  text;
  v_tem    boolean;
  v_devia  boolean;
  v_erros  text := '';
begin
  for v_func in
    select * from (values
      ('public.place_order(text, jsonb, text, integer, text)',  array['anon', 'authenticated', 'service_role']),
      ('public.get_guest_menu(text, text)',                     array['anon', 'authenticated', 'service_role']),
      ('public.get_guest_order(uuid, text)',                    array['anon', 'authenticated', 'service_role']),
      ('public.is_staff(uuid, text[])',                         array['authenticated', 'service_role']),
      ('public.bootstrap_first_owner()',                        array['service_role'])
    ) v (assinatura, executam)
  loop
    if to_regprocedure(v_func.assinatura) is null then
      raise exception 'PREPARO DO TESTE: função % não existe (foi renomeada? atualize a matriz deste teste)', v_func.assinatura;
    end if;
    foreach v_papel in array array['public', 'anon', 'authenticated', 'service_role'] loop
      v_tem   := has_function_privilege(v_papel, v_func.assinatura::regprocedure, 'execute');
      v_devia := v_papel = any (v_func.executam);
      if v_tem and not v_devia then
        v_erros := v_erros || format(E'\n  %s ganhou EXECUTE em %s (não devia)', v_papel, v_func.assinatura);
      elsif v_devia and not v_tem then
        v_erros := v_erros || format(E'\n  %s perdeu o EXECUTE em %s (devia ter)', v_papel, v_func.assinatura);
      end if;
    end loop;
  end loop;

  if v_erros <> '' then
    raise exception 'Matriz de EXECUTE das funções security definer mudou:%. Se a mudança é intencional, revise com o dev-backend e atualize este teste (e a guarda do 0003, item 4).', v_erros;
  end if;
end $$;

rollback;
