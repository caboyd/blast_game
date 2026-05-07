# Explosive Block Effect System

Type: AFK

Blocked by: `issues/008-automatic-laser-power-system.md`

User stories covered:
- As a player, I can buy a global block-effect unlock that changes what happens when blocks are destroyed.
- As a player, destroyed blocks can sometimes explode and damage nearby blocks.
- As a player, block-effect upgrades are categorized separately from vehicle upgrades and weapon systems.

## What to build

Add the first global `Block Effects` vertical slice: an Explosive Blocks unlock plus grouped child upgrades that give destroyed blocks a chance to explode and damage nearby blocks.

Prep should show a new `Block Effects` section with the single-level Explosive Blocks unlock. Buying the unlock should reveal grouped child upgrades for explosion chance, explosion damage, and explosion radius. The effect should apply to blocks destroyed by normal mining, Laser damage, and explosion cascades.

Explosive cascades should be exciting but bounded. Allow secondary explosions, but enforce a per-original-destruction cascade budget or depth cap so one proc cannot run indefinitely or spike the frame.

## Acceptance criteria

- [ ] Prep shop shows a `Block Effects` section distinct from `Vehicle Upgrades` and `Weapon Systems`.
- [ ] `Block Effects` initially shows the single-level Explosive Blocks unlock.
- [ ] Explosive Blocks child upgrades are hidden until the Explosive Blocks unlock has been purchased.
- [ ] Explosive Blocks child upgrades are visually grouped under the Explosive Blocks system.
- [ ] Explosion chance, explosion damage, and explosion radius upgrades use existing money costs and persist through `UpgradeBus`.
- [ ] Destroying a block by drill mining can trigger an explosion when Explosive Blocks is unlocked.
- [ ] Destroying a block by Laser damage can trigger an explosion when Explosive Blocks is unlocked.
- [ ] Explosion damage uses `MiningWorld` normal damage/destruction flow so rewards, fuel, discovery, block stats, and `block_broken` still work.
- [ ] Explosions can trigger secondary explosions within a capped cascade budget or depth.
- [ ] The cascade cap is enforced per original destruction event and prevents unbounded recursion.
- [ ] Explosions have a lightweight visual indicator such as a pulse or ring.

## Blocked by

- `issues/008-automatic-laser-power-system.md`
