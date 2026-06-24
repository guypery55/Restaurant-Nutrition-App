-- McDonald's Rothschild TLV — menu rebuild (separate from the curated TLV seed)
-- ============================================================================
-- WHY SEPARATE / HOW PRODUCED:
--   McDonald's IL official site is fully JavaScript-rendered (the Session-3
--   pipeline could only scrape ~30 promo/McCafé items), and price aggregators
--   block scraping. So the menu here is rebuilt from foodiepedia.co.il (an
--   Israeli nutrition database): the ITEM NAMES are real/grounded from
--   foodiepedia, but its per-serving nutrition numbers extract unreliably
--   through automated tools (e.g. it rendered a Big Mac at 396 cal), so the
--   nutrition below is ESTIMATED (Claude Opus 4.8), consistent with the rest of
--   the seed — NOT foodiepedia's misread figures.
--   NO PRICES: foodiepedia carries no menu prices, so price is null throughout.
--   Scope: food + desserts only (drinks excluded, per decision). Individual
--   condiment/sauce SKUs were omitted as non-dish noise.
--
--   source='claudecode', source_url=foodiepedia brand page, verified=false.
--   This REPLACES the 30 promo items the pipeline previously stored.
--   Safe to re-run (deletes this restaurant's menu, re-inserts).
-- ============================================================================

begin;

insert into restaurants (place_id, name, address, lat, lng, website) values
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','מקדונלד''ס - רוטשילד, תל אביב','שדרות רוטשילד 33, תל אביב-יפו, 6688302, ישראל',32.0638547,34.7735046,'https://www.mcdonalds.co.il/')
on conflict (place_id) do update
  set name = excluded.name, address = excluded.address,
      lat = excluded.lat, lng = excluded.lng, website = excluded.website;

delete from menus where restaurant_id in (
  select id from restaurants where place_id = 'ChIJcQmHsoJMHRURjdNeAtx4ajo'
);

with m as (
  insert into menus (restaurant_id, source, scraper, source_url, verified, fetched_at)
  select id, 'claudecode', null, 'https://foodiepedia.co.il/company/%D7%9E%D7%A7%D7%93%D7%95%D7%A0%D7%9C%D7%93%D7%A1/', false, now()
  from restaurants where place_id = 'ChIJcQmHsoJMHRURjdNeAtx4ajo'
  returning id
)
insert into dishes (menu_id, name_he, name_translit, description, section, price)
select m.id, v.name_he, v.name_translit, v.description, v.section, null
from m, (values
  ('ביג מק','Big Mac','Two beef patties, special sauce, lettuce, cheese, pickles, onion in a sesame bun','Burgers'),
  ('מק רויאל קלאסי','McRoyal Classic','Grilled beef patty, cheese, lettuce and royal sauce in a bun','Burgers'),
  ('מק רויאל חריף','McRoyal Spicy','Grilled beef patty with spicy royal sauce and cheese','Burgers'),
  ('דאבל מק רויאל על גחלים','Double McRoyal on Coals','Two charcoal-grilled beef patties, cheese and royal sauce','Burgers'),
  ('צ''יזבורגר','Cheeseburger','Beef patty, cheese, pickles and ketchup in a bun','Burgers'),
  ('טריפל צ''יזבורגר','Triple Cheeseburger','Three beef patties with cheese and pickles in a bun','Burgers'),
  ('ביג וגן','Big Vegan','Plant-based patty with vegetables and sauce in a bun','Burgers'),
  ('מק צ''יקן קלאסי','McChicken Classic','Breaded chicken patty with lettuce and mayo in a bun','Chicken'),
  ('דאבל מק צ''יקן','Double McChicken','Two breaded chicken patties with lettuce and mayo','Chicken'),
  ('קריספי צ''יקן','Crispy Chicken','Crispy fried chicken fillet with lettuce and sauce in a bun','Chicken'),
  ('מגה קריספי צ''יקן','Mega Crispy Chicken','Large crispy chicken sandwich with double fillet','Chicken'),
  ('מיני קריספי צ''יקן','Mini Crispy Chicken','Small crispy chicken slider in a mini bun','Chicken'),
  ('צ''יקן מק נאגטס קלאסי','Chicken McNuggets Classic','Breaded chicken nuggets','Chicken'),
  ('פוטטו קטן','Potato Wedges Small','Small portion of seasoned potato wedges','Sides'),
  ('פוטטו רגיל','Potato Wedges Regular','Regular portion of seasoned potato wedges','Sides'),
  ('פוטטו גדול','Potato Wedges Large','Large portion of seasoned potato wedges','Sides'),
  ('פוטטו ענק','Potato Wedges Huge','Extra-large portion of seasoned potato wedges','Sides'),
  ('צ''יפס קטן','Fries Small','Small fries','Sides'),
  ('צ''יפס רגיל','Fries Regular','Regular fries','Sides'),
  ('צ''יפס גדול','Fries Large','Large fries','Sides'),
  ('צ''יפס ענק','Fries Huge','Extra-large fries','Sides'),
  ('טבעות בצל','Onion Rings','Battered fried onion rings','Sides'),
  ('סלט ירוק קטן','Small Green Salad','Small green side salad','Sides'),
  ('סלט ירוק עם קריספי צ''יקן','Green Salad with Crispy Chicken','Green salad topped with crispy fried chicken','Sides'),
  ('סלט ירוק עם נאגטס','Green Salad with Nuggets','Green salad topped with chicken nuggets','Sides'),
  ('חטיפי גזר','Carrot Snack','Fresh carrot sticks (kids side)','Sides'),
  ('סקוויז תפוח בננה','Apple-Banana Squeeze','Apple-banana fruit puree pouch','Sides'),
  ('דונאטס אוראו','Oreo Donuts','Donut bites with Oreo topping','Desserts'),
  ('דונאט בציפוי שוקולד זברה','Zebra Chocolate Donut','Donut with zebra chocolate coating','Desserts'),
  ('גלידה פיצוץ תות ובוטנים','Ice Cream Pitzutz Strawberry & Peanut','Soft-serve sundae with strawberry sauce and peanuts','Desserts'),
  ('מילקשייק שוקו','Chocolate Milkshake','Chocolate milkshake','Desserts'),
  ('מילקשייק שוקו וניל','Choco-Vanilla Milkshake','Chocolate-vanilla milkshake','Desserts'),
  ('פרימיום שייק אוריאו','Premium Oreo Shake','Premium thick shake with Oreo','Desserts')
) as v(name_he, name_translit, description, section);

insert into dish_estimates (
  dish_id, calories_low, calories_high, protein_low, protein_high,
  carbs_low, carbs_high, sugar_low, sugar_high, fat_low, fat_high,
  tags, reasoning, model
)
select d.id, e.cl, e.ch, e.pl, e.ph, e.cbl, e.cbh, e.sl, e.sh, e.fl, e.fh,
       e.tags, e.reasoning, 'claude-opus-4-8'
from dishes d
join menus mn on mn.id = d.menu_id
join restaurants r on r.id = mn.restaurant_id
join (values
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','ביג מק',480,560,24,30,42,50,8,11,24,32,array['meat','fried','fast-food'],'Two beef patties with special sauce, lettuce and cheese in a sesame bun'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','מק רויאל קלאסי',480,580,26,34,38,46,8,11,24,34,array['meat','fast-food','high-protein'],'Grilled beef patty with cheese, lettuce and royal sauce in a bun'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','מק רויאל חריף',500,600,26,34,38,48,8,12,26,36,array['meat','spicy','fast-food'],'Spicy McRoyal with chili sauce, grilled beef and cheese'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','דאבל מק רויאל על גחלים',700,860,44,56,40,50,9,13,42,58,array['meat','high-protein','fast-food'],'Two charcoal-grilled beef patties with cheese and royal sauce'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','צ''יזבורגר',290,360,15,20,30,38,7,10,12,18,array['meat','fast-food'],'Beef patty with cheese, pickles and ketchup in a bun'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','טריפל צ''יזבורגר',500,620,30,40,30,40,7,10,28,40,array['meat','high-protein','fast-food'],'Three beef patties with cheese and pickles in a bun'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','ביג וגן',500,620,18,28,56,74,8,13,18,30,array['vegan','fried','fast-food'],'Plant-based patty with vegetables and sauce in a bun'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','מק צ''יקן קלאסי',380,470,15,22,38,48,5,8,16,26,array['fried','fast-food'],'Breaded chicken patty with lettuce and mayo in a bun'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','דאבל מק צ''יקן',520,640,26,36,40,50,5,9,26,40,array['fried','high-protein','fast-food'],'Two breaded chicken patties with lettuce and mayo'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','קריספי צ''יקן',500,620,24,32,44,56,6,10,22,34,array['fried','fast-food'],'Crispy fried chicken fillet with lettuce and sauce in a bun'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','מגה קריספי צ''יקן',680,840,34,46,56,72,8,13,32,48,array['fried','high-protein','fast-food'],'Large crispy chicken sandwich with double fillet'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','מיני קריספי צ''יקן',280,360,12,18,26,34,3,6,12,20,array['fried','fast-food'],'Small crispy chicken slider in a mini bun'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','צ''יקן מק נאגטס קלאסי',200,420,12,22,12,26,0,2,12,26,array['fried','fast-food'],'Breaded chicken nuggets, 6 to 10 pieces depending on portion'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','פוטטו קטן',180,260,2,4,24,34,0,2,8,14,array['fried','vegetarian'],'Small portion of seasoned potato wedges'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','פוטטו רגיל',240,340,3,5,32,44,0,2,11,18,array['fried','vegetarian'],'Regular portion of seasoned potato wedges'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','פוטטו גדול',340,460,4,7,44,60,0,3,16,26,array['fried','vegetarian'],'Large portion of seasoned potato wedges'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','פוטטו ענק',420,560,5,8,54,72,0,3,20,32,array['fried','vegetarian'],'Extra-large portion of seasoned potato wedges'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','צ''יפס קטן',210,290,2,4,26,36,0,2,10,16,array['fried','vegetarian'],'Small fries'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','צ''יפס רגיל',300,400,3,5,38,50,0,2,14,22,array['fried','vegetarian'],'Regular fries'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','צ''יפס גדול',400,520,4,7,50,66,0,3,19,30,array['fried','vegetarian'],'Large fries'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','צ''יפס ענק',480,620,5,8,60,80,0,3,23,36,array['fried','vegetarian'],'Extra-large fries'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','טבעות בצל',280,400,4,7,34,48,3,6,14,24,array['fried','vegetarian'],'Battered fried onion rings'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','סלט ירוק קטן',60,120,2,4,6,12,3,6,3,7,array['vegetarian','vegan','light'],'Small green side salad'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','סלט ירוק עם קריספי צ''יקן',280,420,18,26,18,28,4,8,14,24,array['high-protein','fried'],'Green salad topped with crispy fried chicken'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','סלט ירוק עם נאגטס',260,400,15,22,18,28,4,8,13,22,array['fried'],'Green salad topped with chicken nuggets'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','חטיפי גזר',25,50,0,2,6,11,4,8,0,1,array['vegan','light'],'Fresh carrot sticks served as a kids side'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','סקוויז תפוח בננה',50,90,0,1,12,20,10,17,0,1,array['vegan','light'],'Apple-banana fruit puree pouch'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','דונאטס אוראו',240,360,3,6,30,44,16,26,12,20,array['dessert','sweet'],'Donut bites topped with Oreo'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','דונאט בציפוי שוקולד זברה',260,380,3,6,32,46,18,28,12,22,array['dessert','sweet'],'Donut with zebra chocolate coating'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','גלידה פיצוץ תות ובוטנים',220,340,4,8,30,46,24,38,8,15,array['dessert','sweet','frozen'],'Soft-serve sundae with strawberry sauce and peanuts'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','מילקשייק שוקו',320,480,8,13,52,74,44,64,8,15,array['dessert','sweet','frozen'],'Chocolate milkshake'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','מילקשייק שוקו וניל',320,480,8,13,52,74,44,64,8,15,array['dessert','sweet','frozen'],'Chocolate-vanilla milkshake'),
  ('ChIJcQmHsoJMHRURjdNeAtx4ajo','פרימיום שייק אוריאו',420,620,9,15,60,86,48,70,14,26,array['dessert','sweet','frozen'],'Premium thick shake with Oreo')
) as e(place_id, name_he, cl, ch, pl, ph, cbl, cbh, sl, sh, fl, fh, tags, reasoning)
  on e.place_id = r.place_id and e.name_he = d.name_he
on conflict (dish_id) do nothing;

commit;
