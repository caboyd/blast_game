# Laser Upgrades And Targeting Modes

Type: AFK

Blocked by: `issues/008-automatic-laser-power-system.md`

User stories covered:
- As a player, buying the Laser unlock reveals grouped upgrades for that system.
- As a player, I can tune the laser with range, damage, fire rate, width, and pierce upgrades.
- As a player, I can choose how the laser picks targets without spending upgrade currency on targeting modes.

## What to build

Expand the Laser system from the baseline unlock into a grouped upgrade set. Once Laser is unlocked, prep should reveal Laser child upgrades for range, damage, fire rate, laser width, and pierce count in the `Weapon Systems` section.

Add a persisted per-weapon target-priority control for Laser. The available modes should be healthiest, weakest, highest value, and highest density. The choice should be free, saved in the career config, and used by the runtime targeting logic.

The runtime laser should apply the purchased upgrade stats immediately during runs: range affects target search, damage affects HP removed, fire rate affects cooldown, width affects beam/circle damage area, and pierce allows one firing event to damage multiple blocks along or near the beam path.

## Acceptance criteria

- [ ] Laser child upgrades are hidden until the Laser unlock has been purchased.
- [ ] Laser child upgrades are visually grouped under the Laser system in the `Weapon Systems` prep section.
- [ ] Laser range, damage, fire rate, width, and pierce upgrades use existing money costs and persist through `UpgradeBus`.
- [ ] Prep shows useful next-level or max-level text for the Laser child upgrades.
- [ ] Prep exposes a free Laser target-priority control once Laser is unlocked.
- [ ] Laser target-priority choice persists in the career save and survives returning to prep or restarting the project.
- [ ] Healthiest mode prefers the valid in-range block with the highest current HP.
- [ ] Weakest mode prefers the valid in-range block with the lowest current HP.
- [ ] Highest value mode prefers the valid in-range block with the highest destroy reward.
- [ ] Highest density mode prefers the valid in-range block with the most surrounding solid blocks.
- [ ] Purchased range, damage, fire rate, width, and pierce levels affect runtime Laser behavior.

## Blocked by

- `issues/008-automatic-laser-power-system.md`
