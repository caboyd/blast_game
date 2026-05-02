# Fullscreen Mining Layout

Type: AFK

Blocked by:
- `001-top-run-stats-overlay.md`
- `002-resource-found-overlay.md`
- `003-bottom-player-stats-overlay.md`

User stories covered:
- As a player, the mining viewport uses the full available screen while HUD elements overlay gameplay.
- As a player, the old bottom HUD no longer reserves space or crowds the play area.

## What to build

Remove the mining-scene `BottomHUD` instances from `Planet1` and `Planet2`, remove top and bottom HUD reserved layout bands, and restore the gameplay target to a normal 16:9 area. The gameplay viewport should fill the screen through the existing aspect-ratio layout, letterboxing or pillarboxing if the window is not 16:9. Keep the old `BottomHUD` scene and script files in the project for now.

## Acceptance criteria

- [ ] `Planet1` and `Planet2` no longer instantiate `BottomHUD`.
- [ ] The old bottom HUD files remain in the project and are not deleted.
- [ ] Gameplay no longer reserves vertical space for the old bottom HUD.
- [ ] Gameplay no longer reserves vertical space for the top fuel HUD.
- [ ] HUD elements overlay gameplay instead of shrinking the gameplay area.
- [ ] The gameplay aspect target is restored to 16:9.
- [ ] Non-16:9 windows use the existing aspect-ratio behavior to letterbox or pillarbox.
- [ ] Debug overlays and viewport sizing still update correctly after resize.

## Blocked by

- `001-top-run-stats-overlay.md`
- `002-resource-found-overlay.md`
- `003-bottom-player-stats-overlay.md`
