# Shared Fuel Tank Image Part Visuals

Type: AFK

Triage: needs-triage

Blocked by: None - can start immediately

User stories covered:
- As a player, equipped fuel tanks render from the new asset on any selected ship.

## What to build

Update the shared runtime fuel tank part visuals to use `assets/sprites/prospector/parts/Tank.png`. Both fuel tank tiers should use the same image asset through the existing equipped-part visual path, with tier 0 mildly red-tinted and tier 1 untinted.

## Acceptance criteria

- [x] Both fuel tank part tiers use a Sprite2D-based ship visual sourced from `Tank.png`.
- [x] Tier 0 fuel tank has a mild red tint.
- [x] Tier 1 fuel tank has no tint.
- [x] The fuel tank visual is centered so it stacks directly with the body, treads, and drill layers.
- [x] The fuel tank visual renders above the treads, body, and drill layers when attached to the Prospector.
- [x] Runtime `PartVisuals.attach_to_ship()` still attaches equipped fuel tanks in prep and mining scenes.

## Blocked by

None - can start immediately
