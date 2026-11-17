# GLASS POP — Fill the Shape. Production port of the locked rules
# (claude/design/GAME-LOCKED-fill-the-shape.md). Placeholder art only: no final
# visuals, no sound, no ads - ad moments exist as hooks, nothing is served.
extends Node2D

const FR := preload("res://scripts/fill_rules.gd")
const CONFIG_PATH := "res://config/default.json"
const SAVE_PATH := "user://save.json"

const PALETTE := [
	Color(0.90, 0.32, 0.34), Color(0.26, 0.60, 0.88), Color(0.96, 0.76, 0.24),
	Color(0.36, 0.76, 0.45), Color(0.68, 0.45, 0.85), Color(0.95, 0.55, 0.25),
]
const HOLE := Color(0.20, 0.22, 0.30)
const HOLE_BAD := Color(0.55, 0.16, 0.20)
const BG := Color(0.09, 0.10, 0.14)
const TRAY_SCALE := 0.62

var cfg := {}
var rng := RandomNumberGenerator.new()

# round state
var target: Array[Vector2i] = []
var holes := {}                 # open cells
var filled := {}                # cell -> tray index
var pieces: Array = []          # [{cells, real, placed, offset}]
var tier := 1
var timer_len := 12.0
var time_left := 0.0
var round_live := false
var dead_end := false
var pulse := 0.0

# session state
var score := 0
var streak := 0
var wins_in_tier := 0
var losses_in_row := 0
var free_bonus_left := 1
var last_result := ""

# layout
var cell := 40.0
var board_origin := Vector2.ZERO
var score_h := 0.0
var tray_top := 0.0
var banner_px := 0.0
var drag_index := -1
var drag_pos := Vector2.ZERO
var press_cell := Vector2i(-99, -99)

func _ready() -> void:
	rng.randomize()
	cfg = _load_config()
	tier = 1
	timer_len = _tier_cfg().timer_start
	_load_game()
	_layout()
	get_window().size_changed.connect(func(): _layout(); queue_redraw())
	_new_round()

func _load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _tier_cfg() -> Dictionary:
	for t in cfg.get("tiers", []):
		if int(t.tier) == tier:
			return t
	return cfg.tiers[0]

func _dp() -> float:
	var dpi := DisplayServer.screen_get_dpi()
	return 3.0 if dpi <= 0 else float(dpi) / 160.0

# ------------------------------------------------------------------- round

func _new_round() -> void:
	var tc := _tier_cfg()
	var names: Array = tc.shapes.keys()
	var shape: Array = tc.shapes[names[rng.randi_range(0, names.size() - 1)]]
	target = []
	for c in shape:
		target.append(Vector2i(int(c[0]), int(c[1])))
	var r: Dictionary = FR.make_round(target, int(cfg.tray_size), bool(tc.decoys),
		int(cfg.max_piece_cells), rng)
	if not r.ok:
		return
	pieces = []
	for p in r.pieces:
		pieces.append({"cells": p.cells, "real": p.real, "placed": false, "offset": Vector2i.ZERO})
	holes = {}
	for c in target:
		holes[c] = true
	filled = {}
	time_left = timer_len
	round_live = true
	dead_end = false
	last_result = ""
	_layout()
	queue_redraw()

func _process(delta: float) -> void:
	if round_live:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_lose_round()
		queue_redraw()
	elif pulse > 0.0:
		pulse = max(0.0, pulse - delta)
		queue_redraw()

func _win_round() -> void:
	round_live = false
	var secs := int(ceil(time_left))
	var mults: Array = cfg.streak_multipliers
	var mult: float = mults[min(streak, mults.size() - 1)]
	score += int((int(cfg.score_tier_points) * tier + int(cfg.score_per_second_left) * secs) * mult)
	streak += 1
	wins_in_tier += 1
	losses_in_row = 0
	# Dealer: every win tightens the clock; four wins move up a tier.
	timer_len = max(float(_tier_cfg().timer_floor), timer_len + float(cfg.dealer_win_timer_delta))
	if wins_in_tier >= int(cfg.dealer_wins_to_tier_up) and tier < cfg.tiers.size():
		tier += 1
		wins_in_tier = 0
		timer_len = float(_tier_cfg().timer_start)
	last_result = "filled!"
	_save_game()
	_new_round()

func _lose_round() -> void:
	round_live = false
	streak = 0
	losses_in_row += 1
	timer_len = min(float(_tier_cfg().timer_start), timer_len + float(cfg.dealer_loss_timer_delta))
	if losses_in_row >= int(cfg.dealer_losses_to_tier_down) and tier > 1:
		tier -= 1
		losses_in_row = 0
		wins_in_tier = 0
		timer_len = float(_tier_cfg().timer_start)
	last_result = "%d / %d cells filled" % [target.size() - holes.size(), target.size()]
	_save_game()

