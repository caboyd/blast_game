# Automatic Laser Power System

Type: AFK

Blocked by: None - can start immediately

User stories covered:
- As a player, I can buy a global Laser system unlock in prep and keep it unlocked across vehicles.
- As a player, my unlocked laser automatically damages valid blocks during a mining run.
- As a player, I can clearly distinguish vehicle upgrades from new weapon-system upgrades in prep.

## What to build

Add the first global vehicle power vertical slice: a Laser system unlock that is purchased with existing money, persists through the career save, appears under a new `Weapon Systems` prep-shop section, and auto-fires during mining runs.

The slice should introduce the minimum reusable power-upgrade registry needed for global upgrade definitions while keeping `UpgradeBus` as the purchase, level, cost, and save authority. Existing selected-ship upgrades should continue to appear under a `Vehicle Upgrades` section.

When Laser is unlocked, the active non-follower mining vehicle should periodically choose any non-destroyed solid block in range, ignoring drill part restrictions, draw a lightweight beam, and damage the target through the normal `MiningWorld` destruction/reward flow.

## Acceptance criteria

- [x] Prep shop shows a `Vehicle Upgrades` section containing the current selected-ship upgrades.
- [x] Prep shop shows a `Weapon Systems` section containing a single-level Laser unlock purchase.
- [x] Buying the Laser unlock uses existing money, purchase batching rules where appropriate, and career persistence through `UpgradeBus`.
- [x] The Laser unlock remains available across vehicle selection changes.
- [x] During a mining run, the active lead vehicle auto-fires Laser on a fixed baseline cooldown when unlocked.
- [x] Laser targets any non-empty solid block inside its baseline range and does not apply equipped drill part type restrictions.
- [x] Laser damage goes through `MiningWorld` normal damage/destruction flow so money, fuel, discovery, block stats, and `block_broken` still work.
- [x] Follower visual-only ships do not create or fire power controllers.
- [x] Future Bomb, Missile, Chain Lightning, Chain Destroy, and Gravity Pull systems are not visible in the playable prep UI.

## Blocked by

None - can start immediately
