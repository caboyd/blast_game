# Weapon System: Gravity Pull

Type: AFK

Blocked by: None - can start immediately (follows pattern from `issues/008-automatic-laser-power-system.md`)

Parent: `issues/008-automatic-laser-power-system.md`

Triage: needs-triage

User stories covered:
- As a player, I can unlock Gravity Pull as a global weapon system.
- As a player, periodic gravity bursts affect blocks or pickups near my ship during mining.
- As a player, effects integrate with existing world systems without breaking followers or fuel economy.

## What to build

Add **Gravity Pull** as a global `Weapon Systems` unlock with the same prep + persistence pattern as Laser.

First vertical slice should pick **one** primary interaction (decide in implementation, prefer simplest end-to-end path):

- **Option A — terrain focus:** periodic pull applies **damage** or **“crack” impulse** to solids in a **cone or radius** toward the ship, all via **`MiningWorld`** normal damage / break flow, no drill filter; **or**
- **Option B — pickup focus:** periodic pull applies **impulse** toward the ship on **parts / pickups** using existing rigid-body or pickup APIs (see `PartGroundPickup` / mining pickup groups), without grabbing followers.

Document the chosen option in the PR / issue close notes. Constants: cooldown, radius, strength. Lead ship only; followers inert.

If Option B risks scope creep, default to Option A for parity with other weapons.

## Acceptance criteria

- [ ] Prep lists Gravity Pull under `Weapon Systems`; `UpgradeBus` + career save; global across ships.
- [ ] Lead ship only runs gravity weapon logic on a baseline cooldown.
- [ ] Chosen interaction (terrain or pickups) is demoable end-to-end without cheating collisions or save data.
- [ ] Terrain damage, if used, goes through `MiningWorld` like other weapons; drill allowlists not applied.
- [ ] Followers do not run gravity logic or duplicate VFX.
- [ ] No regressions to ship movement, fuel drain, or follower following.
- [ ] Smoke test for upgrade id registration / purchase.

## Blocked by

None - can start immediately
