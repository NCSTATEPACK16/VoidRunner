class_name Hud
extends CanvasLayer
## In-flight HUD (PLAN.md D4, grown through E4/H, restyled in G4): the cockpit —
## canopy struts with a THREAT panel, and a sculpted bottom console holding the
## weapon selector, MISL ammo counter, TIME clock, kill counter over the radar,
## and SHLD/ENRG/HEAT bars. Built entirely in code at the 320x200 design
## resolution with flat 90s greys and blocky 3x5 bitmap digits (PROJECT.md §11.2).

const W := 320
const H := 200
const CONSOLE_H := 36
const CONSOLE_Y := H - CONSOLE_H

const BAR_W := 40.0
const THREAT_RANGE_SQ := 70.0 * 70.0

const PANEL := Color(0.145, 0.155, 0.175)
const PANEL_DARK := Color(0.075, 0.082, 0.10)
const PANEL_EDGE := Color(0.30, 0.32, 0.36)
const DIGIT_COL := Color("ff9a30")
const DIGIT_DIM := Color(0.35, 0.22, 0.10)

## 3x5 bitmap glyphs, one int per row, 3 bits per row (MSB = left pixel).
const GLYPHS := {
	"0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [7, 1, 7, 4, 7],
	"3": [7, 1, 7, 1, 7], "4": [5, 5, 7, 1, 1], "5": [7, 4, 7, 1, 7],
	"6": [7, 4, 7, 5, 7], "7": [7, 1, 1, 2, 2], "8": [7, 5, 7, 5, 7],
	"9": [7, 5, 7, 1, 7], ":": [0, 2, 0, 2, 0], "/": [1, 1, 2, 4, 4],
	"-": [0, 0, 7, 0, 0], " ": [0, 0, 0, 0, 0],
}

var player: PlayerShip
var enemy_mgr: EnemyManager
var shot_mgr: ShotManager
var weapon_names: Array[String] = []

var _flash: ColorRect
var _msg: Label
var _msg_t := 0.0
var _level_speed: Label
var _score: Label
var _wpn_name: Label
var _shield_bar: ColorRect
var _energy_bar: ColorRect
var _heat_bar: ColorRect
var _shield_num: Label
var _crosshair: Control
var _canopy: Control
var _console_draw: Control
var _kills := 0
var _kill_target := 0
var _threat := false
var _boss_name: Label
var _combo: Label
var radar: RadarDisplay


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0.1, 0.05, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	# canopy frame under everything else so readouts stay on top
	_canopy = Control.new()
	_canopy.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canopy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canopy.draw.connect(_draw_canopy)
	root.add_child(_canopy)
	_crosshair = Control.new()
	_crosshair.position = Vector2(W / 2.0, H / 2.0)
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)
	_msg = _label(root, Vector2(0, 30), "", Color("ff7b5a"), 8)
	_msg.size = Vector2(W, 10)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Phase J: boss name over the boss health bar (the 3x5 font is digits-only)
	_boss_name = _label(root, Vector2(0, 22), "", Color("ff7050"), 8)
	_boss_name.size = Vector2(W, 10)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.visible = false
	_level_speed = _label(root, Vector2(8, 6), "LVL 1 · VEL 18", Color("5fb6d8"), 8)
	_score = _label(root, Vector2(8, 16), "SCORE 0", Color("ffd34d"), 8)
	# Phase J: kill-streak multiplier readout
	_combo = _label(root, Vector2(8, 26), "", Color("ff9a30"), 8)
	_combo.visible = false
	# ---- bottom console ----
	_console_draw = Control.new()
	_console_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_console_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_draw.draw.connect(_draw_console)
	root.add_child(_console_draw)
	radar = RadarDisplay.new()
	radar.position = Vector2(W / 2.0 - 13, CONSOLE_Y + 7)
	radar.size = Vector2(26, 26)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radar)
	_label(root, Vector2(214, CONSOLE_Y + 2), "SHLD", Color("62ffae"), 8)
	_shield_bar = _bar(root, Vector2(242, CONSOLE_Y + 4), Color("37ff9a"))
	_shield_num = _label(root, Vector2(290, CONSOLE_Y + 2), "100", Color("62ffae"), 8)
	_label(root, Vector2(214, CONSOLE_Y + 13), "ENRG", Color("7fd8ff"), 8)
	_energy_bar = _bar(root, Vector2(242, CONSOLE_Y + 15), Color("41c8ff"))
	_label(root, Vector2(214, CONSOLE_Y + 24), "HEAT", Color("ffab66"), 8)
	_heat_bar = _bar(root, Vector2(242, CONSOLE_Y + 26), Color("ff9a30"))
	_wpn_name = _label(root, Vector2(8, CONSOLE_Y + 24), "", Color("9fe8ff"), 8)
	GameState.shields_changed.connect(func(_v: float) -> void: _update_bars())
	GameState.energy_changed.connect(func(_v: float) -> void: _update_bars())
	GameState.heat_changed.connect(func(_v: float) -> void: _update_bars())
	GameState.score_changed.connect(func(v: int) -> void: _score.text = "SCORE %d" % v)
	GameState.weapon_changed.connect(func(_i: int) -> void: _update_weapons())
	GameState.combo_changed.connect(func(_count: int, mult: int) -> void:
		_combo.visible = mult >= 2
		_combo.text = "COMBO x%d" % mult)


