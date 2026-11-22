-- =====================================================================
-- Tabletop · Demo personality for "Harbor & Pine" (run after seed.sql)
-- Safe to run more than once.
-- =====================================================================
do $$
declare r uuid;
begin
  select id into r from restaurants where slug = 'harbor-pine';
  if r is null then return; end if;

  update restaurants set tagline = 'Coffee, Cuban bakes and slow mornings in St. Pete' where id = r;

  update menu_categories set icon = 'cup',      note = 'Pulled to order'        where restaurant_id = r and name = 'Coffee';
  update menu_categories set icon = 'egg',      note = 'All day, every day'     where restaurant_id = r and name = 'Breakfast';
  update menu_categories set icon = 'sandwich', note = 'Pressed hot'            where restaurant_id = r and name = 'Sandwiches';
  update menu_categories set icon = 'pastry',   note = 'Out of the oven at 6am' where restaurant_id = r and name = 'Bakery';

  update menu_items set moods = '{coffee}',       story = 'Steeped for 18 hours. Patience is the secret ingredient.', badge = 'Staff pick'
   where restaurant_id = r and name = 'Cold Brew';
  update menu_items set moods = '{coffee}'
   where restaurant_id = r and name = 'Café Latte';
  update menu_items set moods = '{coffee,sweet}', story = 'Sweet, strong and a little nostalgic. Ask for it lighter if you like.'
   where restaurant_id = r and name = 'Café con Leche';
  update menu_items set moods = '{coffee,light}'
   where restaurant_id = r and name = 'Iced Matcha';
  update menu_items set moods = '{light}'
   where restaurant_id = r and name = 'Avocado Toast';
  update menu_items set moods = '{hearty}',       story = 'Built for long mornings. Add chorizo if you mean business.'
   where restaurant_id = r and name = 'Breakfast Burrito';
  update menu_items set moods = '{light,sweet}',  story = 'Pick coconut flakes on top and it''s nut-free.'
   where restaurant_id = r and name = 'Açaí Bowl';
  update menu_items set moods = '{hearty}',       story = 'Pressed the Tampa way: crisp outside, melty inside.', badge = 'House favorite'
   where restaurant_id = r and name = 'Cuban Press';
  update menu_items set moods = '{light}'
   where restaurant_id = r and name = 'Grilled Veggie Wrap';
  update menu_items set moods = '{sweet}',        story = 'Baked at 6am. When they''re gone, they''re gone.', badge = 'Fresh today'
   where restaurant_id = r and name = 'Guava Pastelito';
  update menu_items set moods = '{sweet}'
   where restaurant_id = r and name = 'Almond Croissant';
  update menu_items set moods = '{sweet}'
   where restaurant_id = r and name = 'GF Banana Bread';

  -- "Goes well with"
  update menu_items m set pairs_with = array(
    select p.id from menu_items p
     where p.restaurant_id = r and p.name = case m.name
       when 'Cold Brew'           then 'Guava Pastelito'
       when 'Café Latte'          then 'Almond Croissant'
       when 'Café con Leche'      then 'Guava Pastelito'
       when 'Iced Matcha'         then 'GF Banana Bread'
       when 'Avocado Toast'       then 'Iced Matcha'
       when 'Breakfast Burrito'   then 'Cold Brew'
       when 'Açaí Bowl'           then 'Iced Matcha'
       when 'Cuban Press'         then 'Café con Leche'
       when 'Grilled Veggie Wrap' then 'Iced Matcha'
       when 'Guava Pastelito'     then 'Café con Leche'
       when 'Almond Croissant'    then 'Café Latte'
       when 'GF Banana Bread'     then 'Café Latte'
     end)
   where m.restaurant_id = r;
end $$;
