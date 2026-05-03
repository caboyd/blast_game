# Shared Drill Image Part Visuals

Type: AFK

Triage: needs-triage

Blocked by: None - can start immediately

User stories covered:
- As a player, equipped drills render from the new asset on any selected ship.

## What to build

Update the shared runtime drill part visuals to use `assets/sprites/prospector/parts/Drill.png`. Both drill tiers should use the same image asset through the existing equipped-part visual path, with tier 0 mildly red-tinted and tier 1 untinted. Preserve the existing ship mining/collision behavior.

## Acceptance criteria

- [ ] Both drill part tiers use a Sprite2D-based ship visual sourced from `Drill.png`.
- [ ] Tier 0 drill has a mild red tint.
- [ ] Tier 1 drill has no tint.
- [ ] The drill visual is centered so it stacks directly with the body, treads, and fuel tank layers.
- [ ] The drill visual renders above the body layer and below the fuel tank layer when attached to the Prospector.
- [ ] Existing drill collision and mining behavior are unchanged.
- [ ] Runtime `PartVisuals.attach_to_ship()` still attaches equipped drills in prep and mining scenes.

## Blocked by

None - can start immediately
