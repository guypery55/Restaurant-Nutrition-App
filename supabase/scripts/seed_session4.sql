-- Session 4 — grounded hand-seed (Claude Code, build-plan §4B contract)
-- ============================================================================
-- HOW THIS DATA WAS PRODUCED (provenance / anti-fabrication):
--   Every dish below was TRANSCRIBED from a real page/PDF fetched live on
--   2026-06-24. Nothing was recalled from general knowledge. Restaurants were
--   resolved through the deployed resolve-restaurant function, so the place_id
--   values are canonical (the same key the live app computes).
--
--   - Taizu : English dinner menu HTML, cross-corroborated by the Hebrew page
--             https://www.taizu.co.il/en/menu-2/dinner/
--   - Goocha: current 2025 English menu PDF (read via pdf-parse text layer)
--             https://www.goocha.co.il/wp-content/uploads/2025/12/8_Goocha_2025_Menus_ENG_d.pdf
--   - M25   : Carmel Market branch menu HTML (food + desserts only; the wine /
--             beer / cocktail lists were intentionally dropped — not nutrition)
--             https://m25meat.co.il/carmel/
--
-- FLAGS: source='claudecode', verified=false (NOT yet human spot-checked),
--        real source_url recorded (DB provenance CHECK enforces this).
-- fetched_at = now() so the app serves these instantly from cache (warm + free,
--   per the cheap-MVP goal). If you would rather force the real pipeline to
--   re-acquire + verify them later, change now() to '2000-01-01'.
--
-- SAFE TO RE-RUN: deletes only these 3 restaurants' menus first (cascades to
--   their dishes), then re-inserts. Touches nothing else.
--
-- AFTER RUNNING: open each source_url, confirm a few dishes match, then
--   `update menus set verified=true where source='claudecode' and ...;`
-- ============================================================================

begin;

-- Canonical restaurant rows (metadata from Google Places via resolve-restaurant,
-- 2026-06-24). Upsert on place_id so this seed is self-contained and survives a
-- truncate of test data. These are the live app's cache keys.
insert into restaurants (place_id, name, address, lat, lng, website) values
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','טאיזו','דרך מנחם בגין 23, תל אביב-יפו, ישראל',32.0639037,34.779945,'http://www.taizu.co.il/'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Goocha Dizengoff','דיזנגוף 171, תל אביב-יפו, ישראל',32.0845876,34.7742132,'http://www.goocha.co.il/'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','M25 שוק הכרמל','סמטת הכרמל 30, תל אביב-יפו, ישראל',32.0677418,34.7673878,'http://m25meat.co.il/')
on conflict (place_id) do update
  set name = excluded.name, address = excluded.address,
      lat = excluded.lat, lng = excluded.lng, website = excluded.website;

delete from menus where restaurant_id in (
  select id from restaurants where place_id in (
    'ChIJa9zBe3tLHRURQHbcLSWNU1g', -- Taizu
    'ChIJKbk7OXxLHRURxs6enNzWz5E', -- Goocha Dizengoff
    'ChIJVai3i4RMHRURFQepMWKweY8'  -- M25 שוק הכרמל
  )
);