func _check_dead_end() -> void:
	var left := []
	for p in pieces:
		if not p.placed:
			left.append(p.cells)
	dead_end = not FR.can_finish(holes.duplicate(), left)
	if dead_end:
		pulse = 1.0

# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventMouseButton:
		if e.pressed:
			if not round_live:
				_after_round_tap(e.position)
				return
			drag_pos = e.position
			drag_index = _tray_hit(e.position)
			press_cell = _cell_at(e.position)
		else:
			if drag_index >= 0:
				_try_drop(e.position)
				drag_index = -1
			elif round_live and press_cell == _cell_at(e.position):
				_take_back(press_cell)
			press_cell = Vector2i(-99, -99)
		queue_redraw()
	elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and drag_index >= 0:
		drag_pos = e.position
		queue_redraw()

func _after_round_tap(pos: Vector2) -> void:
	# Time-up screen. The first extra time of a session is free and carries no ad;
	# after that this is where the rewarded offer goes (Monetization owns cadence).
	if holes.size() > 0 and free_bonus_left > 0 and pos.y > get_viewport_rect().size.y * 0.5:
		free_bonus_left -= 1
		time_left = float(cfg.time_bonus_seconds)
		round_live = true
		queue_redraw()
		return
	_new_round()

func _tray_hit(pos: Vector2) -> int:
	if pos.y < tray_top:
		return -1
	var col := int(pos.x / (get_viewport_rect().size.x / 3.0))
	var row := int((pos.y - tray_top) / (cell * TRAY_SCALE * 3.0))
	var idx := row * 3 + col
	if idx < 0 or idx >= pieces.size() or pieces[idx].placed:
		return -1
	return idx

func _cell_at(pos: Vector2) -> Vector2i:
	var local := pos - board_origin
	return Vector2i(int(floor(local.x / cell)), int(floor(local.y / cell)))

func _shape_extent(shape: Array) -> Vector2:
	var w := 0
	var h := 0
	for o in shape:
		w = max(w, int(o.x) + 1)
		h = max(h, int(o.y) + 1)
	return Vector2(w, h)

# Carried piece sits above the finger at full board scale, and lands where it is
# drawn - the Owner lost sight of the piece under his thumb in the first build.
func _lift_origin(pos: Vector2, shape: Array) -> Vector2:
	var e := _shape_extent(shape)
	return pos + Vector2(-e.x * cell * 0.5, -e.y * cell - cell * 0.9)

func _anchor(pos: Vector2, shape: Array) -> Vector2i:
	var local := _lift_origin(pos, shape) - board_origin
	return Vector2i(int(round(local.x / cell)), int(round(local.y / cell)))

func _try_drop(pos: Vector2) -> void:
	var p: Dictionary = pieces[drag_index]
	var a := _anchor(pos, p.cells)
	for c in p.cells:
		if not holes.has(c + a):
			return
	for c in p.cells:
		holes.erase(c + a)
		filled[c + a] = drag_index
	p.placed = true
	p.offset = a
	if holes.is_empty():
		_win_round()
	else:
		_check_dead_end()

func _take_back(c: Vector2i) -> void:
	if not filled.has(c):
		return
	var idx: int = filled[c]
	var p: Dictionary = pieces[idx]
	for q in p.cells:
		var t: Vector2i = q + p.offset
		filled.erase(t)
		holes[t] = true
	p.placed = false
	_check_dead_end()

# ----------------------------------------------------------------- layout

