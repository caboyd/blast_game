# Weapon System: Missile

Type: AFK

Blocked by: None - can start immediately (follows pattern from `issues/008-automatic-laser-power-system.md`)

Parent: `issues/008-automatic-laser-power-system.md`

Triage: needs-triage

User stories covered:
- As a player, I can unlock a global Missile weapon system in prep under `Weapon Systems` and keep it across vehicles.
- As a player, missiles automatically engage valid terrain during mining runs.
- As a player, missiles are clearly distinct from drill mining and from the Laser line attack.

## What to build

Add a **Missile** global weapon: registry definition + prep row + runtime on the **lead** ship only. Missiles should pick a **non-empty solid** target in baseline range (or along firing arc), travel or simulate travel in a lightweight way, and apply damage on impact through **`MiningWorld`** normal damage flow. Ignore drill part filters for targeting and damage.

First slice can be **kinematically simple** (e.g. short-lived `Line2D` / `Sprite2D` tracer + timed impact at cell center) as long as the outcome is correct gameplay-wise. Baseline cooldown, speed, range, and damage should be constants beside other weapon baselines.

Guidance and multi-missile salvos are **follow-up** work unless they fall out trivially.

## Acceptance criteria

- [ ] Prep shows Missile under `Weapon Systems` with purchase via `UpgradeBus` and career save.
- [ ] Unlock persists across ship selection changes.
- [ ] Lead ship fires on baseline cooldown when unlocked; followers never fire or spawn missile logic.
- [ ] Impact damage goes through `MiningWorld` so rewards, fuel, discovery, and `block_broken` behave like drill/Laser breaks.
- [ ] No drill-type allowlist filtering on missile hits.
- [ ] Missile has a minimal in-world read (trail, glow, or icon) that distinguishes it from Laser.
- [ ] Smoke-level test asserts upgrade id is registered and purchasable within designed caps.

## Blocked by

None - can start immediately
