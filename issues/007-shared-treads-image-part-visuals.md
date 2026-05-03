# Shared Treads Image Part Visuals

Type: AFK

Triage: needs-triage

Blocked by: None - can start immediately

User stories covered:
- As a player, equipped treads render from the new asset on any selected ship.

## What to build

Update the shared runtime treads part visuals to use `assets/sprites/prospector/parts/Tread.png`. Both treads tiers should use the same image asset through the existing equipped-part visual path, with tier 0 mildly red-tinted and tier 1 untinted.

## Acceptance criteria

- [ ] Both treads part tiers use a Sprite2D-based ship visual sourced from `Tread.png`.
- [ ] Tier 0 treads have a mild red tint.
- [ ] Tier 1 treads have no tint.
- [ ] The treads visual is centered so it stacks directly with the body, drill, and fuel tank layers.
- [ ] The treads visual renders below the Prospector body layer when attached to the Prospector.
- [ ] Runtime `PartVisuals.attach_to_ship()` still attaches equipped treads in prep and mining scenes.

## Blocked by

None - can start immediately
