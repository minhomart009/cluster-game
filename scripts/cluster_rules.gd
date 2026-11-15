# CLUSTER — pure game rules. No nodes, no UI, no engine features beyond RefCounted.
# Deliberately headless-testable so bots can play thousands of games (brief req 4).
class_name ClusterRules
extends RefCounted

const EMPTY := -1

# Every shape is 1-3 cells. No piece can complete a group of 4 by itself.
# (Game Designer log part 3, Entry 7: self-clears measured 0.0 after this cap.)
const SHAPES := [
	[Vector2i(0,0)],
	[Vector2i(0,0), Vector2i(1,0)],
	[Vector2i(0,0), Vector2i(0,1)],
	[Vector2i(0,0), Vector2i(1,0), Vector2i(2,0)],
	[Vector2i(0,0), Vector2i(0,1), Vector2i(0,2)],
	[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1)],
	[Vector2i(0,0), Vector2i(1,0), Vector2i(1,1)],
	[Vector2i(0,0), Vector2i(0,1), Vector2i(1,1)],
	[Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
]

var size: int
var clear_threshold: int
var colours: int
var cells: PackedInt32Array
var placements := 0
var cleared_total := 0
var cleared_by_colour := {}
var rng := RandomNumberGenerator.new()

func _init(p_size := 7, p_colours := 4, p_threshold := 4, p_seed := 0) -> void:
	size = p_size
	colours = p_colours
	clear_threshold = p_threshold
	rng.seed = p_seed
	cells = PackedInt32Array()
	cells.resize(size * size)
	cells.fill(EMPTY)

func idx(x: int, y: int) -> int:
	return y * size + x

func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size and y < size

func fits(shape: Array, ox: int, oy: int) -> bool:
	for o in shape:
		var x: int = ox + o.x
		var y: int = oy + o.y
		if not inside(x, y) or cells[idx(x, y)] != EMPTY:
			return false
	return true

# Returns how many cells were cleared by this placement.
func place(shape: Array, colour: int, ox: int, oy: int) -> int:
	if not fits(shape, ox, oy):
		return -1
	var touched: Array[Vector2i] = []
	for o in shape:
		var x: int = ox + o.x
		var y: int = oy + o.y
		cells[idx(x, y)] = colour
		touched.append(Vector2i(x, y))
	placements += 1
	# Only groups containing a newly placed cell can have newly qualified.
	var to_clear := {}
	var seen := {}
	for t in touched:
		if seen.has(t):
			continue
		var group := _group_at(t.x, t.y, colour)
		for g in group:
			seen[g] = true
		if group.size() >= clear_threshold:
			for g in group:
				to_clear[g] = true
	for c in to_clear.keys():
		cells[idx(c.x, c.y)] = EMPTY
	var n := to_clear.size()
	cleared_total += n
	if n > 0:
		cleared_by_colour[colour] = cleared_by_colour.get(colour, 0) + n
	return n

func _group_at(x: int, y: int, colour: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var stack := [Vector2i(x, y)]
	var visited := {}
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if visited.has(p):
			continue
		visited[p] = true
		if not inside(p.x, p.y) or cells[idx(p.x, p.y)] != colour:
			continue
		out.append(p)
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))
	return out

# A tray entry is {shape_id:int, colour:int}
func legal_moves(tray: Array) -> Array:
	var out := []
	for i in tray.size():
		if tray[i] == null:
			continue
		var shape: Array = SHAPES[tray[i].shape_id]
		for y in size:
			for x in size:
				if fits(shape, x, y):
					out.append({"tray": i, "x": x, "y": y})
	return out

func jammed(tray: Array) -> bool:
	for i in tray.size():
		if tray[i] == null:
			continue
		var shape: Array = SHAPES[tray[i].shape_id]
		for y in size:
			for x in size:
				if fits(shape, x, y):
					return false
	return true

func deal(tray_size: int) -> Array:
	var out := []
	for i in tray_size:
		out.append({
			"shape_id": rng.randi_range(0, SHAPES.size() - 1),
			"colour": rng.randi_range(0, colours - 1),
		})
	return out

func occupied() -> int:
	var n := 0
	for c in cells:
		if c != EMPTY:
			n += 1
	return n

func snapshot() -> Dictionary:
	return {"cells": Array(cells), "placements": placements, "cleared": cleared_total}

func restore(s: Dictionary) -> void:
	cells = PackedInt32Array(s.cells)
	placements = s.placements
	cleared_total = s.cleared