func setup(p: PlayerShip, em: EnemyManager, sm: ShotManager, names: Array[String]) -> void:
	player = p
	enemy_mgr = em
	shot_mgr = sm
	weapon_names = names
	radar.player = p
	radar.enemy_mgr = em
	radar.shot_mgr = sm
	_update_weapons()
	_update_bars()


func show_message(text: String, t := 1.2) -> void:
	_msg.text = text
	_msg_t = t


func set_kill_counter(kills: int, target: int) -> void:
	_kills = kills
	_kill_target = target


func set_boss_name(text: String) -> void:
	_boss_name.text = text


func _process(delta: float) -> void:
	_msg_t -= delta
	_msg.visible = _msg_t > 0.0
	if player:
		var a := minf(1.0, player.shake * 1.6) * 0.3
		# Phase J: low-shield warning pulse under everything else
		if GameState.shields < 25.0 and not GameState.is_dead:
			a = maxf(a, (sin(Time.get_ticks_msec() / 160.0) * 0.5 + 0.5) * 0.14)
		_flash.color.a = a
		_level_speed.text = "LVL %d · VEL %d" % [GameState.level_index + 1, int(player.speed)]
	_threat = false
	if shot_mgr and player:
		for p in shot_mgr.enemy_shot_positions():
			if p.distance_squared_to(player.position) < THREAT_RANGE_SQ:
				_threat = true
				break
	_boss_name.visible = enemy_mgr != null and not enemy_mgr.boss.is_empty()
	_crosshair.queue_redraw()
	_canopy.queue_redraw()
	_console_draw.queue_redraw()


func _draw_crosshair() -> void:
	var hot := GameState.is_overheated
	var col := Color("ff5030") if hot else Color("62ffd0")
	for arm in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		_crosshair.draw_line(arm * 3.0, arm * 8.0, col, 1.0)


## G4: canopy frame — angled side struts with brace lines and the THREAT panel
## top-center, all flat fills per the reference-screenshot anatomy.
func _draw_canopy() -> void:
	var c := _canopy
	var floor_y := float(CONSOLE_Y)
	# left strut: wide at the top corner, tapering toward the console
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(0, 0), Vector2(24, 0), Vector2(9, 46), Vector2(0, 62),
	]), PANEL_DARK)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(0, floor_y), Vector2(0, floor_y - 34), Vector2(12, floor_y),
	]), PANEL_DARK)
	c.draw_line(Vector2(24, 0), Vector2(9, 46), PANEL_EDGE)
	c.draw_line(Vector2(9, 46), Vector2(0, 62), PANEL_EDGE)
	c.draw_line(Vector2(0, floor_y - 34), Vector2(12, floor_y), PANEL_EDGE)
	c.draw_line(Vector2(14, 8), Vector2(6, 30), Color(0.20, 0.21, 0.24))
	# right strut, mirrored
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(W, 0), Vector2(W - 24, 0), Vector2(W - 9, 46), Vector2(W, 62),
	]), PANEL_DARK)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(W, floor_y), Vector2(W, floor_y - 34), Vector2(W - 12, floor_y),
	]), PANEL_DARK)
	c.draw_line(Vector2(W - 24, 0), Vector2(W - 9, 46), PANEL_EDGE)
	c.draw_line(Vector2(W - 9, 46), Vector2(W, 62), PANEL_EDGE)
	c.draw_line(Vector2(W, floor_y - 34), Vector2(W - 12, floor_y), PANEL_EDGE)
	c.draw_line(Vector2(W - 14, 8), Vector2(W - 6, 30), Color(0.20, 0.21, 0.24))
	# THREAT panel top-center: label plate + warning light
	c.draw_rect(Rect2(W / 2.0 - 20, 0, 40, 11), PANEL_DARK)
	c.draw_rect(Rect2(W / 2.0 - 20, 10, 40, 1), PANEL_EDGE)
	var lit := _threat and int(Time.get_ticks_msec() / 180) % 2 == 0
	c.draw_rect(Rect2(W / 2.0 - 14, 3, 5, 5), Color("ff3018") if lit else Color(0.22, 0.09, 0.07))
	_draw_text3x5(c, Vector2(W / 2.0 - 6, 3), "-", 1, DIGIT_DIM)  # spacer tick
	var threat_col := Color("ff5030") if _threat else Color(0.36, 0.20, 0.16)
	c.draw_rect(Rect2(W / 2.0 - 4, 4, 22, 3), threat_col)
	# Phase J: boss health bar under the THREAT panel — chunky rect, white damage
	# flash, tick marks at the 66%/33% phase gates
	if enemy_mgr and not enemy_mgr.boss.is_empty():
		var b: Dictionary = enemy_mgr.boss
		c.draw_rect(Rect2(100, 13, 120, 8), PANEL_DARK)
		c.draw_rect(Rect2(100, 13, 120, 8), PANEL_EDGE, false)
		var frac: float = b.hp / float(b.max_hp)
		var fill_col := Color("e8ecf4") if b.flash_t > 0.0 else Color("ff3838")
		c.draw_rect(Rect2(102, 15, maxf(0.0, 116.0 * frac), 4), fill_col)
		for gate in [0.66, 0.33]:
			c.draw_rect(Rect2(102 + int(116 * gate), 14, 1, 6), PANEL_EDGE)


