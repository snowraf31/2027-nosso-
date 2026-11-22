-- =====================================================================
-- Tabletop · Demo data: "Harbor & Pine" café with 12 tables
-- Demo table 7 URL:  /r/harbor-pine/t/demo-table-7
-- Safe to run once on a fresh database.
-- =====================================================================
do $$
declare
  r uuid; c_coffee uuid; c_breakfast uuid; c_sand uuid; c_bakery uuid;
  g_milk uuid; g_size uuid; g_coffee_extras uuid; g_add uuid; g_bread uuid;
  g_protein uuid; g_side uuid; g_acai uuid; g_matcha uuid;
  i uuid;
begin
  insert into restaurants (slug, name, timezone, tax_rate)
  values ('harbor-pine', 'Harbor & Pine', 'America/New_York', 0.07)
  returning id into r;

  -- Tables 1–12 (fixed tokens only for the demo; real tables get random tokens)
  insert into tables (restaurant_id, label, qr_token)
  select r, n::text, 'demo-table-' || n from generate_series(1, 12) n;

  insert into menu_categories (restaurant_id, name, position) values (r, 'Coffee', 1)     returning id into c_coffee;
  insert into menu_categories (restaurant_id, name, position) values (r, 'Breakfast', 2)  returning id into c_breakfast;
  insert into menu_categories (restaurant_id, name, position) values (r, 'Sandwiches', 3) returning id into c_sand;
  insert into menu_categories (restaurant_id, name, position) values (r, 'Bakery', 4)     returning id into c_bakery;

  -- Modifier groups
  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Milk', 1, 1) returning id into g_milk;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_milk, 'Whole milk', 0, 1), (g_milk, 'Oat milk', 75, 2), (g_milk, 'Almond milk', 75, 3);

  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Size', 1, 1) returning id into g_size;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_size, '12 oz', 0, 1), (g_size, '16 oz', 75, 2);

  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Extras', 0, 3) returning id into g_coffee_extras;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_coffee_extras, 'Extra shot', 100, 1), (g_coffee_extras, 'Vanilla syrup', 60, 2), (g_coffee_extras, 'Cinnamon', 0, 3);

  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Add', 0, 2) returning id into g_add;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_add, 'Poached egg', 200, 1), (g_add, 'Smoked salmon', 450, 2);

  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Bread', 1, 1) returning id into g_bread;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_bread, 'Sourdough', 0, 1), (g_bread, 'Gluten-free bread', 150, 2);

  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Protein', 1, 1) returning id into g_protein;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_protein, 'No meat', 0, 1), (g_protein, 'Chorizo', 250, 2), (g_protein, 'Bacon', 250, 3);

  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Side', 1, 1) returning id into g_side;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_side, 'Plantain chips', 0, 1), (g_side, 'Side salad', 100, 2);

  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Topping', 1, 1) returning id into g_acai;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_acai, 'Almond granola', 0, 1), (g_acai, 'Coconut flakes (nut-free)', 0, 2);

  insert into modifier_groups (restaurant_id, name, min_select, max_select) values (r, 'Matcha milk', 1, 1) returning id into g_matcha;
  insert into modifier_options (group_id, name, price_cents, position) values
    (g_matcha, 'Oat milk', 0, 1), (g_matcha, 'Coconut milk', 0, 2);

  -- Items
  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_coffee, 'Cold Brew', 'Steeped 18 hours, smooth and low-acid. Served over ice.', 475, '{vegan,gf,nf}', '{}', 1) returning id into i;
  insert into item_modifier_groups values (i, g_size, 1), (i, g_coffee_extras, 2);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_coffee, 'Café Latte', 'Double shot of espresso with steamed milk.', 525, '{gf,nf}', '{dairy}', 2) returning id into i;
  insert into item_modifier_groups values (i, g_milk, 1), (i, g_coffee_extras, 2);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_coffee, 'Café con Leche', 'Cuban-style espresso, sweetened, with hot milk.', 450, '{gf,nf}', '{dairy}', 3) returning id into i;
  insert into item_modifier_groups values (i, g_milk, 1);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_coffee, 'Iced Matcha', 'Ceremonial-grade matcha whisked to order.', 575, '{vegan,gf,nf}', '{}', 4) returning id into i;
  insert into item_modifier_groups values (i, g_matcha, 1);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_breakfast, 'Avocado Toast', 'Smashed avocado, pickled onion, chili flakes and lime on sourdough.', 1150, '{vegan,nf}', '{gluten}', 1) returning id into i;
  insert into item_modifier_groups values (i, g_bread, 1), (i, g_add, 2);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_breakfast, 'Breakfast Burrito', 'Scrambled eggs, black beans, potato, cheddar, salsa verde.', 1200, '{nf}', '{gluten,dairy,egg}', 2) returning id into i;
  insert into item_modifier_groups values (i, g_protein, 1);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_breakfast, 'Açaí Bowl', 'Açaí, banana, berries and honey with your choice of topping.', 1050, '{gf}', '{tree_nuts}', 3) returning id into i;
  insert into item_modifier_groups values (i, g_acai, 1);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_sand, 'Cuban Press', 'Mojo pork, ham, Swiss, pickles and mustard on pressed Cuban bread.', 1350, '{nf}', '{gluten,dairy}', 1) returning id into i;
  insert into item_modifier_groups values (i, g_side, 1);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position)
  values (r, c_sand, 'Grilled Veggie Wrap', 'Zucchini, peppers, hummus and arugula in a spinach tortilla.', 1100, '{vegan,nf}', '{gluten,sesame}', 2) returning id into i;
  insert into item_modifier_groups values (i, g_side, 1);

  insert into menu_items (restaurant_id, category_id, name, description, price_cents, dietary_tags, allergens, position) values
    (r, c_bakery, 'Guava Pastelito', 'Flaky puff pastry with guava and cream cheese.', 375, '{nf}', '{gluten,dairy}', 1),
    (r, c_bakery, 'Almond Croissant', 'Twice-baked butter croissant, frangipane, toasted almonds.', 425, '{}', '{gluten,dairy,tree_nuts}', 2),
    (r, c_bakery, 'GF Banana Bread', 'Moist, lightly spiced, baked gluten-free in house.', 395, '{gf,nf}', '{egg}', 3);
end $$;
