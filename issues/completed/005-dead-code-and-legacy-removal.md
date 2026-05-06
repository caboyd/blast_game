# Dead Code And Legacy Removal

Type: AFK

Blocked by: None - can start immediately

Goal:
- Remove code and resources that are no longer reachable from the main game flow.
- Separate true dead code from legacy compatibility paths that need an explicit save/test/product decision.
- Keep changes small enough that agents can work through one slice at a time.

## Agent Instructions

- Make one ranked slice per PR/change unless the slice is trivial and isolated.
- Before deleting anything, run a repo-wide reference check for the exact symbol/path across `.gd`, `.tscn`, `.tres`, `.godot`, tests, and issue docs.
- Treat tests as usage. If a legacy file is test-only, update or remove the test coverage in the same slice.
- Do not remove compatibility code for saves unless the slice explicitly says save compatibility can be dropped.
- After each slice, run the Godot smoke/test scene if available and at least one static reference search for deleted paths.

## Ranked Removal Slices

### 1. Remove Orphan HPBar

Paths:
- `scenes/ui/HPBar.tscn`
- `scripts/ui/HPBar.gd`

Evidence:
- `HPBar`, `hp_bars`, and `HPBar.tscn` only reference these files themselves.
- No scene, preload, autoload, or script uses this component.

Acceptance criteria:
- [ ] Both files are deleted.
- [ ] Repo-wide search for `HPBar`, `hp_bars`, and `HPBar.tscn` has no remaining production references.
- [ ] Project loads without missing-resource errors.

### 2. Remove Dead GameSession Fields And Hook

Paths:
- `scripts/systems/GameSession.gd`

Targets:
- `mounted_turrets`
- `next_planet_scene`
- stale comment that says Prep calls `go_to_planet(GameSession.next_planet_scene)`
- `on_ship_destroyed()`

Evidence:
- `mounted_turrets` is only declared.
- `next_planet_scene` is only declared/commented; Prep now uses `get_stage_planet_scene_path()`.
- `on_ship_destroyed()` is never called; current mission end paths call `end_current_run_to_prep()` directly.

Acceptance criteria:
- [ ] Targets are removed.
- [ ] `GameSession.get_stage_planet_scene_path()`, `begin_run()`, and `end_current_run_to_prep()` still work.
- [ ] Repo-wide search for removed names has no hits.

### 3. Remove Unused MiningMissionUI Top-Band API

Paths:
- `scripts/systems/MiningMissionUI.gd`

Targets:
- `top_fuel_layout_changed` signal
- emissions/dirty notification that only serve that signal, if no remaining callers need them
- `get_top_fuel_band_px()`
- stale comments about planet scenes re-reading the top fuel band

Evidence:
- No code connects to `top_fuel_layout_changed`.
- No code calls `get_top_fuel_band_px()`.
- Planet layout now uses fullscreen overlay offsets rather than reserving top/bottom HUD bands.

Acceptance criteria:
- [ ] Unused signal/API is removed or simplified.
- [ ] `attach_fuel_bar_for_mining_host()` still attaches `TopMiningRunHud`.
- [ ] `ResourceFoundOverlay` still compiles after any notification cleanup.
- [ ] Repo-wide search for removed names has no hits.

### 4. Remove Dead Pickup Mark API

Paths:
- `scripts/systems/PartRegistry.gd`

Targets:
- `mark_pickup_collected(pickup_id)`

Evidence:
- No call sites found.
- Current pickup collection uses `mark_once_part_pickup()` and `GameSession.mark_part_pickup_collected()`.

Acceptance criteria:
- [ ] `mark_pickup_collected()` is removed.
- [ ] `is_pickup_collected()` remains if still used by `should_skip_spawn_for_pickup_def()`.
- [ ] Part pickups still collect once and persist across career save/load.

### 5. Remove Unused Click-Fire Constants

Paths:
- `scripts/stats/GameStatistics.gd`
- optionally update stale comments in `scripts/systems/UpgradeBus.gd`

Targets:
- `DAMAGE_SOURCE_CLICK`
- `CLICK_FIRE_RATE_START_MS`
- `CLICK_FIRE_RATE_MIN_MS`
- `CLICK_FIRE_RATE_STEP`
- stale `UpgradeBus` header text about legacy combat/click defs staying in code

Evidence:
- Click constants are defined but never referenced.
- `UpgradeBus` now routes upgrade definitions through `ShipDataRegistry`.

Acceptance criteria:
- [ ] Unused constants are removed.
- [ ] `UpgradeBus` comments match the current registry-backed implementation.
- [ ] Repo-wide search for removed names has no hits.

### 6. Remove Unused Optional APIs If Product Agrees

Paths:
- `scripts/world/MiningWorld.gd`
- `scripts/ui/BottomPlayerStatsStrip.gd`
- `scripts/ui/BottomHUD.gd` if still present
- `scripts/systems/AudioManager.gd`
- `scripts/stats/GameStatistics.gd`

Targets:
- `MiningWorld.set_fog_shader_colors(mid, dark)`
- `get_occlusion_bottom_reserve_px()` and private fallback helpers
- `AudioManager.set_overall_volume()`
- `AudioManager.set_sfx_volume()`
- `GameStatistics.clear_mining_mission_vehicle_debug_overrides()`

