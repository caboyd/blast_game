# Weapon System: Chain Destroy

Type: AFK

Blocked by: None - can start immediately (follows pattern from `issues/008-automatic-laser-power-system.md`)

Parent: `issues/008-automatic-laser-power-system.md`

Triage: needs-triage

User stories covered:
- As a player, I can unlock Chain Destroy as a global weapon system.
- As a player, destroying or heavily damaging a block can propagate instant destruction to neighboring blocks during a weapon event.
- As a player, propagation remains fair and bounded.

## What to build

**Chain Destroy** is distinct from **Explosive Blocks** (`issues/010-explosive-block-effect-system.md`): it is an **active weapon proc** on a cooldown (like Laser), not a passive on-any-destruction effect.

Baseline slice:

- Lead ship only, periodic trigger when unlocked.
- Pick a seed solid in range (no drill filter).
- Apply weapon damage; on **break** or as part of the same weapon tick, **propagate** full or partial destruction to **adjacent** solid cells (4-neighbor or 8-neighbor — pick one and document).

Enforce a **per-event cap** on extra cells destroyed (and optionally minimum HP threshold) so dense seams do not wipe the map in one frame. All propagated breaks must use **`MiningWorld`** normal destruction flow.

Visual: brief flash or crack propagation along destroyed cells.

## Acceptance criteria

- [ ] Prep `Weapon Systems` includes Chain Destroy; money, `UpgradeBus`, and save work globally.
- [ ] Lead ship only; followers excluded.
- [ ] One weapon event can destroy **more than one** cell when layout allows, with a clear documented cap.
- [ ] No reliance on drill allowlists for seed or propagated cells.
- [ ] Propagation does not bypass rewards, `block_broken`, fuel, or discovery.
- [ ] Behavior and UX are clearly different from passive explosive procs in issue 010.
- [ ] Smoke test for upgrade id registration / purchase.

## Blocked by

None - can start immediately