-- ---------------------------------------------------------------------------
-- TAIZU — AsiaTerranean (chef Yuval Ben Neriah). Prices in ₪.
-- name_he is Hebrew where captured verbatim from the Hebrew menu, otherwise the
-- English menu text. name_translit is the English menu name. Price ranges /
-- per-unit notes are kept in the description.
-- ---------------------------------------------------------------------------
with m as (
  insert into menus (restaurant_id, source, scraper, source_url, verified, fetched_at)
  select id, 'claudecode', null, 'https://www.taizu.co.il/en/menu-2/dinner/', false, now()
  from restaurants where place_id = 'ChIJa9zBe3tLHRURQHbcLSWNU1g'
  returning id
)
insert into dishes (menu_id, name_he, name_translit, description, section, price)
select m.id, v.name_he, v.name_translit, v.description, v.section, v.price
from m, (values
  ('לחמניות מאודות','Steamed Buns','Tomato chutney, buffalo yogurt, eggplant','Water',26),
  ('טרטר טאיזו','Taizu Tartar','Wild fish, crispy rice cone, black sesame, soy foam, flying fish roe. Per unit','Water',28),
  ('קונוס קוויאר','Caviar Cone','Ossetra caviar, crispy rice cone, creme fraiche foam, fish stock, pickled mussel. Per unit','Water',48),
  ('אויסטר טום קא','Oyster Tom Kah','Lambert oyster, coconut, galangal, lemongrass. Per unit','Water',42),
  ('קארי ואבטיח','Curry and Watermelon','Soy-pickled watermelon and melon, fresh green curry, fermented black mustard seeds, coconut cream. Per unit','Water',24),
  ('סלט דפי שעועית','Mung Bean Sheets Salad','Red basil, holy basil, caramelized cashews, radishes, shallots, Chinese tahini','Wood',66),
  ('סשימי טונה בלו-פין','Bluefin Tuna Sashimi','Tuna broth, lemongrass, caramelized shallots, toasted jasmine rice','Wood',108),
  ('קרפצ''יו באנגלי','Bangali Carpaccio','Local fish, curry leaves oil, papadam','Wood',104),
  ('הר גאו','Har Gow Dumplings','Black tiger shrimp, Jerusalem artichoke, spring onion, lime, fennel','Wood',82),
  ('Green Leaves Salad','Green Leaves Salad','Horseradish leaves, organic cornichon, nectarine, apricot, arare, apple vinaigrette','Wood',66),
  ('Wild Fish Ceviche','Wild Fish Ceviche','Red chili, galangal, kaffir lime, coconut, cucumbers','Wood',102),
  ('Swisschard Pot Stickers','Swisschard Pot Stickers','Swisschard, macadamia cream, freekeh, garlic chips, shimeji','Wood',82),
  ('Shrimp Salad','Shrimp Salad','Vietnamese herbs, crispy shallots, tamarind, shrimp crackers, soft-boiled egg','Wood',88),
  ('Shanghai Dumplings','Shanghai Dumplings','Veal cheeks, beef soup, pistachio masala, pomegranate broth. 58 / 86','Wood',58),
  ('באו טונה אדומה','Red Tuna Bao','Pickled lemon, pumpkin, sambal belado, soft egg. Per unit','Fire',54),
  ('ראמפ סיני','Chinese Rump','Homemade chili oil, green onion, bright soy, crispy garlic, cashmere pepper','Fire',98),
  ('טרטר בקר','Beef Tartar','Chopped rump, crispy shallots, tapioca pearls, rice puff, tamarind, wasabi leaf. Per 2 units','Fire',64),
  ('סלט קלמרי סיאם','Siam Calamari Salad','Poached calamari, charred corn, bean noodles, fish sauce, crispy shallots, chili oil, lime','Fire',78),
  ('נמס','Nems','Chopped chicken or tofu, carrots, peanuts, sprouts, tapioca pearls. Per unit','Earth',44),
  ('ספייר ריבס רול טלה','Lamb Spare Ribs Roll','Lamb spring roll, tamarind glaze, peanuts, cucumber, mint','Earth',92),
  ('קורמה טלה','Lamb Korma','Lace crepe, curry leaf, fenugreek, allspice, coconut cream. Per unit','Earth',52),
  ('מסאמן ירקות אורגניים עונתיים','Organic Seasonal Vegetables Massaman','Coconut cream, young corn, charred cherry tomatoes, Japanese eggplant, Thai eggplant, Thai zucchini, chili oil, peanuts','Earth',98),
  ('דניס נאם פלה','Nam Pla Sea Bream','Steamed sea bream, anise, tamarind, nam pla, coriander, chili, lime, coconut rice','Metal',185),
  ('לברק שלם מטוגן','Fried Whole Sea Bass','Lettuce, herbs, chili lime, peanuts, fish sauce','Metal',185),
  ('באטר צ''יקן','Butter Chicken','Tomatoes, ghee, fenugreek, peanuts, curry leaves, sour cream','Metal',118),
  ('פפר סטייק וייטנאמי','Vietnamese Pepper Steak','Bok choy, ratte potatoes, charred onions, onsen egg, nori toffee','Metal',218),
  ('נתח מיושן על העצם','Roasted Entrecote','Kashmir chili, forest mushrooms, onions, oyster sauce. Per 100 gr','Metal',82),
  ('Charcoal Corn','Charcoal Corn','Polenta cake, corn crumble, dark truffle, fiery potato ice cream','Desserts',62),
  ('Black Forest','Black Forest','Coconut cream, chocolate mousse, berries, matcha powder','Desserts',62),
  ('White Pandan Rice','White Pandan Rice','Coconut toffee, wild crispy rice, lime pearls, pandan, yogurt crumble','Desserts',62)
) as v(name_he, name_translit, description, section, price);

