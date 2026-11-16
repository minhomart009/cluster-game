# CLUSTER — bare core loop. No art, no sound, no meta, no ads (RULE 9.5).
# Placeholder colours only. Every tunable comes from config, never from a literal here.
extends Node2D

const CR := preload("res://scripts/cluster_rules.gd")
const CONFIG_PATH := "res://config/default.json"
const SAVE_PATH := "user://save.json"

# Placeholder palette. Art & UI owns the real one.
const PALETTE := [
	Color(0.90, 0.30, 0.32), Color(0.26, 0.60, 0.88),
	Color(0.96, 0.76, 0.24), Color(0.36, 0.76, 0.45),
	Color(0.68, 0.45, 0.85),
]
const EMPTY_COLOR := Color(0.16, 0.17, 0.21)
const BG := Color(0.09, 0.10, 0.13)

var cfg := {}
var rules
var tray: Array = []
var drag_index := -1
var drag_pos := Vector2.ZERO
var board_origin := Vector2.ZERO
var cell := 0.0
var tray_slot_w := 0.0
var score_h := 0.0
var tray_y := 0.0
var banner_px := 0.0
const TRAY_SCALE := 0.62
var game_over := false
var placements_this_run := 0

func _ready() -> void:
	cfg = _load_config()
	_layout()
	get_window().size_changed.connect(_on_resize)
	if not _load_game():
		_new_run()

func _on_resize() -> void:
	_layout()
	queue_redraw()

func _load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_error("config missing")
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

# One dp in pixels. 160 dpi is the Android baseline; fall back to a mid-range
# density if the platform reports nothing rather than silently using 1 px per dp.
func _dp() -> float:
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return 3.0
	return float(dpi) / 160.0

func _layout() -> void:
	var vp := get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var top := 0.0
	if safe.size.y > 0 and safe.size.y < DisplayServer.screen_get_size().y:
		top = float(safe.position.y) / float(DisplayServer.screen_get_size().y) * vp.y

	# Banner is anchored at the BOTTOM (reference game does this), capped at 50dp.
	var banner_dp: float = 0.0
	if bool(cfg.get("banner_enabled", false)):
		banner_dp = min(float(cfg.get("banner_height_dp", 50)), float(cfg.get("banner_max_height_dp", 50)))
	banner_px = banner_dp * _dp()

	# Five bands, top to bottom: safe area, score, board, tray, banner.
	# The board takes the middle of the screen and the tray sits directly under it,
	# with no dead space between them (presentation study, section 2).
	var size: int = int(cfg.get("grid_size", 7))
	score_h = vp.y * 0.13
	var gap := 0.0
	var tray_h := 0.0
	var avail_h := 0.0
	# Tray height depends on cell size, so solve for the cell: board + gap + tray must fit.
	# tray row is about 2 cells tall at tray scale, gap is half a cell.
	var h_budget: float = vp.y - top - score_h - banner_px - vp.y * 0.04
	cell = floor(min(vp.x * 0.94 / size, h_budget / (float(size) + 0.5 + 2.0 * TRAY_SCALE + 0.6)))
	gap = cell * 0.5
	tray_h = cell * (2.0 * TRAY_SCALE + 0.6)
	avail_h = float(size) * cell + gap + tray_h
	var board_w := cell * size
	var free_v: float = vp.y - top - score_h - banner_px - avail_h
	board_origin = Vector2((vp.x - board_w) * 0.5, top + score_h + max(free_v * 0.35, 0.0))
	tray_y = board_origin.y + board_w + gap + tray_h * 0.5
	tray_slot_w = vp.x / float(cfg.get("tray_size", 3))

func _new_run() -> void:
	var size: int = int(cfg.get("grid_size", 7))
	var colours: int = int(cfg.get("endless_colours_start", 4))
	var threshold: int = int(cfg.get("clear_threshold", 4))
	rules = CR.new(size, colours, threshold, randi())
	tray = rules.deal(int(cfg.get("tray_size", 3)))
	game_over = false
	placements_this_run = 0
	_save_game()
	queue_redraw()

# ---------- input: pick a piece up, carry it, drop it. The verb never changes. ----------

func _unhandled_input(e: InputEvent) -> void:
	if game_over:
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
			_new_run()
		return
	if e is InputEventScreenTouch or e is InputEventMouseButton:
		if e.pressed:
			drag_index = _tray_hit(e.position)
			drag_pos = e.position
		elif drag_index >= 0:
			_try_drop(e.position)
			drag_index = -1
		queue_redraw()
	elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and drag_index >= 0:
		drag_pos = e.position
		queue_redraw()

func _tray_hit(pos: Vector2) -> int:
	# Generous hit band around the tray row - thumbs are not precise.
	if absf(pos.y - tray_y) > cell * 1.6:
		return -1
	var i := int(pos.x / tray_slot_w)
	if i < 0 or i >= tray.size() or tray[i] == null:
		return -1
	return i

# Where the carried piece is actually drawn: centred on the finger horizontally and
# lifted a clear distance ABOVE it, so the thumb never covers the piece or the cells
# it is about to land on (presentation study 3.2 - the Owner hit exactly this).
func _shape_extent(shape: Array) -> Vector2:
	var w := 0
	var h := 0
	for o in shape:
		w = max(w, int(o.x) + 1)
		h = max(h, int(o.y) + 1)
	return Vector2(w, h)

