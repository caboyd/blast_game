class_name GlobalPartMovementPenaltyEffect
extends GlobalPartEffect

## Treads-only: every `every_s`, translation is scaled by `speed_multiplier` for `duration_s`.

@export var every_s: float = 0.0
@export var duration_s: float = 0.0

## During that window: `effective_move_speed × speed_multiplier`. Clamped to [0, 1]: 0 = full stop, 1 = no slowdown.
@export_range(0.0, 1.0) var speed_multiplier: float = 0.0