-- ---------------------------------------------------------------------------
-- GOOCHA DIZENGOFF — fish & seafood house. English menu (2025 PDF). Prices ₪.
-- Section grouping follows the PDF; a few items straddle headings in the PDF
-- flow, so treat `section` as approximate. Dish names + prices are verbatim.
-- ---------------------------------------------------------------------------
with m as (
  insert into menus (restaurant_id, source, scraper, source_url, verified, fetched_at)
  select id, 'claudecode', null, 'https://www.goocha.co.il/wp-content/uploads/2025/12/8_Goocha_2025_Menus_ENG_d.pdf', false, now()
  from restaurants where place_id = 'ChIJKbk7OXxLHRURxs6enNzWz5E'
  returning id
)
insert into dishes (menu_id, name_he, name_translit, description, section, price)
select m.id, v.name_he, v.name_translit, v.description, v.section, v.price
from m, (values
  ('Roasted Corno di Toro Pepper','Roasted Corno di Toro Pepper','Hameiri cheese, coriander seed oil, roasted almonds','Getting Started',42),
  ('Fish Ceviche','Fish Ceviche','Tomatoes, kalamata olives, onion, coriander','Getting Started',63),
  ('Red Tuna Tartare','Red Tuna Tartare','Avocado, yuzu saffron vinaigrette','Getting Started',82),
  ('Seared Baby Squid','Seared Baby Squid','Tahini, harissa, tomato salsa, fresh parsley','Getting Started',73),
  ('Beef Fillet Carpaccio Tonnato','Beef Fillet Carpaccio Tonnato','Tuna Ortiz aioli, capers, arugula','Getting Started',82),
  ('Fish Tacos','Fish Tacos','Crispy fish, chipotle, salsa, pickled onion','Getting Started',68),
  ('Garlic & Butter Shrimp','Garlic & Butter Shrimp','White wine, parsley, lemon','Fruits de Mer',84),
  ('Crab Meat with Mascarpone Agnolotti','Crab Meat with Mascarpone Agnolotti','Beurre blanc sauce','Fruits de Mer',98),
  ('Shrimp with Spicy Tomato Salsa','Shrimp with Spicy Tomato Salsa','Coriander, chili, olive oil','Fruits de Mer',84),
  ('Seafood Mix Garlic-Butter','Seafood Mix Garlic-Butter','White wine, parsley, lemon','Fruits de Mer',105),
  ('Seafood Curry','Seafood Curry','Coconut milk with plain rice','Fruits de Mer',105),
  ('Easy Peel Shrimp Platter','Easy Peel Shrimp Platter','Shell-on shrimp seared on the plancha, fermented pepper gazpacho','Fruits de Mer',134),
  ('Cheeseburger','Cheeseburger','100% ground beef on site, melted cheddar, fries','Surf & Turf',78),
  ('Roasted Chicken in Red Curry','Roasted Chicken in Red Curry','89 / with shrimp 101','Surf & Turf',89),
  ('Skillet Chicken','Skillet Chicken','Potatoes, green beans, herbs, grilled onions','Surf & Turf',89),
  ('Beef Fillet (aged in house)','Beef Fillet (aged in house)','Veal demi-glace, cream, black pepper sauce. 158 / with shrimp 172','Surf & Turf',158),
  ('The Diner''s Veal Spare Ribs','The Diner''s Veal Spare Ribs','Homemade BBQ glaze, roasted potatoes','Surf & Turf',182),
  ('Monday Evening Mussel Special','Monday Evening Mussel Special','1/2 kg mussels + fries + draft beer','Surf & Turf',112),
  ('Fried Calamari','Fried Calamari','Garlic & chili aioli','Surf & Turf',59),
  ('Crab Bisque','Crab Bisque',null,'Surf & Turf',69),
  ('Shrimp Roll Brioche','Shrimp Roll Brioche','Toasted bun filled with chopped shrimp and aioli','Surf & Turf',76),
  ('Crispy Black Cod','Crispy Black Cod','Wrapped in lettuce and herbs, nam jim sauce','Surf & Turf',73),
  ('Garlic Bread','Garlic Bread',null,'Surf & Turf',35),
  ('Sourdough Bread','Sourdough Bread','Romesco and garlic confit','Surf & Turf',21),
  ('Leafy Green Mix Salad','Leafy Green Mix Salad','Goat cheese, maple vinaigrette, mustard, roasted almonds','Salad',64),
  ('Caesar','Caesar',null,'Salad',58),
  ('Caesar Salad with Shrimp Tempura','Caesar Salad with Shrimp Tempura',null,'Salad',73),
  ('Pulpo','Pulpo','Selection of leaves, seared octopus, goat cheese, almonds, fruit','Salad',87),
  ('Crab Meat and Avocado','Crab Meat and Avocado','Mustard aioli and butter, on a mix of green leaves','Salad',88),
  ('Mussels & Fries Mariniere','Mussels & Fries Mariniere','Butter, white wine, garlic, parsley. 1/2 kg 98 / 1 kg 152','Salad',98),
  ('Gnocchi with Sea Bream Fillet','Gnocchi with Sea Bream Fillet','Garlic & butter sauce','Pasta',92),
  ('Seafood Pasta','Seafood Pasta','Tomato / cream / rose / aglio olio','Pasta',104),
  ('Shrimp & Crab Meat Pasta','Shrimp & Crab Meat Pasta','Cream sauce, sundried tomatoes','Pasta',110),
  ('Fish & Chips','Fish & Chips','Deep-fried fish fillet, tartare sauce','Fish',83),
  ('Whole Sea Bream','Whole Sea Bream','Deep fried / a la plancha','Fish',126),
  ('Salmon Fillet','Salmon Fillet','Dijon mustard & cream sauce, mashed potatoes','Fish',106),
  ('Miso Black Cod','Miso Black Cod','Coconut rice, bok choi, miso butter sauce','Fish',147),
  ('Sea Bass Fillet','Sea Bass Fillet','Roasted vegetables, cauliflower & goat cheese cream, chili oil','Fish',145),
  ('Red Tuna Steak','Red Tuna Steak','Soy & yuzu caramel, puree, bok choy','Fish',158),
  ('Sea Bream Fillet','Sea Bream Fillet','Baked zucchini, tomato salsa, olive oil, spiced breadcrumbs','Fish',114),
  ('Sea Bream & Shrimp Duet','Sea Bream & Shrimp Duet','Cream sauce, sundried tomatoes','Fish',139),
  ('Lemon Cream Meringue','Lemon Cream Meringue','With pistachio crumble','Desserts',48),
  ('Chocolate Sundae','Chocolate Sundae','Brownie, coconut flakes, white chocolate ganache','Desserts',46),
  ('Belgian Waffle','Belgian Waffle','Caramelized banana and vanilla ice cream','Desserts',54),
  ('Tiramisu','Tiramisu',null,'Desserts',46),
  ('Coconut Malabi Pudding','Coconut Malabi Pudding','Mango and berry sauce','Desserts',42),
  ('Chocolate Mousse with Peanut Crumble','Chocolate Mousse with Peanut Crumble','White chocolate sauce and whipped cream','Desserts',43),
  ('Creme Brulee','Creme Brulee','Classic vanilla','Desserts',41),
  ('Sundae with Berries','Sundae with Berries','Belgian waffle cream and amarena','Desserts',46)
) as v(name_he, name_translit, description, section, price);

