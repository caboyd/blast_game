# Top Run Stats Overlay

Type: AFK

Blocked by: None - can start immediately

User stories covered:
- As a player, I can see fuel, money gained this run, rolling money per second, and estimated time remaining while mining.
- As a player, fuel pickups and fuel drain changes update the run timer immediately.

## What to build

Replace the current fuel-only mining overlay with a top overlay stack that keeps the fuel bar at the top and adds one centered half-transparent stats pill below it. The pill should show actual money awarded this run, rolling 10-second money per second, and live time remaining computed from current fuel divided by the leading ship's effective fuel drain per second.

## Acceptance criteria

- [ ] The top HUD shows fuel as a bar, plus a centered half-transparent pill formatted with run money, rolling `$/s`, and time remaining.
- [ ] Money gained this run is actual awarded money after bonuses, not raw block value or net wallet change.
- [ ] Rolling `$/s` uses actual money awards from the last 10 seconds.
- [ ] Time remaining uses current fuel, including overflow, divided by the leading ship's effective fuel drain per second.
- [ ] The overlay works on both `Planet1` and `Planet2`.
- [ ] The HUD updates while the run is active without requiring scene reloads.

## Blocked by

None - can start immediately
