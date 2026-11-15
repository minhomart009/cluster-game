# Headless bot harness (brief requirement 4). Run:
#   godot --headless --path . --script res://scripts/sim.gd
extends SceneTree

# class_name globals are not registered in a --script run (no editor cache), so preload.
const CR := preload("res://scripts/cluster_rules.gd")

const GAMES_CARELESS := 150
const GAMES_THOUGHTFUL := 40
const CAP := 400  # a run reaching the cap is treated as endless
const TRAY := 3
const FIFTH_AFTER := 40

func _initialize() -> void:
	print("CLUSTER sim — 7x7, clear>=4, tray 3, 5th colour after %d placements" % FIFTH_AFTER)
	for bot in ["careless", "thoughtful"]:
		var games: int = GAMES_CARELESS if bot == "careless" else GAMES_THOUGHTFUL
		var runs: Array[int] = []
		var self_clears := 0
		var endless := 0
		for g in games:
			var r: Dictionary = _play(bot, g)
			runs.append(r.placements)
			self_clears += r.self_clears
			if r.capped:
				endless += 1
		runs.sort()
		var med: int = runs[runs.size() / 2]
		print("%-11s median=%-5d p10=%-5d p90=%-5d hit-cap=%d/%d  self-clears/game=%.2f" % [
			bot, med, runs[runs.size() / 10], runs[runs.size() * 9 / 10], endless, games,
			float(self_clears) / games])
	quit()

func _play(bot: String, seed_v: int) -> Dictionary:
	var g := CR.new(7, 4, 4, seed_v * 7919 + 13)
	var tray: Array = g.deal(TRAY)
	var self_clears := 0
	while g.placements < CAP:
		if g.jammed(tray):
			break
		var moves := g.legal_moves(tray)
		var pick: Dictionary
		if bot == "careless":
			pick = moves[g.rng.randi_range(0, moves.size() - 1)]
		else:
			pick = _best(g, tray, moves)
		var e = tray[pick.tray]
		var n: int = g.place(CR.SHAPES[e.shape_id], e.colour, pick.x, pick.y)
		# self-clear = placement cleared without needing any tile already on the board
		if n > 0 and n == CR.SHAPES[e.shape_id].size():
			self_clears += 1
		tray[pick.tray] = null
		if _empty_tray(tray):
			tray = g.deal(TRAY)
		if g.placements == FIFTH_AFTER:
			g.colours = 5
	return {"placements": g.placements, "self_clears": self_clears, "capped": g.placements >= CAP}

func _empty_tray(tray: Array) -> bool:
	for t in tray:
		if t != null:
			return false
	return true

# 1-ply: clear as much as possible, otherwise sit next to your own colour and keep the board open.
func _best(g, tray: Array, moves: Array) -> Dictionary:
	var best: Dictionary = moves[0]
	var best_score := -1e9
	for m in moves:
		var e = tray[m.tray]
		var snap: Dictionary = g.snapshot()
		var n: int = g.place(CR.SHAPES[e.shape_id], e.colour, m.x, m.y)
		var score := float(n) * 25.0 - float(g.occupied()) * 1.0 + _friendly(g, e.colour) * 2.0
		g.restore(snap)
		if score > best_score:
			best_score = score
			best = m
	return best

# How much of this colour is clustered already — bigger clusters are closer to bursting.
func _friendly(g, colour: int) -> float:
	var n := 0
	for y in g.size:
		for x in g.size:
			if g.cells[g.idx(x, y)] != colour:
				continue
			if x + 1 < g.size and g.cells[g.idx(x + 1, y)] == colour:
				n += 1
			if y + 1 < g.size and g.cells[g.idx(x, y + 1)] == colour:
				n += 1
	return float(n)
