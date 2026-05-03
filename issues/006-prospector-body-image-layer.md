# Prospector Body Image Layer

Type: AFK

Triage: needs-triage

Blocked by: None - can start immediately

User stories covered:
- As a player, the Prospector uses the new body art while Scout keeps its current polygon body.

## What to build

Update the Prospector ship scene to use `assets/sprites/prospector/prospector_body.png` as its body visual. The body sprite should be centered on the ship, scaled to match the current in-game Prospector visual footprint, and layered above treads but below equipped drill and fuel tank visuals. Keep Scout body visuals unchanged.

## Acceptance criteria

- [ ] `Prospector.tscn` displays `prospector_body.png` as the Prospector body visual.
- [ ] The Prospector body sprite is centered at the same origin used by the part attachment layers.
- [ ] The Prospector body sprite is scaled to match the current in-game Prospector visual footprint.
- [ ] The Prospector body layer renders above treads and below drill and fuel tank visuals.
- [ ] Scout keeps its current polygon hull/body visual.
- [ ] Existing Prospector collision and mining geometry are unchanged.

## Blocked by

None - can start immediately
