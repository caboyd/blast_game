# Systems

This is the living developer/agent-facing map of the current project systems. Keep it in sync with code changes: if a change adds, removes, renames, or meaningfully changes a system, responsibility boundary, lifecycle flow, or cross-system dependency, update this document in the same change.

## How To Read This

A **system** is a top-level responsibility boundary. A **component** is a smaller implementation piece grouped under the system it supports; components are not tracked as separate systems unless they become architectural hubs.

Each system uses the same shape:

- **Purpose**: why the system exists.
- **Owns**: state, behavior, or assets the system is responsible for.
- **Key Files**: primary implementation files and scenes/resources.
- **Collaborates With**: other systems it depends on or notifies.
- **Runtime Flow**: how the system behaves during play.
- **Update When**: changes that should trigger edits to this section.

## Runtime Lifecycle

The project starts in Prep (`res://scenes/prep/Prep.tscn`). Prep loads career state through autoloads, shows ship selection, ship stats, discovered stage data, and upgrade purchases. Starting a mission calls `GameSession.begin_run()`, reloads the active ship, and transitions to `GameSession.next_planet_scene`.

Planet 1 spawns the active ship, attaches it to `MiningWorld`, creates visual-only follower ships for unlocked chain members, starts the mission timer, and activates mission HUD elements. During physics ticks the active ship steers toward the mouse, moves through mineable terrain, mines blocks, drains fuel, and updates fog-of-war vision. Running out of fuel or using debug return ends the run, commits run progress to career state, saves, and returns to Prep.

## System: Session And Persistence

**Purpose**: Own long-lived game/session state that must survive scene changes and disk saves.

**Owns**:

- Selected ship id.
- Next planet scene path.
- Career blocks destroyed and money persistence.
- Upgrade-level persistence delegation.
- Stage block discovery persistence.
- Stage reveal/fog persistence files.
- Mission timer start and elapsed time.
- Run begin/end transitions.

**Key Files**:

- `scripts/systems/GameSession.gd`
- `project.godot` autoload entry for `GameSession`

**Collaborates With**:

- `GameStatistics` for money, fuel reset, run block baseline, and emitted stat updates.
- `UpgradeBus` for loading and writing upgrade levels.
- `ShipDataRegistry` for validating/restoring selected ship data.
- `MiningWorld` for stage reveal load/save and block discovery.
- Prep and planet scenes for scene transitions.

**Runtime Flow**:

On startup, `GameSession` defers career loading so other autoloads are ready. Career load restores total blocks, money, selected ship, upgrade levels, fuel max, and discovered block types. Prep calls `begin_run()` before entering a planet, which resets per-run counters and fuel. Planet scenes call `start_mission_timer()`. When a run ends, `end_current_run_to_prep()` commits this run's block count to career, writes the career file, resets the run baseline, and returns to Prep.

**Update When**:

- Save file sections, keys, or file formats change.
- Run lifecycle changes.
- Scene transition ownership moves.
- New persistent career, stage, or mission state is added.

## System: Ship Data And Registry

**Purpose**: Load authored ship resources, determine active/unlocked ships, expose ship upgrade definitions, and apply upgrade effects to ship stats.

**Owns**:

- Loading all `ShipData` resources from `res://data/ships/`.
- Active ship lookup based on `GameSession.selected_ship_id`.
- Ship ordering in Prep.
- Ship unlock checks.
- Upgrade definition indexing by id.
- Effective and preview stat calculations.

**Key Files**:

- `scripts/systems/ShipDataRegistry.gd`
- `scripts/data/ShipData.gd`
- `scripts/data/ShipUpgradeData.gd`
- `scripts/data/ShipUpgradeEffect.gd`
- `scripts/data/ShipUpgradeMath.gd`
- `data/ships/scout.tres`
- `data/ships/prospector.tres`
- `project.godot` autoload entry for `ShipDataRegistry`

**Collaborates With**:

- `GameSession` for selected ship id.
- `UpgradeBus` for current upgrade levels and max-level checks.
- `GameStatistics` for active ship fuel baseline and reward modifiers.
- Prep for ship picker, stat preview, shop rows, and unlock messaging.
- Planet runtime for spawning active and follower ships.

**Runtime Flow**:

The registry loads ship resources at startup and rebuilds an upgrade id index. Prep and planet scenes ask for the active ship and mission ship chain. Unlocking is currently sequential: Prospector unlocks after every Scout upgrade is maxed. Upgrade effects from every ship's upgrade list apply globally at runtime, while the Prep shop lists only upgrades for the currently selected ship.

