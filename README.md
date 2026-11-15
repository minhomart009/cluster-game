# CLUSTER

Casual puzzle game. Godot 4.6, Android first.

Drag a 1–3 cell shape onto a 7×7 grid. Four or more connected cells of one colour burst
and free their space. All three dealt shapes must be placed before new ones arrive.
No legal placement ends the run.

- `scripts/cluster_rules.gd` — the rules, as a pure logic class with no nodes, so bots and CI can play it.
- `scripts/sim.gd` — headless bot harness. `godot --headless --script res://scripts/sim.gd`
- `config/default.json` — every tunable value. Nothing balance-related is hard-coded.
- `.github/workflows/build.yml` — rules test → debug APK → launch on an API 28 emulator.

Package name `com.minho.cluster` is a **placeholder pending the Owner's confirmation**: it cannot be
changed after the first Play Store upload without creating a new app.