func _lift_origin(pos: Vector2, shape: Array) -> Vector2:
	var e := _shape_extent(shape)
	return pos + Vector2(-e.x * cell * 0.5, -e.y * cell - cell * 0.9)

# The piece lands where it is drawn, not where the finger is.
func _grid_anchor(pos: Vector2, shape: Array) -> Vector2i:
	var local := _lift_origin(pos, shape) - board_origin
	return Vector2i(int(round(local.x / cell)), int(round(local.y / cell)))

func _try_drop(pos: Vector2) -> void:
	var e = tray[drag_index]
	var shape: Array = CR.SHAPES[e.shape_id]
	var a := _grid_anchor(pos, shape)
	if not rules.fits(shape, a.x, a.y):
		return
	rules.place(shape, e.colour, a.x, a.y)
	placements_this_run += 1
	tray[drag_index] = null
	if _tray_empty():
		tray = rules.deal(int(cfg.get("tray_size", 3)))
	# Fifth colour arrives on schedule, from config.
	if placements_this_run >= int(cfg.get("endless_fifth_colour_after", 40)):
		rules.colours = min(PALETTE.size(), int(cfg.get("endless_colours_start", 4)) + 1)
	if rules.jammed(tray):
		game_over = true
	_save_game()

func _tray_empty() -> bool:
	for t in tray:
		if t != null:
			return false
	return true

# ---------- offline auto-save: the run survives a kill, with no connection ----------

func _save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"cells": Array(rules.cells),
		"tray": tray,
		"colours": rules.colours,
		"placements": placements_this_run,
		"cleared": rules.cleared_total,
		"game_over": game_over,
	}))
	return true

func _load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or not d.has("cells"):
		return false
	var size: int = int(cfg.get("grid_size", 7))
	rules = CR.new(size, int(d.get("colours", 4)), int(cfg.get("clear_threshold", 4)), randi())
	var cells: Array = d.cells
	if cells.size() != size * size:
		return false
	for i in cells.size():
		rules.cells[i] = int(cells[i])
	rules.cleared_total = int(d.get("cleared", 0))
	placements_this_run = int(d.get("placements", 0))
	game_over = bool(d.get("game_over", false))
	tray = []
	for t in d.get("tray", []):
		tray.append(null if t == null else {"shape_id": int(t.shape_id), "colour": int(t.colour)})
	if tray.is_empty():
		tray = rules.deal(int(cfg.get("tray_size", 3)))
	return true

func _notification(what: int) -> void:
	# Back button must pause/end politely, never drop a live board without saving.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if rules != null:
			_save_game()

# ---------- drawing: placeholder rectangles, nothing more ----------

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG)
	if rules == null:
		return
	var size: int = rules.size
	for y in size:
		for x in size:
			var v: int = rules.cells[rules.idx(x, y)]
			var r := Rect2(board_origin + Vector2(x, y) * cell + Vector2(2, 2), Vector2(cell - 4, cell - 4))
			draw_rect(r, EMPTY_COLOR if v == CR.EMPTY else PALETTE[v % PALETTE.size()])
	_draw_ghost()
	_draw_tray(vp)
	var font := ThemeDB.fallback_font
	var big := int(score_h * 0.62)
	draw_string(font, Vector2(0, board_origin.y - score_h * 0.18), str(rules.cleared_total),
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, big, Color(1, 1, 1))
	if game_over:
		draw_string(font, Vector2(0, tray_y + cell * 1.4), "no room left — tap to restart",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(cell * 0.42), Color(0.8, 0.82, 0.9))

func _draw_ghost() -> void:
	if drag_index < 0 or tray[drag_index] == null:
		return
	var e = tray[drag_index]
	var shape: Array = CR.SHAPES[e.shape_id]
	var a := _grid_anchor(drag_pos, shape)
	var ok: bool = rules.fits(shape, a.x, a.y)
	var col: Color = PALETTE[e.colour % PALETTE.size()]
	col.a = 0.45 if ok else 0.15
	for o in shape:
		var r := Rect2(board_origin + Vector2(a.x + o.x, a.y + o.y) * cell + Vector2(2, 2), Vector2(cell - 4, cell - 4))
		draw_rect(r, col)
	# The carried piece: full board scale, above the finger, fully visible.
	var lift := _lift_origin(drag_pos, shape)
	for o in shape:
		draw_rect(Rect2(lift + Vector2(o.x, o.y) * cell + Vector2(2, 2), Vector2(cell - 4, cell - 4)), PALETTE[e.colour % PALETTE.size()])

func _draw_tray(vp: Vector2) -> void:
	var base_y := tray_y
	for i in tray.size():
		if tray[i] == null or i == drag_index:
			continue
		var e = tray[i]
		var shape: Array = CR.SHAPES[e.shape_id]
		var s := cell * TRAY_SCALE   # small at rest, full size when lifted (presentation study)
		var cx := tray_slot_w * (i + 0.5)
		for o in shape:
			draw_rect(Rect2(Vector2(cx, base_y) + Vector2(o.x, o.y) * s - Vector2(s * 0.5, s * 0.5), Vector2(s - 4, s - 4)), PALETTE[e.colour % PALETTE.size()])
