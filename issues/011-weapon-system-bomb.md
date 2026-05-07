# Weapon System: Bomb

Type: AFK

Blocked by: None - can start immediately (follows pattern from `issues/008-automatic-laser-power-system.md`)

Parent: `issues/008-automatic-laser-power-system.md`

Triage: needs-triage

User stories covered:
- As a player, I can unlock a global Bomb weapon system in prep under `Weapon Systems` and keep it across vehicles.
- As a player, my unlocked Bomb automatically affects the minefield during runs without using drill type filters.
- As a player, Bomb stays separate from `Vehicle Upgrades` and from `Block Effects` (see `issues/010-explosive-block-effect-system.md`).

## What to build

Add a **Bomb** global weapon: single-level (or thin multi-level if already consistent with Laser) unlock in the power-system registry, listed in prep `Weapon Systems`, purchased with existing money and `UpgradeBus` / career save.

Baseline behavior should mirror the Laser tracer bullet: only the **active lead** `ShipBase` runs the controller; **followers** do nothing. Bombs should damage terrain through the normal **`MiningWorld` destruction / reward path** (money, fuel cells, discovery, stats, `block_broken`), and must **not** apply drill part allowlists.

Define a concrete first fun slice (e.g. periodic arming + **area damage** at a chosen in-range solid cell, with a simple fuse or drop VFX). Document baseline cooldown, radius, and damage constants in the issue or in code next to Laser constants for later balancing.

Child upgrades (damage, radius, cluster count, etc.) are **out of scope** here unless trivial; prefer a follow-up issue patterned on `issues/009-laser-upgrades-and-targeting-modes.md`.

## Acceptance criteria

- [ ] Prep `Weapon Systems` lists Bomb after the unlock is wired; `Vehicle Upgrades` unchanged.
- [ ] Bomb purchase uses `UpgradeBus`, batch rules, and career persistence.
- [ ] Bomb unlock remains available when changing selected ship.
- [ ] During a run, **lead ship only** auto-uses Bomb on a baseline cooldown when unlocked.
- [ ] Bomb damage uses `MiningWorld` APIs that preserve normal economy and signals (no silent terrain clears).
- [ ] Drill part type restrictions do **not** gate Bomb targets or damage.
- [ ] Follower visual-only ships do not create or run Bomb logic.
- [ ] Automated smoke or unit test covers registry + max-level / purchase path for the Bomb upgrade id (same class of checks as Laser in `tests/upgrade_effects_smoke.gd`).
- [ ] Lightweight VFX (pulse, ring, or sprite) makes Bomb readable without heavy new assets.

## Blocked by

None - can start immediately