**Update When**:

- New ship resources, ship stats, or unlock rules are added.
- Upgrade effect stats or cost math change.
- Upgrade effects stop being global or shop visibility changes.
- Ship data moves out of `.tres` resources.

## System: Upgrades And Economy Purchases

**Purpose**: Centralize upgrade levels, purchase validation, purchase cost calculation, and upgrade purchase events.

**Owns**:

- Current upgrade levels.
- Upgrade affordability/count calculations.
- Max-level enforcement.
- Purchase transactions.
- `upgrade_purchased` signal.
- Reading/writing upgrade levels to career config.

**Key Files**:

- `scripts/systems/UpgradeBus.gd`
- `scripts/data/ShipUpgradeMath.gd`
- `project.godot` autoload entry for `UpgradeBus`

**Collaborates With**:

- `ShipDataRegistry` for upgrade definitions and caps.
- `GameStatistics` for money spend checks.
- `GameSession` for career saving.
- Prep and Bottom HUD purchase UI.
- `GameStatistics` and ship systems that react to purchased upgrades.

**Runtime Flow**:

UI asks `UpgradeBus` how many levels a request can buy and what it costs. `try_purchase_count()` verifies the request, spends money through `GameStatistics`, updates the level dictionary, emits `upgrade_purchased`, and saves career state. Fuel tank upgrades are handled specially by `GameStatistics` so added capacity preserves current fill.

**Update When**:

- Purchase batching, affordability, caps, or refund behavior changes.
- Upgrade levels become per-ship instead of global.
- New systems need to react to upgrade purchases.
- Upgrade persistence changes.

## System: Statistics, Fuel, And Rewards

**Purpose**: Hold mutable gameplay stats and emit change signals for UI and persistence.

**Owns**:

- Total blocks destroyed.
- Per-run block baseline.
- Money.
- Furthest depth.
- Fuel and fuel max.
- Fuel overflow cap behavior.
- Debug world-visual toggle.
- Reward application for mined blocks.

**Key Files**:

- `scripts/stats/GameStatistics.gd`
- `project.godot` autoload entry for `GameStatistics`

**Collaborates With**:

- `GameSession` for career saves and run baselines.
- `ShipDataRegistry` for active ship fuel baseline and stat modifiers.
- `UpgradeBus` for upgrade purchase reactions.
- `MiningWorld` for mined-block rewards and depth updates.
- `ShipBase` and `MonumentLaserTurret` for fuel drain.
- Prep, Bottom HUD, and fuel UI for display.

**Runtime Flow**:

Stats are updated by gameplay actions and emit `stats_changed` and `fuel_changed`. Fuel is reset at run start, drained by the active ship each physics tick, increased by fuel pickups, and capped at an absolute overflow limit. Money is earned from mined cells and can be modified by upgrade effects such as double-money chance.

**Update When**:

- New global or run stats are added.
- Fuel rules, reward rules, or stat signals change.
- Currency persistence or spending behavior changes.
- Debug visualization state moves elsewhere.

## System: Prep

**Purpose**: Provide the out-of-mission planning screen for ship selection, progress review, stage discovery, and upgrade purchasing.

**Owns**:

- Main start-mission action.
- Ship picker and ship preview.
- Ship lock messaging.
- Career/money/depth labels.
- Stage block catalog display.
- Active ship stats display.
- Active ship upgrade shop.
- Debug progress reset button.

**Key Files**:

- `scenes/prep/Prep.tscn`
- `scripts/prep/Prep.gd`

**Collaborates With**:

- `GameSession` for selected ship, career progress, run start, reset, and planet transition.
- `ShipDataRegistry` for ship data, unlock state, previews, and active ship upgrades.
- `GameStatistics` for money, fuel, and progress stats.
- `UpgradeBus` for purchase operations.
- `MiningWorld` for stage block type metadata.
- `ShipChainLayout` for preview follower spacing.

**Runtime Flow**:

Prep initializes tabs, buttons, ship picker, stat listeners, and the active ship preview. Selecting a ship updates session state, reloads active ship data, reapplies the fuel baseline, rebuilds the preview, saves career, and refreshes all UI. Upgrade purchases go through `UpgradeBus`. Starting a mission reloads the active ship, begins a run, and changes to the configured planet scene.

**Update When**:

- Prep tabs, shop behavior, ship selection, or preview rules change.
- New planning-screen responsibilities are added.
- Stage discovery presentation changes.
- Run start preconditions change.