## G4: sculpted console plate — bevel lines, weapon slot row, MISL ammo digits,
## TIME clock, and the kill counter over the radar, in blocky 3x5 digits.
func _draw_console() -> void:
	var c := _console_draw
	c.draw_rect(Rect2(0, CONSOLE_Y, W, CONSOLE_H), PANEL)
	c.draw_rect(Rect2(0, CONSOLE_Y, W, 1), PANEL_EDGE)
	c.draw_rect(Rect2(0, CONSOLE_Y + 1, W, 1), PANEL_DARK)
	# recessed wells: weapons / time / radar / bars
	c.draw_rect(Rect2(4, CONSOLE_Y + 4, 100, CONSOLE_H - 8), PANEL_DARK)
	c.draw_rect(Rect2(110, CONSOLE_Y + 4, 40, CONSOLE_H - 8), PANEL_DARK)
	c.draw_rect(Rect2(W / 2.0 - 16, CONSOLE_Y + 4, 32, CONSOLE_H - 8), PANEL_DARK)
	c.draw_rect(Rect2(210, CONSOLE_Y + 4, 106, CONSOLE_H - 8), PANEL_DARK)
	# weapon slots 1-4
	for i in 4:
		var r := Rect2(8 + i * 13, CONSOLE_Y + 6, 11, 11)
		var on := i == GameState.weapon_index
		c.draw_rect(r, Color(0.24, 0.17, 0.08) if on else Color(0.10, 0.11, 0.13))
		c.draw_rect(r, DIGIT_COL if on else Color(0.24, 0.26, 0.30), false)
		_draw_text3x5(c, r.position + Vector2(4, 3), str(i + 1), 1,
			DIGIT_COL if on else Color(0.40, 0.43, 0.48))
	# MISL ammo (live with Phase I2)
	_draw_text3x5(c, Vector2(64, CONSOLE_Y + 7), "%02d" % GameState.missiles, 2,
		DIGIT_COL if GameState.missiles > 0 else Color("ff3018"))
	_draw_text3x5(c, Vector2(64, CONSOLE_Y + 20), "-", 1, DIGIT_DIM)
	# TIME clock
	_draw_text3x5(c, Vector2(114, CONSOLE_Y + 7), _time_string(), 2, DIGIT_COL)
	# kill counter over the radar (only while an arena lock is active)
	if _kill_target > 0:
		var s := "%03d/%03d" % [_kills, _kill_target]
		_draw_text3x5(c, Vector2(W / 2.0 - s.length() * 2.0, CONSOLE_Y - 8), s, 1, DIGIT_COL)


func _time_string() -> String:
	if not player:
		return "0:00"
	var t := int(player.elapsed)
	return "%d:%02d" % [t / 60, t % 60]


## Blocky 3x5 pixel digits, the DOS console look — px is the pixel scale.
func _draw_text3x5(ci: CanvasItem, pos: Vector2, text: String, px: int, color: Color) -> void:
	var x := pos.x
	for chr in text:
		var rows: Array = GLYPHS.get(chr, GLYPHS[" "])
		for ry in 5:
			for rx in 3:
				if rows[ry] & (4 >> rx):
					ci.draw_rect(Rect2(x + rx * px, pos.y + ry * px, px, px), color)
		x += 4 * px
	# colons render narrow; acceptable at this scale


func _update_bars() -> void:
	_shield_bar.size.x = BAR_W * GameState.shields / GameState.MAX_SHIELDS
	_energy_bar.size.x = BAR_W * GameState.energy / GameState.MAX_ENERGY
	_heat_bar.size.x = BAR_W * GameState.heat / GameState.MAX_HEAT
	_shield_num.text = str(int(GameState.shields))
	_heat_bar.color = Color("ff3010") if GameState.is_overheated else Color("ff9a30")


func _update_weapons() -> void:
	if not weapon_names.is_empty():
		_wpn_name.text = weapon_names[GameState.weapon_index]


func _label(parent: Control, pos: Vector2, text: String, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, pos: Vector2, color: Color) -> ColorRect:
	var back := ColorRect.new()
	back.position = pos
	back.size = Vector2(BAR_W + 2, 7)
	back.color = Color(0.03, 0.04, 0.06)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.position = Vector2(1, 1)
	fill.size = Vector2(BAR_W, 5)
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return fill
