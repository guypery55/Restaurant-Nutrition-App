-- Session 8 (v3) — estimate trust & accuracy: catalog audit
-- ============================================================================
-- WHAT THIS IS
--   A read-only audit of every row in dish_estimates. It flags estimates that
--   look internally incoherent so we can decide whether to re-estimate them.
--   No writes — safe to run any time. Reused by Session 11's metrics view.
--
-- THE CORE CHECK — macro↔calorie self-consistency
--   Real food obeys the Atwater identity: calories ≈ 4·protein + 4·carbs + 9·fat.
--   We compute, per estimate, the reconciliation error between the reported
--   calorie midpoint and the macro-implied calories, as a fraction of calories:
--       recon_err = |cal_mid − (4P + 4C + 9F)| / cal_mid
--   and the calorie range width relative to the midpoint:
--       cal_width = (calories_high − calories_low) / cal_mid
--
-- TWO PRINCIPLED EXEMPTIONS (why a naive check false-flags)
--   1. ALCOHOL — ethanol is ~7 cal/g and is NOT one of the 4/4/9 macros, so an
--      alcoholic drink's calories legitimately exceed its macro sum. A beer at
--      60 kcal / ~3 g carbs "reconciles" to ~14 kcal — a false positive.
--   2. NEAR-ZERO items (< 30 kcal) — diet sodas, water, tiny garnishes. At that
--      scale the identity is meaningless: a 2-vs-3 kcal gap reads as 33% error
--      and a 0–5 kcal range reads as 200% width. Denominator noise, not error.
--   These are classified out below (category <> 'real_food') and excluded from
--   the "needs review" verdict — matching the estimator's own exemptions.
--
-- TOLERANCES (Session 8, calibrated against the live catalog 2026-07-01)
--   real food: recon_err > 0.20  → inconsistent
--   real food: cal_width > 1.00  → absurdly wide
--   Baseline the day this was written: 251 estimates, median recon_err 3.1%,
--   median cal_width 37.6% (≈ ±19%, already at the ±15-20% target). Every flier
--   over tolerance was alcohol or near-zero — ZERO real-food estimates needed a
--   fix. If that ever stops being true, the offenders surface as 'real_food'
--   rows in the detail query below.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Shared computation: one row per estimate, with category + error metrics.
-- (Copy this CTE into the summary or detail query below, or wrap in a view.)
-- ---------------------------------------------------------------------------
with scored as (
  select
    de.dish_id,
    r.name  as restaurant,
    d.name_he,
    d.section,
    de.calories_low, de.calories_high,
    de.tags,
    (de.calories_low + de.calories_high) / 2.0 as cal_mid,
    (de.protein_low  + de.protein_high)  / 2.0 as prot_mid,
    (de.carbs_low    + de.carbs_high)    / 2.0 as carb_mid,
    (de.fat_low      + de.fat_high)      / 2.0 as fat_mid,
    4 * (de.protein_low + de.protein_high) / 2.0
      + 4 * (de.carbs_low + de.carbs_high) / 2.0
      + 9 * (de.fat_low   + de.fat_high)   / 2.0 as macro_cal,
    case
      when de.tags && array['beer','wine','cider','alcohol','alcoholic',
                            'light-alcohol','cocktail','spirits']
        then 'alcohol'
      when (de.calories_low + de.calories_high) / 2.0 < 30
        then 'near_zero'
      else 'real_food'
    end as category
  from dish_estimates de
  join dishes      d on d.id = de.dish_id
  join menus       m on m.id = d.menu_id
  join restaurants r on r.id = m.restaurant_id
),
metrics as (
  select *,
    case when cal_mid > 0 then abs(cal_mid - macro_cal) / cal_mid end as recon_err,
    case when cal_mid > 0 then (calories_high - calories_low) / cal_mid end as cal_width,
    -- The verdict: only REAL FOOD outside tolerance needs review. Alcohol and
    -- near-zero are expected to "fail" the naive identity and are left alone.
    (
      category = 'real_food'
      and cal_mid > 0
      and (abs(cal_mid - macro_cal) / cal_mid > 0.20
           or (calories_high - calories_low) / cal_mid > 1.00)
    ) as needs_review
  from scored
)

-- ---------------------------------------------------------------------------
-- SUMMARY — the headline health of the catalog.
-- ---------------------------------------------------------------------------
select
  count(*)                                          as total_estimates,
  count(*) filter (where category = 'real_food')    as real_food,
  count(*) filter (where category = 'alcohol')      as alcohol_exempt,
  count(*) filter (where category = 'near_zero')    as near_zero_exempt,
  round(avg(recon_err)  filter (where category = 'real_food'), 3) as avg_recon_err_food,
  round((percentile_cont(0.5) within group (order by recon_err)
         filter (where category = 'real_food'))::numeric, 3)      as median_recon_err_food,
  round((percentile_cont(0.5) within group (order by cal_width)
         filter (where category = 'real_food'))::numeric, 3)      as median_cal_width_food,
  count(*) filter (where needs_review)              as needs_review
from metrics;

-- ---------------------------------------------------------------------------
-- DETAIL — the actual estimates that need a human (real food, out of tolerance).
-- If this returns 0 rows, the catalog is coherent and no re-estimation is due.
-- Re-run the SAME `with scored ... metrics ...` CTE above before this SELECT.
-- ---------------------------------------------------------------------------
-- select restaurant, name_he, section, round(cal_mid,0) as cal_mid,
--        round(macro_cal,0) as macro_cal, round(recon_err,2) as recon_err,
--        round(cal_width,2) as cal_width, tags
-- from metrics
-- where needs_review
-- order by recon_err desc nulls last;
