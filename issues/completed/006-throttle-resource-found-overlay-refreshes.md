# Throttle Resource Found Overlay Refreshes

Type: AFK

Blocked by: None - can start immediately

User stories covered:
- As a player, mined-resource counts remain accurate without the resource overlay rebuilding every frame during bursts.
- As a player, viewport resize feedback stays responsive without allowing resize events to trigger repeated same-frame rebuilds.

## What to build

Route `ResourceFoundOverlay` mined-resource and viewport-size invalidations through a single scheduler instead of calling `_refresh_rows()` directly. Mined-resource updates should coalesce and render the latest `GameStatistics` snapshot at most every 250ms by default. Viewport-size updates should use a separate faster interval, around 50ms by default. Both intervals should be exposed as top-level exported seconds variables.

The initial render should start immediately when the overlay is ready. Empty/reset snapshots should hide the overlay immediately so stale resources do not linger between runs.

## Acceptance criteria

- [ ] `ResourceFoundOverlay` exposes a configurable mined-resource refresh interval with a default of `0.25` seconds.
- [ ] `ResourceFoundOverlay` exposes a configurable viewport refresh interval with a default of `0.05` seconds.
- [ ] `GameStatistics.run_mined_resources_changed` no longer causes direct synchronous row rebuilds for every emitted signal.
- [ ] Multiple mined-resource changes inside one refresh window coalesce into one rebuild using the latest sorted resource snapshot.
- [ ] Multiple viewport-size changes inside one viewport refresh window coalesce into one rebuild using the latest viewport width.
- [ ] The initial overlay render starts immediately after `_ready()`.
- [ ] Empty or reset resource snapshots hide the overlay immediately and notify the top HUD layout as dirty.

## Blocked by

None - can start immediately