Evidence:
- No in-repo callers found for these APIs.

Risk:
- These may be intentional future/editor-facing APIs. Remove only if the product decision is to keep the codebase minimal over preserving future hooks.

Acceptance criteria:
- [ ] Product decision is recorded in the PR/commit message.
- [ ] Removed names have no remaining references.
- [ ] Current debug overlay, audio, fog, and bottom stats strip behavior are unchanged.

## Legacy / Replaced Systems Requiring Decisions

### A. Old BottomHUD Cluster

Paths:
- `scenes/ui/BottomHUD.tscn`
- `scripts/ui/BottomHUD.gd`
- `scenes/ui/StatItem.tscn`
- `scripts/ui/StatItem.gd`
- `scenes/ui/UpgradeItem.tscn`
- `scripts/ui/UpgradeItem.gd`
- `scripts/ui/ResponsiveGrid.gd`
- `resources/ui/hud_style_outer.tres`
- `resources/ui/hud_style_inner.tres`
- `resources/ui/hud_style_section.tres`
- `resources/ui/hud_style_inner_flat.tres`
- `resources/ui/hud_style_item.tres`
- `resources/ui/hud_style_buy_button.tres`

Replacement:
- Mining uses `TopMiningRunHud`, `MiningMissionUI`, and `BottomPlayerStatsStrip`.
- Prep uses its own inline shop/stats UI.

Evidence:
- Main scenes do not instantiate `BottomHUD`.
- `tests/upgrade_effects_smoke.gd` still preloads and instantiates `BottomHUD`.
- `issues/completed/004-fullscreen-mining-layout.md` explicitly said to keep the old files for then-current work.

Decision needed:
- Either keep the cluster as test-only legacy coverage, or delete/update the smoke test and remove the cluster.

Acceptance criteria if removing:
- [ ] Smoke test is updated to cover current Prep/top/bottom overlay systems instead of `BottomHUD`.
- [ ] Entire old HUD cluster is deleted.
- [ ] Repo-wide search for old HUD paths/classes has no hits.

### B. Legacy Save Compatibility For Part IDs And Pickup Keys

Paths:
- `scripts/systems/PartRegistry.gd`
- `scripts/systems/GameSession.gd`

Targets:
- `_LEGACY_PART_IDS`
- `_LEGACY_PLANET1_PICKUP_PREFIX`
- `migrate_legacy_pickup_ids_to_game_session_pickup_slots()`
- `_try_migrate_one_legacy_pickup_id_to_game_session()`
- old `_collected_pickups` fallback paths, only if all legacy pickup ids are no longer supported

Replacement:
- Canonical `part_*` ids.
- `GameSession` typed pickup slots keyed by part type, tier, and pickup index.

Evidence:
- Compatibility runs during career load.
- Current pickup flow uses `mark_once_part_pickup()` and typed `GameSession` pickup persistence.

Decision needed:
- Define save policy. If old local saves must keep working, do not remove this slice.

Acceptance criteria if removing:
- [ ] Save compatibility cutoff is documented.
- [ ] Career load no longer calls legacy migration.
- [ ] New-format saves still load equipped parts, part levels, and pickup state.
- [ ] Tests cover canonical save/load without the legacy map.

### C. Legacy PartVisuals Root Cleanup

Paths:
- `scripts/systems/PartVisuals.gd`

Targets:
- `LEGACY_ROOT_NAME`
- `TREADS_ROOT_NAME`
- `UPPER_ROOT_NAME`
- cleanup loop for old visual-root nodes

Replacement:
- `%Attachment_Treads`, `%Attachment_Drill`, and `%Attachment_FuelTank` markers on ship scenes.

Evidence:
- Current ship scenes use attachment markers.
- No repo scenes contain the old root node names.

Decision needed:
- Remove only if old ship scenes/saved instantiated nodes do not need cleanup.

Acceptance criteria if removing:
- [ ] Current `Scout.tscn` and `Prospector.tscn` still receive part visuals through markers.
- [ ] Repo-wide search for old root names has no hits.

### D. Hidden Placeholder Drill Nodes In Ship Scenes

Paths:
- `scenes/ships/Scout.tscn`
- `scenes/ships/Prospector.tscn`

Replacement:
- Runtime part visuals attached by `PartVisuals`.

Decision needed:
- Verify whether hidden `Drill` nodes are still needed for collision, editor positioning, or as marker parents before deleting.

Acceptance criteria if removing:
- [ ] Ship collision/mining still works.
- [ ] Part visuals still attach and preview correctly in Prep and both planet scenes.

## Not Removal Candidates From This Audit

- Autoloads in `project.godot`.
- `data/parts/**` resources loaded by `PartRegistry`.
- `data/ships/**` resources loaded by `ShipDataRegistry`.
- `audio/drill.wav`, `audio/dirtmine.wav`, and `audio/dirtfall.wav`.
- `assets/sprites/crack.png`.
- Shaders under `shaders/`.
- `MiningWorld`, `Planet1`, `Planet2`, `TopMiningRunHud`, `MiningFuelBar`, `DebugOverlay`, `BottomPlayerStatsStrip`, `GenerationMonument`, `MonumentLaserTurret`, `MiningDebrisField`, and part visual/ground pickup scenes.

