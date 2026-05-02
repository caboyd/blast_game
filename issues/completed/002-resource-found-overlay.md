# Resource Found Overlay

Type: AFK

Blocked by: None - can start immediately

User stories covered:
- As a player, I can see which resources I have mined during the current run.
- As a player, I can compare resource counts visually using proportional bars.
- As a player, I can inspect block max HP without keeping HP text always visible.

## What to build

Add a top-left resource panel that starts below the full top HUD stack. It should list only resource types mined during the current run, sorted by count descending. Each row shows a same-color square, the mined count, and a horizontal bar whose maximum width is 10% of the root viewport width. The most-mined resource uses the full bar width and all others scale proportionally. When the resource panel is hovered, every visible row shows `MAX HP X` aligned on the far right.

## Acceptance criteria

- [ ] Resource counts increment only when blocks are fully mined or destroyed.
- [ ] Fuel clusters count as one found resource event.
- [ ] All non-empty mineable block types are eligible for the panel, including common terrain.
- [ ] Rows are hidden until their count is greater than zero this run.
- [ ] Rows are sorted by count descending and update as resources are mined.
- [ ] Row color matches the mined block type color.
- [ ] The largest count gets a 100% bar, and other bars scale proportionally.
- [ ] The max bar width is 10% of the root viewport width.
- [ ] Hovering the panel shows `MAX HP X` for all visible rows at the far right.
- [ ] The overlay works on both `Planet1` and `Planet2`.

## Blocked by

None - can start immediately