func _layout() -> void:
	var vp := get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var top := 0.0
	if safe.size.y > 0 and safe.size.y < DisplayServer.screen_get_size().y:
		top = float(safe.position.y) / float(DisplayServer.screen_get_size().y) * vp.y
	var banner_dp: float = 0.0
	if bool(cfg.get("banner_enabled", false)):
		banner_dp = min(float(cfg.get("banner_height_dp", 50)), float(cfg.get("banner_max_height_dp", 50)))
	banner_px = banner_dp * _dp()
	score_h = vp.y * 0.15
	var ext := _shape_extent(target) if not target.is_empty() else Vector2(4, 4)
	var budget_h: float = vp.y - top - score_h - banner_px
	# Board gets the middle; the tray needs about 6 cells of height at tray scale.
	cell = floor(min(vp.x * 0.92 / max(ext.x, 3.0),
		budget_h / (max(ext.y, 3.0) + 6.0 * TRAY_SCALE + 1.2)))
	cell = max(cell, 12.0)
	var bw := ext.x * cell
	board_origin = Vector2((vp.x - bw) * 0.5, top + score_h)
	tray_top = board_origin.y + ext.y * cell + cell * 0.8

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var font := ThemeDB.fallback_font
	# Score is the biggest element on screen (presentation study 3.1).
	draw_string(font, Vector2(0, score_h * 0.62), str(score), HORIZONTAL_ALIGNMENT_CENTER,
		vp.x, int(score_h * 0.52), Color(1, 1, 1))
	var mults: Array = cfg.streak_multipliers
	var mult: float = mults[min(streak, mults.size() - 1)]
	draw_string(font, Vector2(16, score_h * 0.9), "tier %d   x%.1f" % [tier, mult],
		HORIZONTAL_ALIGNMENT_LEFT, vp.x, int(score_h * 0.17), Color(0.7, 0.75, 0.85))
	# Timer bar
	var frac: float = 0.0 if timer_len <= 0.0 else clampf(time_left / timer_len, 0.0, 1.0)
	var bar := Rect2(Vector2(vp.x * 0.08, score_h * 0.95), Vector2(vp.x * 0.84, max(6.0, cell * 0.12)))
	draw_rect(bar, Color(0.18, 0.2, 0.26))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)),
		Color(0.95, 0.4, 0.35) if frac < 0.3 else Color(0.4, 0.78, 0.95))

	for c in target:
		var r := Rect2(board_origin + Vector2(c) * cell + Vector2(2, 2), Vector2(cell - 4, cell - 4))
		if filled.has(c):
			draw_rect(r, PALETTE[int(filled[c]) % PALETTE.size()])
		else:
			var col := HOLE
			if dead_end:
				col = HOLE.lerp(HOLE_BAD, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))
			draw_rect(r, col)

	if drag_index >= 0:
		_draw_carried()
	_draw_tray(vp)

	if dead_end and round_live:
		draw_string(font, Vector2(0, tray_top - cell * 0.25),
			"Raasta band — tap a placed piece to take it back", HORIZONTAL_ALIGNMENT_CENTER,
			vp.x, int(cell * 0.34), Color(0.98, 0.6, 0.55))
	if not round_live:
		draw_string(font, Vector2(0, vp.y * 0.56), last_result, HORIZONTAL_ALIGNMENT_CENTER,
			vp.x, int(cell * 0.45), Color(1, 1, 1))
		var hint := "tap for +%d seconds (free)" % int(cfg.time_bonus_seconds) if (free_bonus_left > 0 and holes.size() > 0) else "tap to play the next shape"
		draw_string(font, Vector2(0, vp.y * 0.62), hint, HORIZONTAL_ALIGNMENT_CENTER,
			vp.x, int(cell * 0.33), Color(0.75, 0.8, 0.9))

func _draw_carried() -> void:
	var p: Dictionary = pieces[drag_index]
	var a := _anchor(drag_pos, p.cells)
	var ok := true
	for c in p.cells:
		if not holes.has(c + a):
			ok = false
			break
	var col: Color = PALETTE[drag_index % PALETTE.size()]
	var ghost := col
	ghost.a = 0.45 if ok else 0.12
	for c in p.cells:
		draw_rect(Rect2(board_origin + Vector2(c + a) * cell + Vector2(2, 2),
			Vector2(cell - 4, cell - 4)), ghost)
	var lift := _lift_origin(drag_pos, p.cells)
	for c in p.cells:
		draw_rect(Rect2(lift + Vector2(c) * cell + Vector2(2, 2), Vector2(cell - 4, cell - 4)), col)

func _draw_tray(vp: Vector2) -> void:
	var slot_w := vp.x / 3.0
	var s := cell * TRAY_SCALE
	for i in pieces.size():
		if pieces[i].placed or i == drag_index:
			continue
		var row := i / 3
		var col_i := i % 3
		var centre := Vector2(slot_w * (col_i + 0.5), tray_top + s * 3.0 * row + s * 1.5)
		var e := _shape_extent(pieces[i].cells)
		var base := centre - Vector2(e.x, e.y) * s * 0.5
		for c in pieces[i].cells:
			draw_rect(Rect2(base + Vector2(c) * s, Vector2(s - 3, s - 3)), PALETTE[i % PALETTE.size()])

# ------------------------------------------------------------------- save

func _save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"score": score, "tier": tier, "timer_len": timer_len,
		"wins_in_tier": wins_in_tier, "losses_in_row": losses_in_row, "streak": streak}))

func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	score = int(d.get("score", 0))
	tier = clampi(int(d.get("tier", 1)), 1, cfg.tiers.size())
	timer_len = float(d.get("timer_len", _tier_cfg().timer_start))
	wins_in_tier = int(d.get("wins_in_tier", 0))
	losses_in_row = int(d.get("losses_in_row", 0))
	streak = int(d.get("streak", 0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_save_game()
