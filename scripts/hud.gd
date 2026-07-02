class_name Hud
extends CanvasLayer
## In-flight HUD (PLAN.md D4, grown through E4/H): console gauges, weapon selector,
## score/level, kill counter for locked arenas, radar, message line, damage flash.
## Built entirely in code at the 320x200 design resolution; Phase G restyles it into
## the sculpted cockpit console.

const W := 320
const H := 200

var player: PlayerShip
var enemy_mgr: EnemyManager
var shot_mgr: ShotManager
var weapon_names: Array[String] = []

var _flash: ColorRect
var _msg: Label
var _msg_t := 0.0
var _kill_label: Label
var _level_speed: Label
var _score: Label
var _weapon_labels: Array[Label] = []
var _shield_bar: ColorRect
var _energy_bar: ColorRect
var _heat_bar: ColorRect
var _shield_num: Label
var _wpn_name: Label
var _crosshair: Control
var radar: RadarDisplay

const BAR_W := 44.0


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
	_crosshair = Control.new()
	_crosshair.position = Vector2(W / 2.0, H / 2.0)
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)
	_msg = _label(root, Vector2(0, 30), "", Color("ff7b5a"), 8)
	_msg.size = Vector2(W, 10)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_label = _label(root, Vector2(0, 42), "", Color("ffd34d"), 8)
	_kill_label.size = Vector2(W, 10)
	_kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_speed = _label(root, Vector2(8, 8), "LVL 1 · VEL 18", Color("5fb6d8"), 8)
	radar = RadarDisplay.new()
	radar.position = Vector2(W - 52, 6)
	radar.size = Vector2(46, 46)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radar)
	# ---- bottom console strip ----
	var console := ColorRect.new()
	console.color = Color(0.02, 0.03, 0.06, 0.75)
	console.position = Vector2(0, H - 30)
	console.size = Vector2(W, 30)
	console.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(console)
	_label(console, Vector2(6, 3), "SHLD", Color("62ffae"), 8)
	_shield_bar = _bar(console, Vector2(32, 5), Color("37ff9a"))
	_shield_num = _label(console, Vector2(80, 3), "100", Color("62ffae"), 8)
	_label(console, Vector2(6, 16), "ENRG", Color("7fd8ff"), 8)
	_energy_bar = _bar(console, Vector2(32, 18), Color("41c8ff"))
	_label(console, Vector2(228, 16), "HEAT", Color("ffab66"), 8)
	_heat_bar = _bar(console, Vector2(258, 18), Color("ff9a30"))
	_score = _label(console, Vector2(0, 3), "SCORE 0", Color("ffd34d"), 8)
	_score.position = Vector2(W / 2.0 - 40, 3)
	_score.size = Vector2(80, 10)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in 4:
		var wl := _label(console, Vector2(112 + i * 12, 16), str(i + 1), Color("5fb6d8"), 8)
		_weapon_labels.append(wl)
	_wpn_name = _label(console, Vector2(164, 16), "", Color("9fe8ff"), 8)
	GameState.shields_changed.connect(func(_v: float) -> void: _update_bars())
	GameState.energy_changed.connect(func(_v: float) -> void: _update_bars())
	GameState.heat_changed.connect(func(_v: float) -> void: _update_bars())
	GameState.score_changed.connect(func(v: int) -> void: _score.text = "SCORE %d" % v)
	GameState.weapon_changed.connect(func(_i: int) -> void: _update_weapons())


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


func show_message(text: String) -> void:
	_msg.text = text
	_msg_t = 1.2


func set_kill_counter(kills: int, target: int) -> void:
	if target <= 0:
		_kill_label.text = ""
	else:
		_kill_label.text = "HOSTILES %03d/%03d" % [kills, target]


func _process(delta: float) -> void:
	_msg_t -= delta
	_msg.visible = _msg_t > 0.0
	if player:
		_flash.color.a = minf(1.0, player.shake * 1.6) * 0.3
		_level_speed.text = "LVL %d · VEL %d" % [GameState.level_index + 1, int(player.speed)]
	_crosshair.queue_redraw()


func _draw_crosshair() -> void:
	var hot := GameState.is_overheated
	var col := Color("ff5030") if hot else Color("62ffd0")
	for arm in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		_crosshair.draw_line(arm * 3.0, arm * 8.0, col, 1.0)


func _update_bars() -> void:
	_shield_bar.size.x = BAR_W * GameState.shields / GameState.MAX_SHIELDS
	_energy_bar.size.x = BAR_W * GameState.energy / GameState.MAX_ENERGY
	_heat_bar.size.x = BAR_W * GameState.heat / GameState.MAX_HEAT
	_shield_num.text = str(int(GameState.shields))
	_heat_bar.color = Color("ff3010") if GameState.is_overheated else Color("ff9a30")


func _update_weapons() -> void:
	for i in _weapon_labels.size():
		var on := i == GameState.weapon_index
		_weapon_labels[i].add_theme_color_override(
			"font_color", Color("ffd34d") if on else Color("35506a"))
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
	back.color = Color(0.02, 0.04, 0.07)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.position = Vector2(1, 1)
	fill.size = Vector2(BAR_W, 5)
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return fill