-- ---------------------------------------------------------------------------
-- M25 (Carmel Market) — butcher / meat restaurant. Hebrew menu. Prices ₪.
-- Food + desserts only (wine / beer / cocktail lists omitted on purpose).
-- ---------------------------------------------------------------------------
with m as (
  insert into menus (restaurant_id, source, scraper, source_url, verified, fetched_at)
  select id, 'claudecode', null, 'https://m25meat.co.il/carmel/', false, now()
  from restaurants where place_id = 'ChIJVai3i4RMHRURFQepMWKweY8'
  returning id
)
insert into dishes (menu_id, name_he, name_translit, description, section, price)
select m.id, v.name_he, v.name_translit, v.description, v.section, v.price
from m, (values
  ('עראייס','Arayes',null,'תפריט שוק',59),
  ('שווארמה מעושנים','Shawarma Me''ushanim','Smoked shawarma','תפריט שוק',72),
  ('קבב שוק','Kebab Shuk',null,'תפריט שוק',73),
  ('המבורגר','Hamburger',null,'תפריט שוק',83),
  ('סלט ירוק','Salat Yarok','Green salad','תפריט שוק',56),
  ('סלט טחינה עגבניות','Salat Tehina Agvaniyot','Tahini & tomato salad','תפריט שוק',37),
  ('קורנביף','Corned Beef',null,'ספיישלים קבועים',69),
  ('לשון פרה','Leshon Para','Cow tongue','ספיישלים קבועים',67),
  ('לב שור','Lev Shor','Ox heart','ספיישלים קבועים',57),
  ('טרטר פריז','Tartar Pariz','Paris-style tartare','ספיישלים קבועים',61),
  ('סלט קצבים','Salat Katzavim','Butchers'' salad','ספיישלים קבועים',64),
  ('אנטריקוט','Entrecote','₪64 ל-100 גרם','סטייקים ושיפודים',64),
  ('על העצם','Al Ha''etzem','On the bone. ₪59–65 ל-100 גרם','סטייקים ושיפודים',59),
  ('צלע / אוכף טלה','Tzela / Ukaf Tale','Lamb rib / saddle. ₪56–59 ל-100 גרם','סטייקים ושיפודים',56),
  ('מבחר שיפודים','Mivchar Shipudim','Selection of skewers. ₪26–68 ל-100 גרם','סטייקים ושיפודים',null),
  ('מוס שוקולד','Mousse Shokolad','Chocolate mousse','קינוחים',39),
  ('קראק פאי','Crack Pie',null,'קינוחים',44),
  ('מלבי','Malabi',null,'קינוחים',49)
) as v(name_he, name_translit, description, section, price);