## System: Planet Mission Runtime

**Purpose**: Own the active mining mission scene lifecycle, viewport layout, ship spawning, ship chain followers, and run-ending hooks.

**Owns**:

- Planet id assignment.
- Active ship instantiation.
- Mission ship chain follower instantiation and path following.
- Gameplay viewport sizing around HUD occlusion.
- Mission timer start.
- Out-of-fuel run ending.

**Key Files**:

- `scenes/planets/Planet1.tscn`
- `scripts/planets/Planet1.gd`
- `scripts/systems/ShipChainLayout.gd`

**Collaborates With**:

- `MiningMissionUI` for top fuel-bar visibility and layout.
- `BottomHUD` for bottom occlusion reserve.
- `GameSession` for mission timer and run end.
- `ShipDataRegistry` for active and chained ships.
- `MiningWorld` for terrain attachment and Planet 1 stage content.
- `ShipBase` for active ship behavior and follower visuals.

**Runtime Flow**:

On ready, Planet 1 activates the mission fuel bar, starts the mission timer, applies viewport layout, spawns the active ship and unlocked follower visuals, attaches the ship to `MiningWorld`, moves the ship to the center of chunk `(0, 0)`, stamps a starting dirt area, carves hull terrain, and connects run-ending/layout signals. A helper tick node updates follower ships from the active ship's sampled path.

**Update When**:

- New planet scenes share or replace Planet 1 behavior.
- Ship chain following changes.
- Gameplay viewport/HUD layout ownership changes.
- Mission start or end flow changes.

## System: Ships And Mining Interaction

**Purpose**: Define playable mining ship behavior and the interface between ships, terrain, fuel, upgrades, and vision.

**Owns**:

- Active ship steering and movement.
- Hull and drill shape resolution.
- Effective stat accessors.
- Mining tick timing and pending damage.
- Fuel drain and out-of-fuel signal.
- Terrain collision/mining integration.
- Ship-specific scene roots via subclasses.
- Visual-only follower mode.

**Key Files**:

- `scripts/ships/ShipBase.gd`
- `scripts/ships/Scout.gd`
- `scenes/ships/Scout.tscn`
- `scenes/ships/Prospector.tscn`

**Collaborates With**:

- `ShipDataRegistry` for base stats and upgrade effects.
- `MiningWorld` for terrain collision, mining, spawn carving, and vision.
- `GameStatistics` for fuel drain and debug visuals.
- Planet runtime for spawning and follower updates.
- Prep for previewing effective stats.

**Runtime Flow**:

The active ship loads current `ShipData` in `_ready()`, resolves its hull and drill collision shapes, and creates a debug draw layer. Each physics tick it rotates toward the mouse, attempts movement through terrain, mines through its drill, drains fuel, updates vision, and emits `out_of_fuel` once fuel reaches zero. Follower ships skip gameplay processing and act as visuals only.

**Update When**:

- Ship movement, mining, collision, fuel drain, or vision rules change.
- Ship scene requirements change.
- New ship base stats or effective stat accessors are added.
- Follower visuals gain gameplay behavior.

## System: Mining World And Stage Content

**Purpose**: Own the mineable grid, chunk generation, terrain damage, rewards, fog-of-war, stage reveal persistence, and Planet 1 static content.

**Owns**:

- Chunked cell storage.
- Block type ids, HP, money values, colors, and stage catalog rows.
- Procedural dirt/stone/gold/fuel/ruby generation.
- Static cell overrides.
- Planet 1 generation monument stamping and attachment.
- Terrain damage and clearing.
- Hull/mining overlap checks.
- Vision reveal updates.
- Visual textures for world and fog.
- Debounced reveal persistence.

**Key Files**:

- `scripts/world/MiningWorld.gd`
- `scenes/world/MiningWorld.tscn`
- `scripts/world/GenerationMonument.gd`
- `scripts/world/MonumentLaserTurret.gd`

**Collaborates With**:

- `GameSession` for reveal load/save and block discovery.
- `GameStatistics` for block counts, rewards, fuel pickups, and depth.
- `ShipBase` for mining, collision, and vision calls.
- Planet runtime for stage id, ship attachment, and start-area stamping.
- Prep for stage block catalog metadata.

**Runtime Flow**:

Chunks are generated lazily from the stage seed and chunk coordinate. Mining and collision APIs ensure chunks exist, mutate cell HP/type data, apply rewards or fuel pickup effects, mark block types discovered, and dirty visuals/reveal state. Vision writes reveal masks and saves them through `GameSession` after a debounce. Planet 1 includes a generation monument that spawns laser turrets; turrets pulse periodically and drain ship fuel when in range.

