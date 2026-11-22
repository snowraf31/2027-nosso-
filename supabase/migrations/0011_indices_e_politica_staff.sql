-- =====================================================================
-- 0011 · Índices das chaves estrangeiras e política staff_read_own sem re-avaliação por linha
--
-- Origem: avisos de desempenho do Supabase (advisors) no projeto de desenvolvimento.
--
-- 1) unindexed_foreign_keys: o Postgres não cria índice sozinho para a coluna que referencia
--    outra tabela. Sem ele, apagar ou atualizar a linha "pai" (ex.: um restaurante, uma categoria,
--    um item do cardápio) varre a tabela "filha" inteira, e os JOINs do cardápio e da cozinha
--    ficam mais lentos conforme o banco cresce.
--    Só entram aqui as FKs que de fato não têm índice começando pela coluna. Já cobertas, por
--    isso fora da lista:
--      - orders.restaurant_id          -> orders_board_idx (restaurant_id, status, created_at)
--      - tables.restaurant_id          -> unique (restaurant_id, label)
--      - staff.user_id                 -> chave primária (user_id, restaurant_id)
--      - item_modifier_groups.item_id  -> chave primária (item_id, group_id)
--      - order_items.order_id          -> order_items_order_idx
--    A chave primária de staff começa por user_id: não serve para restaurant_id.
--    Sem "concurrently": a migration roda dentro de uma transação. As tabelas são pequenas.
--
-- 2) auth_rls_initplan: a política staff_read_own chamava auth.uid() direto, e o Postgres
--    reavalia a função a cada linha. Com (select auth.uid()) ela vira um InitPlan, calculado
--    uma vez por consulta. A semântica é a mesma: cada pessoa vê só a própria linha de staff.
--
-- Só acréscimos: nenhuma migration anterior é editada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Índices para chaves estrangeiras sem índice
-- ---------------------------------------------------------------------
create index if not exists item_modifier_groups_group_id_idx on public.item_modifier_groups (group_id);
create index if not exists menu_categories_restaurant_id_idx on public.menu_categories (restaurant_id);
create index if not exists menu_items_category_id_idx        on public.menu_items (category_id);
create index if not exists menu_items_restaurant_id_idx      on public.menu_items (restaurant_id);
create index if not exists modifier_groups_restaurant_id_idx on public.modifier_groups (restaurant_id);
create index if not exists modifier_options_group_id_idx     on public.modifier_options (group_id);
create index if not exists order_items_menu_item_id_idx      on public.order_items (menu_item_id);
create index if not exists orders_table_id_idx               on public.orders (table_id);
create index if not exists staff_restaurant_id_idx           on public.staff (restaurant_id);

-- ---------------------------------------------------------------------
-- 2) staff_read_own com (select auth.uid())
-- ---------------------------------------------------------------------
drop policy if exists staff_read_own on public.staff;
create policy staff_read_own on public.staff
  for select using (user_id = (select auth.uid()));
