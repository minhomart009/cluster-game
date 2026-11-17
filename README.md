# GLASS POP — Fill the Shape

Godot 4.6, Android first. Locked mechanic: see `claude/design/GAME-LOCKED-fill-the-shape.md`.

A target shape appears with a tray of up to 6 pieces and a timer. Drag pieces in
(no rotation) to fill the shape exactly; tap a placed piece to take it back.
Filling it wins the round. Losing costs the round and the streak multiplier only —
never score or progress. A results-driven dealer tightens the clock on every win,
moves up a tier after four wins and down after two losses in a row.

- `scripts/fill_rules.gd` — round generation, exact-cover solver, dead-end check. Pure logic, no nodes.
- `scripts/main.gd` — the game.
- `scripts/sim.gd` — headless harness. CI fails if any generated round is unsolvable
  or if dead-end detection is wrong in either direction.
- `config/default.json` — tiers, shapes, timers, dealer and scoring. Remote-config; no balance value is hard-coded.
- `.github/workflows/build.yml` — rules test → release APK → launch on an API 28 emulator → publish.

Package name `com.minho.cluster` is fixed (confirmed by the Owner): it cannot change
after the first Play upload without creating a new app.
