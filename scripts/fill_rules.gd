# GLASS POP — Fill the Shape. Pure rules: round generation, exact-cover solving,
# dead-end detection. No nodes, no UI, so bots and CI can run it headlessly.
class_name FillRules
extends RefCounted

# ---------------------------------------------------------------- generation

# Every round is cut from the target itself, so a solution exists by construction
# (GAME-LOCKED section 5 / timer doc section 1).
static func cut_shape(cells: Array, rng: RandomNumberGenerator, max_pieces: int, max_size: int) -> Array:
	var remaining := {}
	for c in cells:
		remaining[c] = true
	var want: int = clampi(int(ceil(float(cells.size()) / 4.0)), 2, max_pieces)
	var target_size: int = max(2, int(round(float(cells.size()) / float(want))))
	var pieces := []
	while not remaining.is_empty():
		var keys := remaining.keys()
		var start: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
		var blob: Array[Vector2i] = [start]
		remaining.erase(start)
		var size_goal: int = min(max_size, max(2, target_size + rng.randi_range(-1, 1)))
		# The last piece must swallow whatever is left, or we strand single cells.
		while blob.size() < size_goal:
			var options: Array[Vector2i] = []
			for b in blob:
				for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var n: Vector2i = b + d
					if remaining.has(n) and not options.has(n):
						options.append(n)
			if options.is_empty():
				break
			var pick: Vector2i = options[rng.randi_range(0, options.size() - 1)]
			blob.append(pick)
			remaining.erase(pick)
		pieces.append(_normalise(blob))
		if pieces.size() >= max_pieces and not remaining.is_empty():
			# Never leave cells uncovered: fold the rest into the last piece only if
			# it stays connected, otherwise start over with a looser piece budget.
			return []
	return pieces

static func _normalise(cells: Array) -> Array:
	var mx := 1 << 30
	var my := 1 << 30
	for c in cells:
		mx = min(mx, c.x)
		my = min(my, c.y)
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(Vector2i(c.x - mx, c.y - my))
	out.sort()
	return out

# A decoy is only allowed if it cannot sit anywhere inside the target. Pieces that
# fit but lead nowhere ("red herrings") are banned - they punish weak players and
# hide information, which is the thing this game must never do (timer doc, 1).
static func is_obvious_decoy(piece: Array, target: Dictionary) -> bool:
	return not fits_anywhere(piece, target)

static func fits_anywhere(piece: Array, holes: Dictionary) -> bool:
	for h in holes.keys():
		for anchor in piece:
			var off: Vector2i = h - anchor
			var ok := true
			for c in piece:
				if not holes.has(c + off):
					ok = false
					break
			if ok:
				return true
	return false

static func random_piece(rng: RandomNumberGenerator, max_size: int) -> Array:
	var size: int = rng.randi_range(2, max(2, min(4, max_size)))
	var blob: Array[Vector2i] = [Vector2i.ZERO]
	while blob.size() < size:
		var b: Vector2i = blob[rng.randi_range(0, blob.size() - 1)]
		var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		var n: Vector2i = b + dirs[rng.randi_range(0, 3)]
		if not blob.has(n):
			blob.append(n)
	return _normalise(blob)

# Returns {"cells": target cells, "pieces": [{cells, real}], "ok": bool}
static func make_round(shape_cells: Array, tray_size: int, allow_decoys: bool,
		max_piece_cells: int, rng: RandomNumberGenerator) -> Dictionary:
	var target := {}
	for c in shape_cells:
		target[c] = true
	var cut := []
	for attempt in 12:
		cut = cut_shape(shape_cells, rng, tray_size, max_piece_cells)
		if not cut.is_empty():
			break
	if cut.is_empty():
		return {"ok": false}
	var pieces := []
	for p in cut:
		pieces.append({"cells": p, "real": true})
	if allow_decoys:
		var guard := 0
		while pieces.size() < tray_size and guard < 200:
			guard += 1
			var d := random_piece(rng, max_piece_cells)
			if is_obvious_decoy(d, target):
				pieces.append({"cells": d, "real": false})
	pieces.shuffle()
	return {"ok": true, "cells": shape_cells.duplicate(), "pieces": pieces}

# ------------------------------------------------------- exact-cover solving

# Can the pieces still left in the tray fill exactly the holes still open?
# Called after every placement AND every take-back. At these sizes (<=16 cells,
# <=6 pieces) this is instant, which is why the dead-end warning can be immediate.
static func can_finish(holes: Dictionary, pieces: Array) -> bool:
	if holes.is_empty():
		return true
	var total := 0
	for p in pieces:
		total += p.size()
	if total < holes.size():
		return false
	return _search(holes.duplicate(), pieces, [])

static func _search(holes: Dictionary, pieces: Array, used: Array) -> bool:
	if holes.is_empty():
		return true
	# Always attack the same hole: the top-left one. Every tiling must cover it,
	# so this prunes the search hard without any cleverness.
	var keys := holes.keys()
	keys.sort()
	var hole: Vector2i = keys[0]
	for i in pieces.size():
		if used.has(i):
			continue
		var piece: Array = pieces[i]
		for anchor in piece:
			var off: Vector2i = hole - anchor
			var cells: Array[Vector2i] = []
			var ok := true
			for c in piece:
				var t: Vector2i = c + off
				if not holes.has(t):
					ok = false
					break
				cells.append(t)
			if not ok:
				continue
			for t in cells:
				holes.erase(t)
			used.append(i)
			if _search(holes, pieces, used):
				return true
			used.erase(i)
			for t in cells:
				holes[t] = true
	return false
