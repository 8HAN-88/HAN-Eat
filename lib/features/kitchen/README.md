# Kitchen (HAN Eat) — quarantine folder

Everything under `lib/features/kitchen/` is **recipe / nutrition / meal-plan / shopping / AI food scan** code for the HAN Eat (`AppVariant.kitchen`) product.

The messenger (HanWe, `AppVariant.social`) still wires some of this in for now (routes, bootstrap, feed/channel recipe composers). This folder exists so kitchen code can be deleted in one cut without hunting through the tree.

## Layout

| Path | Contents |
|------|----------|
| `menu/` | Recipe search, create recipe, AI scan result |
| `meal_plan/` | Meal plan UI + AI plan |
| `shopping/` | Shopping list |
| `categories/` | Recipe categories |
| `favorites/` | Favorite recipes |
| `recipe_detail/` | Recipe detail, cooking mode, by-id |
| `diet/` | Diet & allergies screens |
| `ai_scan/` | Analysis mode controller |
| `data/` | Models, services, mock recipes |
| `domain/` | Nutrition helpers, cuisine countries, access rules |
| `presentation/widgets/` | Recipe cards, nutrition form, visibility, scan credits |

## How to remove kitchen and ship a pure messenger

1. Delete this directory: `lib/features/kitchen/`.
2. Delete entrypoint `lib/main_kitchen.dart` (and any kitchen flavor / `APP_VARIANT=kitchen` build config).
3. Strip kitchen routes and imports from `lib/app/app_router.dart`.
4. Stop initializing kitchen services in `lib/app/bootstrap.dart`, `lib/widgets/services_ready_gate.dart`, and `lib/core/storage/hive_bootstrap.dart`.
5. Remove recipe composers / `DetailPage` openers from feed, posts, and channels (or gate them permanently behind `AppVariant.kitchen` and then delete).
6. Drop kitchen-only API helpers from `lib/services/api_service.dart` and kitchen tests under `test/` (`recipe_*`, `shopping_*`, `favorites_*`, `meal_plan_*`, `mock_recipes_*`, `scan_recipe_*`).
7. Optionally remove `AppVariant.kitchen` from `lib/core/app/app_variant.dart`.

After that, the app should be HanWe messenger only.