**Update When**:

- Block types, generation rules, rewards, HP, or colors change.
- Fog/reveal persistence changes.
- Stage-specific content is added or moved out of `MiningWorld`.
- Mining/collision API contracts change.

## System: HUD And UI Components

**Purpose**: Display live mission/prep state and expose player controls for upgrades, fuel visibility, debug controls, and responsive layout.

**Owns**:

- Bottom mission HUD stats and upgrade cards.
- Top mission fuel bar.
- Prep and mission responsive grids.
- Reusable stat and upgrade UI components.
- HP bar drawing utility.
- Debug overlay controls.

**Key Files**:

- `scripts/ui/BottomHUD.gd`
- `scenes/ui/BottomHUD.tscn`
- `scripts/systems/MiningMissionUI.gd`
- `scenes/ui/MiningFuelBar.tscn`
- `scripts/ui/MiningFuelBar.gd`
- `scripts/ui/UpgradeItem.gd`
- `scenes/ui/UpgradeItem.tscn`
- `scripts/ui/StatItem.gd`
- `scenes/ui/StatItem.tscn`
- `scripts/ui/ResponsiveGrid.gd`
- `scripts/ui/HPBar.gd`
- `scripts/ui/DebugOverlay.gd`
- `scenes/ui/DebugOverlay.tscn`

**Collaborates With**:

- `GameStatistics` for stats and fuel signals.
- `GameSession` for mission time and debug return-to-prep.
- `UpgradeBus` for purchase state and purchases.
- `ShipDataRegistry` for upgrade definitions.
- Planet runtime for HUD occlusion and fuel-bar layout.
- `MiningWorld`/ship debug drawing through `GameStatistics.debug_world_visuals`.

**Runtime Flow**:

Bottom HUD builds stat and upgrade components from config and refreshes when stats or fuel changes. It reports bottom occlusion so Planet 1 can keep gameplay inside the visible area. `MiningMissionUI` is an autoload that owns a fuel bar and shows it while a mining scene is active. `DebugOverlay` toggles debug visuals, grants money, and can return the current run to Prep.

**Update When**:

- HUD stats, upgrade cards, fuel display, or layout behavior changes.
- UI components become shared by new systems.
- Debug controls change or move.
- Mission viewport occlusion rules change.

## System: Projectiles And Combat Support

**Purpose**: Hold current projectile/explosion support code used by combat-style entities.

**Owns**:

- Generic projectile movement/lifetime.
- Cannon projectile configuration, collision substeps, detonation, and explosion FX spawn.
- Cannon explosion visual effect.

**Key Files**:

- `scripts/projectiles/Projectile.gd`
- `scripts/projectiles/CannonProjectile.gd`
- `scripts/projectiles/CannonExplosionFX.gd`

**Collaborates With**:

- Nodes in the `enemies` group that implement the expected enemy API.
- Future/current turret code that configures cannon projectiles.

**Runtime Flow**:

Generic projectiles move along a configured direction until their lifetime expires. Cannon projectiles override movement to substep collision checks against enemy nodes, detonate on hit, apply area damage, spawn an explosion FX node, and free themselves. The current repository does not contain a top-level combat system around these components.

**Update When**:

- Enemy, turret, projectile, or explosion ownership becomes active gameplay.
- Combat entities are added as a top-level system.
- Projectile collision or damage contracts change.

## Autoloads

The following systems are globally available through Godot autoloads configured in `project.godot`:

- `GameSession`
- `ShipChainLayout`
- `ShipDataRegistry`
- `UpgradeBus`
- `GameStatistics`
- `MiningMissionUI`

## Current Scenes

- `scenes/prep/Prep.tscn`: main scene and planning screen.
- `scenes/planets/Planet1.tscn`: active mining mission scene.
- `scenes/world/MiningWorld.tscn`: mineable terrain component.
- `scenes/ships/Scout.tscn`: Scout ship scene.
- `scenes/ships/Prospector.tscn`: Prospector ship scene.
- `scenes/ui/*.tscn`: HUD, fuel, stat, upgrade, HP, and debug UI components.

## Tests

Current smoke coverage lives in:

- `tests/UpgradeEffectsSmoke.tscn`
- `tests/upgrade_effects_smoke.gd`

These tests focus on upgrade/effective-stat behavior. Broader system interaction coverage is not currently represented in tests.
