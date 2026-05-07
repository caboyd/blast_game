# Weapon System: Chain Lightning

Type: AFK

Blocked by: None - can start immediately (follows pattern from `issues/008-automatic-laser-power-system.md`)

Parent: `issues/008-automatic-laser-power-system.md`

Triage: needs-triage

User stories covered:
- As a player, I can unlock Chain Lightning as a global weapon system in `Weapon Systems`.
- As a player, lightning strikes chain between nearby blocks during mining runs.
- As a player, each hop respects normal mining rewards and stats.

## What to build

Implement **Chain Lightning** as a global unlock with prep + save + lead-ship-only runtime. Each firing event should:

1. Choose an initial **solid** target in baseline range (no drill filter).
2. Apply damage through **`MiningWorld`** normal cell damage.
3. **Chain** to one or more additional solid cells within a small radius / hop limit, with **decaying damage** or a fixed small hop count for the first slice.

Cap total hops or total damage per event so performance stays predictable (similar spirit to cascade caps in `issues/010-explosive-block-effect-system.md` but tuned for lightning).

Visual can be **polyline or segmented Line2D** between cell centers; audio optional reuse of existing hit SFX.

## Acceptance criteria

- [ ] Prep lists Chain Lightning under `Weapon Systems`; `UpgradeBus` + career persistence work.
- [ ] Unlock survives ship changes and is global across vehicles.
- [ ] Only the lead mining ship triggers lightning; followers do not.
- [ ] At least **two** cells can be damaged in one event when terrain allows (primary + one chain), each through normal `MiningWorld` flow.
- [ ] Chain does not use drill part type allowlists.
- [ ] A per-event hop or damage budget prevents pathological chains on dense terrain.
- [ ] Lightning is visually distinguishable from Laser and Missile.
- [ ] Smoke test covers registry / purchase id.

## Blocked by

None - can start immediately
