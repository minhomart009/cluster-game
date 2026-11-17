# Headless test harness for GLASS POP (brief requirement 4). CI gate 1 runs this.
#   godot --headless --script res://scripts/sim.gd
extends SceneTree

const FR := preload("res://scripts/fill_rules.gd")
const ROUNDS_PER_SHAPE := 60

func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.open("res://config/default.json", FileAccess.READ).get_as_text())
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var tray: int = int(cfg.tray_size)
	var maxc: int = int(cfg.max_piece_cells)

	var total := 0
	var solvable := 0
	var failed_gen := 0
	print("GLASS POP — round generation and solvability")
	for t in cfg.tiers:
		for name in t.shapes.keys():
			var cells: Array[Vector2i] = []
			for c in t.shapes[name]:
				cells.append(Vector2i(int(c[0]), int(c[1])))
			var worst_pieces := 0
			for i in ROUNDS_PER_SHAPE:
				total += 1
				var r: Dictionary = FR.make_round(cells, tray, bool(t.decoys), maxc, rng)
				if not r.ok:
					failed_gen += 1
					continue
				var holes := {}
				for c in cells:
					holes[c] = true
				var plist := []
				for p in r.pieces:
					plist.append(p.cells)
				worst_pieces = max(worst_pieces, plist.size())
				if FR.can_finish(holes, plist):
					solvable += 1
			print("  tier %d %-9s cells=%-3d pieces<=%d" % [int(t.tier), name, cells.size(), worst_pieces])
	print("rounds=%d solvable=%d failed_generation=%d" % [total, solvable, failed_gen])

	# Dead-end detection must work in both directions, or the Owner's bug is back.
	var sq2 := {Vector2i(0,0): true, Vector2i(1,0): true, Vector2i(0,1): true, Vector2i(1,1): true}
	var two_dominoes := [[Vector2i(0,0), Vector2i(1,0)], [Vector2i(0,0), Vector2i(1,0)]]
	var can_a: bool = FR.can_finish(sq2.duplicate(), two_dominoes)
	# An L-shaped hole can never be filled by a 2x2 block: this is the dead end.
	var ell := {Vector2i(0,0): true, Vector2i(0,1): true, Vector2i(1,1): true}
	var square_piece := [[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)]]
	var can_b: bool = FR.can_finish(ell.duplicate(), square_piece)
	print("deadend_check solvable_case=%s unsolvable_case=%s" % [str(can_a), str(can_b)])
	print("RESULT all_rounds_solvable=%s" % str(total == solvable and failed_gen == 0))
	quit()
