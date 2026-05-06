# Spread Resource Found Overlay Rebuilds Across Frames

Type: AFK

Blocked by: `006-throttle-resource-found-overlay-refreshes.md`

User stories covered:
- As a player, the resource overlay can update during large mining bursts without causing a single-frame UI spike.
- As a player, the currently visible resource list remains stable while a refreshed list is being prepared.
- As a player, hover details continue to behave naturally when a background refresh completes.

## What to build

Change `ResourceFoundOverlay` row rebuilding so visible rows are not destroyed and recreated synchronously in one frame. Build the next resource row list into an off-tree `VBoxContainer` over multiple frames, then swap it into place once the new list is complete. Expose a top-level row budget, defaulting to one row per frame, so rebuild cost can be tuned independently from the refresh cadence.

If resource or viewport changes arrive while a rebuild is already running, let the current rebuild finish, mark the overlay dirty, and schedule one follow-up rebuild after the relevant refresh interval using the latest snapshot. When the completed list is swapped in, recompute hover state from the current mouse position so the detail label does not disappear solely because a refresh finished.

## Acceptance criteria

- [ ] `ResourceFoundOverlay` exposes a configurable per-frame row rebuild budget with a default of `1`.
- [ ] Rebuilding a non-empty resource list creates at most the configured number of rows per frame.
- [ ] The old visible row list remains displayed until the new row list is complete.
- [ ] The completed row list swaps in as one visible update after background construction finishes.
- [ ] Resource or viewport changes received during an active rebuild schedule exactly one follow-up rebuild using the latest snapshot instead of restarting repeatedly.
- [ ] Hover state is preserved or recomputed after swap when the mouse is still over the same resource row or its detail region.
- [ ] The top HUD layout is marked dirty after the completed swap updates `custom_minimum_size`.

## Blocked by

- `006-throttle-resource-found-overlay-refreshes.md`
