# Bottom Player Stats Overlay

Type: AFK

Blocked by: None - can start immediately

User stories covered:
- As a player, I can see my current ship capabilities while mining.
- As a player, I can see which ships are in my mission train without opening prep UI.

## What to build

Add a compact bottom overlay strip with a half-transparent dark background. The strip should be centered near the bottom of the screen and show player stats in this order: drill damage, movement speed, current ship, and ship train. Do not include money per second in this bottom strip; that belongs in the top run stats overlay.

## Acceptance criteria

- [ ] The bottom overlay displays `Drill`, `Speed`, `Ship`, and `Train` in that order.
- [ ] Drill damage shows effective damage per mining tick.
- [ ] Movement speed shows effective movement speed in cells per second.
- [ ] Current ship uses the active ship display name.
- [ ] Train shows count plus ship display names, for example `Train: 2 (Scout, Prospector)`.
- [ ] The strip uses a compact centered half-transparent background and does not recreate the old large `BottomHUD` panel.
- [ ] The overlay works on both `Planet1` and `Planet2`.

## Blocked by

None - can start immediately