-- ---------------------------------------------------------------------------
-- PRE-COMPUTED NUTRITION ESTIMATES (Claude Opus 4.8, seed-time).
-- Per the user's call: 5 dishes are LEFT OUT here on purpose (Taizu Mung Bean
-- Sheets Salad + Butter Chicken; Goocha Fish & Chips + Salmon Fillet; M25
-- Hamburger) so the live Haiku `estimate-dishes` path can be tested on them.
-- The other 81 are filled here. Matched to dishes by (place_id, name_he), so it
-- runs in the same transaction right after the inserts above. Ranges are typical
-- single Israeli/Middle-Eastern servings. model='claude-opus-4-8' marks these as
-- seed-time (the live app uses Haiku for anything not already cached).
-- ---------------------------------------------------------------------------
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
  -- TAIZU
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','לחמניות מאודות',220,340,6,10,30,45,4,8,7,14,array['vegetarian','steamed'],'Two steamed bao buns with yogurt and eggplant, mostly refined flour with a little dairy and oil'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','טרטר טאיזו',90,150,6,10,8,14,1,3,4,9,array['seafood','raw'],'A single small fish-tartar rice cone, lean fish on a fried rice cone'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','קונוס קוויאר',110,180,5,9,8,14,1,2,7,13,array['seafood','rich'],'One caviar cone with creme fraiche foam, small but fatty from cream and roe'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','אויסטר טום קא',70,130,4,7,4,8,2,4,4,9,array['seafood'],'A single oyster in coconut tom kah broth, light shellfish with a little coconut fat'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','קארי ואבטיח',60,120,1,3,8,16,6,12,2,6,array['vegan','light'],'Pickled watermelon and melon in green coconut curry, mostly fruit sugars with light fat'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','סשימי טונה בלו-פין',180,280,22,32,6,12,1,3,6,12,array['seafood','raw','high-protein'],'Bluefin tuna sashimi with broth and a little rice, lean high-protein fish'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','קרפצ''יו באנגלי',160,260,14,22,6,12,1,3,8,16,array['seafood','raw'],'Thin local-fish carpaccio with curry-leaf oil and papadam, lean fish with added oil'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','הר גאו',220,340,10,16,28,42,2,5,6,12,array['seafood','dumplings'],'Shrimp dumplings in wheat-tapioca wrappers, protein with a starchy wrapper'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','Green Leaves Salad',180,300,3,6,14,24,8,14,10,20,array['vegetarian','light'],'Leafy salad with fruit and apple vinaigrette, greens and fruit with dressing oil'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','Wild Fish Ceviche',150,240,16,24,6,12,2,5,6,12,array['seafood','raw','light'],'Citrus-cured wild fish with coconut and cucumber, lean fish and light'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','Swisschard Pot Stickers',240,360,7,12,30,44,3,6,9,16,array['vegetarian','dumplings','fried'],'Pan-fried chard dumplings with macadamia cream and freekeh, starchy wrappers with nut-cream fat'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','Shrimp Salad',200,320,16,24,12,20,4,8,9,17,array['seafood','high-protein'],'Shrimp with herbs, tamarind and a soft egg, lean protein with dressing'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','Shanghai Dumplings',280,420,16,24,30,44,3,7,10,18,array['meat','dumplings'],'Soup dumplings filled with veal cheek, meat and broth in a wheat wrapper'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','באו טונה אדומה',180,280,10,16,22,32,4,8,6,12,array['seafood'],'One bao bun with red tuna, pumpkin and soft egg, fish and egg in a steamed bun'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','ראמפ סיני',260,400,24,34,6,12,2,5,14,26,array['meat','high-protein','spicy'],'Sliced beef rump in chili oil and soy, fatty beef with chili oil'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','טרטר בקר',220,340,16,24,10,18,2,5,12,22,array['meat','raw','high-protein'],'Two beef-tartar bites with crispy shallots and rice puff, raw beef with added fat'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','סלט קלמרי סיאם',220,340,16,24,16,26,4,8,8,16,array['seafood','spicy'],'Poached calamari with bean noodles, corn and chili oil, lean squid with noodles'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','נמס',120,200,5,9,12,20,1,3,6,12,array['fried'],'One fried spring roll with chicken or tofu and peanuts, fried wrapper and moderate'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','ספייר ריבס רול טלה',320,480,18,28,18,28,5,10,18,30,array['meat','rich'],'Lamb spring roll with tamarind glaze and peanuts, fatty glazed lamb'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','קורמה טלה',200,320,10,16,14,22,3,6,12,22,array['meat','rich'],'One lamb korma crepe with coconut cream, lamb in a rich coconut sauce'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','מסאמן ירקות אורגניים עונתיים',320,480,8,14,30,46,10,18,18,30,array['vegan','rich'],'Seasonal vegetables in coconut massaman with peanuts, vegetables in a rich coconut sauce'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','דניס נאם פלה',380,560,34,48,24,36,4,9,14,26,array['seafood','high-protein'],'Whole steamed sea bream with coconut rice, large lean fish portion plus rice'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','לברק שלם מטוגן',420,620,34,48,10,18,2,5,24,40,array['seafood','fried','high-protein'],'Whole fried sea bass with herbs, large fish portion and fried'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','פפר סטייק וייטנאמי',520,760,34,48,24,38,4,9,28,46,array['meat','high-protein','rich'],'Pepper steak with potatoes, onsen egg and nori toffee, substantial beef main with potatoes'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','נתח מיושן על העצם',250,340,20,28,2,6,0,2,18,28,array['meat','high-protein'],'Aged entrecote per 100g with mushrooms, fatty beef priced by weight'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','Charcoal Corn',380,560,5,9,44,64,28,44,16,28,array['dessert','sweet'],'Polenta cake with potato ice cream and truffle, a rich sweet plated dessert'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','Black Forest',420,620,5,9,44,64,34,50,22,36,array['dessert','sweet'],'Chocolate mousse with coconut cream and berries, a rich chocolate dessert'),
  ('ChIJa9zBe3tLHRURQHbcLSWNU1g','White Pandan Rice',320,480,4,8,44,64,26,42,12,22,array['dessert','sweet'],'Coconut toffee with crispy rice and pandan, a sweet coconut-rice dessert'),
  -- GOOCHA
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Roasted Corno di Toro Pepper',220,340,8,14,12,20,6,12,14,24,array['vegetarian'],'Roasted sweet pepper with cheese and almonds, vegetables with cheese and nut fat'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Fish Ceviche',160,260,16,24,6,12,2,5,7,14,array['seafood','raw','light'],'Citrus-cured fish with olives and onion, lean fish and light'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Red Tuna Tartare',200,300,18,26,6,12,1,4,11,19,array['seafood','raw','high-protein'],'Red tuna tartare with avocado, lean fish with avocado fat'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Seared Baby Squid',180,280,16,24,8,14,2,5,8,16,array['seafood','high-protein'],'Seared squid with tahini and harissa, lean squid with tahini fat'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Beef Fillet Carpaccio Tonnato',240,360,16,24,4,10,1,3,16,28,array['meat','raw'],'Beef carpaccio with tuna aioli and capers, thin beef with a rich aioli'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Fish Tacos',280,440,14,22,26,40,4,8,12,22,array['seafood','fried'],'Crispy fish tacos with chipotle and salsa, fried fish in tortillas'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Garlic & Butter Shrimp',240,380,20,30,4,10,1,3,16,28,array['seafood','high-protein'],'Shrimp in garlic-butter and white wine, lean shrimp with butter'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Crab Meat with Mascarpone Agnolotti',360,540,16,24,36,52,3,7,16,28,array['seafood','pasta'],'Crab-filled agnolotti in beurre blanc, pasta with crab and a butter sauce'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Shrimp with Spicy Tomato Salsa',200,320,20,30,8,14,4,8,8,16,array['seafood','spicy','high-protein'],'Shrimp in spicy tomato salsa with olive oil, lean shrimp and light sauce'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Seafood Mix Garlic-Butter',280,440,24,36,6,12,1,4,16,30,array['seafood','high-protein'],'Mixed seafood in garlic-butter, assorted shellfish with butter'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Seafood Curry',360,540,22,34,40,58,6,12,12,24,array['seafood','rich'],'Seafood in coconut curry with rice, shellfish with coconut and a rice portion'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Easy Peel Shrimp Platter',300,460,30,44,8,16,3,7,14,26,array['seafood','high-protein','shareable'],'Plancha-seared shell-on shrimp platter, large lean-protein portion'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Cheeseburger',750,1050,35,50,55,80,8,14,40,62,array['meat','fried','rich'],'Beef cheeseburger with cheddar and fries, a burger plus a fried side'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Roasted Chicken in Red Curry',420,620,30,44,22,36,6,12,18,32,array['meat','high-protein'],'Roast chicken in red coconut curry, chicken in a rich curry sauce'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Skillet Chicken',480,700,34,50,30,46,3,7,22,38,array['meat','high-protein'],'Skillet chicken with potatoes and green beans, chicken with a starchy side'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Beef Fillet (aged in house)',520,760,38,54,4,10,1,4,36,58,array['meat','high-protein','rich'],'Aged beef fillet in demi-glace cream sauce, lean cut with a rich cream sauce'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','The Diner''s Veal Spare Ribs',680,980,38,54,30,46,10,18,38,60,array['meat','rich'],'BBQ-glazed veal spare ribs with roasted potatoes, fatty ribs plus potatoes'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Monday Evening Mussel Special',650,950,28,42,60,90,4,10,22,40,array['seafood','shareable'],'Half-kilo mussels with fries and a beer, shellfish plus a fried side and beer carbs'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Fried Calamari',320,480,16,24,24,38,1,4,16,28,array['seafood','fried'],'Fried calamari with aioli, battered squid and fried'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Crab Bisque',220,360,8,14,14,24,4,9,12,22,array['seafood','soup'],'Creamy crab bisque, a rich cream-based shellfish soup'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Shrimp Roll Brioche',380,560,18,28,32,48,5,10,18,30,array['seafood'],'Toasted brioche filled with chopped shrimp and aioli, shrimp roll with a buttery bun'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Crispy Black Cod',260,400,18,26,10,18,2,5,14,26,array['seafood'],'Crispy black cod wrapped in lettuce with nam jim, fatty fish lightly wrapped'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Garlic Bread',280,440,6,10,36,54,2,5,12,22,array['vegetarian','carb-heavy'],'Garlic bread, refined bread with garlic butter'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Sourdough Bread',240,380,6,10,36,54,2,5,8,16,array['vegetarian','carb-heavy'],'Sourdough with romesco and garlic confit, bread with an oil-based dip'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Leafy Green Mix Salad',220,360,8,14,12,22,6,12,14,26,array['vegetarian','light'],'Leafy salad with goat cheese and almonds, greens with cheese nuts and dressing'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Caesar',320,480,10,16,16,26,2,5,22,36,array['vegetarian'],'Caesar salad, romaine with creamy dressing croutons and cheese'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Caesar Salad with Shrimp Tempura',460,660,22,32,28,42,3,7,26,42,array['seafood'],'Caesar topped with tempura shrimp, Caesar plus battered fried shrimp'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Pulpo',320,480,22,32,12,22,6,12,16,28,array['seafood','high-protein'],'Seared octopus over leaves with goat cheese and fruit, lean octopus with cheese'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Crab Meat and Avocado',300,460,14,22,8,16,3,7,22,36,array['seafood'],'Crab and avocado with mustard aioli on greens, crab with avocado and aioli fat'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Mussels & Fries Mariniere',560,820,26,40,55,82,4,9,20,36,array['seafood','shareable'],'Half-kilo mussels in white-wine butter with fries, shellfish plus a fried side'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Gnocchi with Sea Bream Fillet',480,700,22,32,48,70,3,7,20,34,array['seafood','pasta'],'Potato gnocchi with sea bream in garlic-butter, starchy gnocchi with fish and butter'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Seafood Pasta',520,760,24,36,60,86,5,11,16,30,array['seafood','pasta'],'Seafood pasta in tomato or cream sauce, a pasta portion with mixed seafood'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Shrimp & Crab Meat Pasta',560,800,26,38,58,84,4,9,20,34,array['seafood','pasta'],'Pasta with shrimp and crab in cream sauce, pasta with shellfish and cream'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Whole Sea Bream',380,560,38,54,6,14,1,4,18,32,array['seafood','high-protein'],'Whole sea bream fried or plancha, a large lean-fish portion'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Miso Black Cod',460,680,30,44,36,52,8,16,22,38,array['seafood','rich'],'Miso black cod with coconut rice, fatty fish with a sweet glaze and rice'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Sea Bass Fillet',360,540,30,44,14,24,3,7,18,32,array['seafood','high-protein'],'Sea bass fillet with roasted vegetables and goat-cheese cream, lean fish with a creamy side'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Red Tuna Steak',360,540,34,48,18,30,6,12,14,26,array['seafood','high-protein'],'Seared tuna in soy-yuzu caramel with puree, lean tuna with a sweet glaze and puree'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Sea Bream Fillet',320,480,30,44,10,18,2,5,16,28,array['seafood','high-protein'],'Baked sea bream fillet with zucchini and breadcrumbs, lean fish with light sides'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Sea Bream & Shrimp Duet',380,560,32,46,10,18,2,6,18,32,array['seafood','high-protein'],'Sea bream with shrimp in cream sauce, lean fish and shrimp with cream'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Lemon Cream Meringue',360,520,5,9,42,62,32,48,16,28,array['dessert','sweet'],'Lemon cream with meringue and pistachio crumble, a sweet citrus dessert'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Chocolate Sundae',460,660,6,10,52,74,40,58,22,36,array['dessert','sweet'],'Brownie with ice cream and white chocolate ganache, a rich chocolate sundae'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Belgian Waffle',520,740,7,12,64,90,36,54,22,38,array['dessert','sweet'],'Belgian waffle with caramelized banana and vanilla ice cream'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Tiramisu',360,520,6,10,36,54,26,40,18,30,array['dessert','sweet'],'Classic tiramisu with mascarpone and coffee'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Coconut Malabi Pudding',280,420,3,6,40,58,28,44,10,18,array['dessert','sweet'],'Coconut milk pudding with mango and berry sauce'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Chocolate Mousse with Peanut Crumble',420,600,6,10,40,58,30,46,24,38,array['dessert','sweet'],'Chocolate mousse with peanut crumble and white chocolate sauce'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Creme Brulee',320,460,5,9,30,44,26,40,18,30,array['dessert','sweet'],'Classic vanilla creme brulee, a rich custard dessert'),
  ('ChIJKbk7OXxLHRURxs6enNzWz5E','Sundae with Berries',360,540,4,8,44,64,32,48,14,26,array['dessert','sweet'],'Ice cream sundae with berries, waffle cream and amarena'),
  -- M25
  ('ChIJVai3i4RMHRURFQepMWKweY8','עראייס',380,560,18,28,30,46,2,5,18,32,array['meat','grilled'],'Grilled pita stuffed with spiced minced meat, meat in a flatbread'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','שווארמה מעושנים',420,620,26,38,30,46,2,5,22,38,array['meat','high-protein'],'Smoked shawarma, spiced fatty meat typically served with pita and sides'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','קבב שוק',420,620,24,36,20,34,2,5,26,44,array['meat','grilled','high-protein'],'Grilled minced-meat kebab, fatty seasoned meat skewers'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','סלט ירוק',120,220,3,6,10,18,4,8,7,15,array['vegetarian','vegan','light'],'Simple green salad with dressing, vegetables and oil'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','סלט טחינה עגבניות',160,260,5,9,12,20,5,10,10,18,array['vegetarian','vegan'],'Tomato salad with tahini, vegetables with sesame tahini fat'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','קורנביף',320,480,22,32,6,12,1,4,22,38,array['meat','high-protein'],'House corned beef, cured fatty beef portion'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','לשון פרה',280,420,18,26,2,6,0,2,22,36,array['meat','high-protein'],'Braised cow tongue, a rich fatty offal cut'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','לב שור',220,340,24,34,2,6,0,2,12,22,array['meat','high-protein'],'Grilled ox heart, lean muscular offal high in protein'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','טרטר פריז',260,400,18,26,6,12,1,3,18,30,array['meat','raw','high-protein'],'Paris-style beef tartare, raw seasoned beef with added fat'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','סלט קצבים',300,460,16,24,10,18,3,7,20,34,array['meat'],'Butchers salad with assorted meats over greens, a meat-heavy salad'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','אנטריקוט',250,340,19,26,0,2,0,1,19,28,array['meat','high-protein'],'Entrecote steak per 100g, well-marbled fatty beef'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','על העצם',240,330,18,26,0,2,0,1,18,27,array['meat','high-protein'],'Bone-in steak per 100g, a fatty beef cut priced by weight'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','צלע / אוכף טלה',280,380,16,24,0,2,0,1,24,34,array['meat','high-protein'],'Lamb rib or saddle per 100g, a fatty lamb cut'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','מבחר שיפודים',220,320,18,26,2,6,0,2,14,26,array['meat','grilled','high-protein'],'Assorted grilled meat skewers per 100g, mixed lean and fatty cuts'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','מוס שוקולד',320,480,4,8,32,48,26,40,18,30,array['dessert','sweet'],'Chocolate mousse, a rich sweet dessert with cream and chocolate'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','קראק פאי',380,560,4,8,48,70,36,54,18,32,array['dessert','sweet'],'Crack pie, a very sweet buttery sugar pie'),
  ('ChIJVai3i4RMHRURFQepMWKweY8','מלבי',220,340,3,6,36,54,26,42,6,12,array['dessert','sweet'],'Malabi milk pudding with syrup, a sweet milk-starch pudding')
) as e(place_id, name_he, cl, ch, pl, ph, cbl, cbh, sl, sh, fl, fh, tags, reasoning)
  on e.place_id = r.place_id and e.name_he = d.name_he
on conflict (dish_id) do nothing;

commit;

-- Sanity check after commit:
-- select r.name, m.source, m.source_url, m.verified, count(d.*) as dishes
-- from restaurants r join menus m on m.restaurant_id = r.id
-- left join dishes d on d.menu_id = m.id
-- where m.source = 'claudecode'
-- group by r.name, m.source, m.source_url, m.verified order by r.name;
