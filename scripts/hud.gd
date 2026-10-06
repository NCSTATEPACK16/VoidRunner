class_name Hud
extends CanvasLayer
## In-flight HUD (PLAN.md D4, grown through E4/H, restyled in G4, rebuilt for
## 3.0 phase 4): the cockpit — brushed-steel canopy struts with a THREAT panel,
## and a painted console plate (HudArt) whose recessed wells hold the weapon
## selector and MSL counter, the TIME clock, the radar scope, the evade lamp and
## the SHLD/ENRG/HEAT LED gauges. Built entirely in code at the 320x200 design
## resolution with blocky 3x5 bitmap digits (PROJECT.md §11.2).

const W := 320
const H := 200
const CONSOLE_H := 36
const CONSOLE_Y := H - CONSOLE_H

## LED gauges: LED_N segments of LED_W px (1 px gaps) starting at LED_X
const LED_N := 12
const LED_W := 3
const LED_X := 244

const PANEL_DARK := Color(0.10, 0.12, 0.16)
const PANEL_EDGE := Color(0.46, 0.52, 0.64)
const DIGIT_COL := Color("ff9a30")
const DIGIT_DIM := Color(0.35, 0.22, 0.10)
const LABEL_DIM := Color(0.50, 0.56, 0.66)

# 3.0 phase 5: live power-up timers stack down the right side of the view
const POWER_ORDER := ["overdrive", "powercore", "phase"]
const POWER_NAMES := {"overdrive": "OVERDRIVE", "powercore": "POWER CORE", "phase": "PHASE SHIELD"}
const POWER_RAMPS := {"overdrive": Palette.GOLD, "powercore": Palette.MAGENTA, "phase": Palette.CYAN}
const POWER_Y := 46
const POWER_ROW := 14

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
var _bomb_flash: ColorRect   # V2.0 plasma bomb white-out, decays in _process
var _phase_tint: ColorRect   # 3.0: faint cyan glaze while PHASE SHIELD runs
## v4a: capped whole-screen flashes — red on a hit, gold on a pickup. At most one
## new flash every FLASH_GAP_MS (no more than 3 a second, the photosensitivity
## line); REDUCE FLASH scales them down. They sit under the palette layer, so they
## come out in palette colours like everything else.
const FLASH_GAP_MS := 340
const FLASH_FADE := 0.25
const FLASH_REDUCED := 0.35
var _tint_flash: ColorRect
var _tint_a0 := 0.0
var _tint_last_ms := -100000
var _power_draw: Control
var _power_labels := {}      # kind -> Label
var _c_power_live := false
var _c_xmode := -1           # crosshair colour state (overheat / power-ups)
var _msg: Label
var _msg_t := 0.0
var _level_speed: Label
var _score: Label
var _wpn_name: Label
var _shield_num: Label
var _crosshair: Control
var _canopy: Control
var _canopy_static: Control    # V2.1: struts/plates draw once, never per frame
var _console_draw: Control
# 3.0 phase 4: lit LED counts (shield, energy, heat) and the low-shield blink
# phase (-1 = steady) — the console redraws only when one of them changes
var _led := Vector3i(-1, -1, -1)
var _led_blink := -1
var _kills := 0
var _kill_target := 0
var _threat := false
var _boss_name: Label
var _combo: Label
var radar: RadarDisplay
# V2.1 dirty caches: each dynamic layer redraws only when its inputs change —
# the full cockpit was re-emitting dozens of draw calls every frame before
var _c_threat := false
var _c_blink := -2
var _c_pips := -1
var _c_boss_hp := -2
var _c_boss_flash := false
var _c_wpn := -1
var _c_missiles := -1
var _c_tsec := -1
var _c_kills := -1
var _c_ktarget := -1
var _c_dodge := false
var _c_hot := false
var _c_vel := -1
var _c_metric := -1
# V2.2 L1e: transient feedback — the crosshair layer redraws only while these live
var _kill_tick_t := 0.0
var _dmg_arcs: Array = []   # {angle: float, t: float}, newest appended
# V2.2 L2c: style meter — grade name pops on transitions, bar drains with the window
const STYLE_TH := [0, 3, 6, 10, 15]
var _style_name: Label
var _style_draw: Control
var _style_pop_t := 0.0
var _c_style_live := false


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
	_bomb_flash = ColorRect.new()
	_bomb_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bomb_flash.color = Color(0.95, 0.98, 1.0, 0.0)
	_bomb_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bomb_flash)
	_phase_tint = ColorRect.new()
	_phase_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_phase_tint.color = Color(0.3, 0.9, 1.0, 0.0)
	_phase_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_phase_tint)
	_tint_flash = ColorRect.new()   # v4a
	_tint_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint_flash.color = Color(1, 1, 1, 0.0)
	_tint_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tint_flash)
	# canopy frame under everything else so readouts stay on top; the static
	# frame draws once at boot, the dynamic layer sits directly on top of it
	_canopy_static = Control.new()
	_canopy_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canopy_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canopy_static.draw.connect(_draw_canopy_static)
	root.add_child(_canopy_static)
	_canopy = Control.new()
	_canopy.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canopy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canopy.draw.connect(_draw_canopy)
	root.add_child(_canopy)
	_crosshair = Control.new()
	_crosshair.position = Vector2(W / 2.0, H / 2.0)
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)
	_msg = _label(root, Vector2(0, 33), "", Color("ff7b5a"), 8)
	_msg.size = Vector2(W, 10)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Phase J: boss name over the boss health bar (the 3x5 font is digits-only)
	_boss_name = _label(root, Vector2(0, 22), "", Color("ff7050"), 8)
	_boss_name.size = Vector2(W, 10)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.visible = false
	# x=26 clears the left canopy strut (it reaches ~x=22 up top) so SCORE isn't
	# clipped to "ORE ..." behind the frame
	_level_speed = _label(root, Vector2(26, 6), "LVL 1 · VEL 18", Color("5fb6d8"), 8)
	_score = _label(root, Vector2(26, 16), "SCORE 0", Color("ffd34d"), 8)
	# Phase J: kill-streak multiplier readout
	_combo = _label(root, Vector2(26, 26), "", Color("ff9a30"), 8)
	# V2.2 L2c: style grade + drain bar directly under the combo readout
	_style_name = _label(root, Vector2(26, 36), "", Color("62ffd0"), 8)
	_style_name.visible = false
	_style_draw = Control.new()
	_style_draw.position = Vector2(26, 47)
	_style_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_draw.draw.connect(_draw_style)
	root.add_child(_style_draw)
	GameState.style_changed.connect(_on_style_changed)
	_combo.visible = false
	# 3.0 phase 5: power-up timers — a name and a draining bar per live one
	_power_draw = Control.new()
	_power_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_power_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_power_draw.draw.connect(_draw_power)
	root.add_child(_power_draw)
	for kind: String in POWER_ORDER:
		var pl := _label(root, Vector2(214, POWER_Y), POWER_NAMES[kind],
			Palette.ramp(POWER_RAMPS[kind], 13), 8)
		pl.size = Vector2(80, 10)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pl.visible = false
		_power_labels[kind] = pl
	# ---- bottom console: the painted plate (drawn once, at boot), then the
	# dynamic layer and labels in its wells (HudArt.WELLS) ----
	var plate := TextureRect.new()
	plate.texture = HudArt.console(W, CONSOLE_H)
	plate.position = Vector2(0, CONSOLE_Y)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	_console_draw = Control.new()
	_console_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_console_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_draw.draw.connect(_draw_console)
	root.add_child(_console_draw)
	radar = RadarDisplay.new()
	radar.position = Vector2(146, CONSOLE_Y + 4)
	radar.size = Vector2(28, 28)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radar)
	_label(root, Vector2(218, CONSOLE_Y + 6), "SHLD", Color("62ffae"), 8)
	_shield_num = _label(root, Vector2(296, CONSOLE_Y + 6), "100", Color("62ffae"), 8)
	_label(root, Vector2(218, CONSOLE_Y + 14), "ENRG", Color("7fd8ff"), 8)
	_label(root, Vector2(218, CONSOLE_Y + 22), "HEAT", Color("ffab66"), 8)
	_wpn_name = _label(root, Vector2(8, CONSOLE_Y + 21), "", Color("9fe8ff"), 8)
	_label(root, Vector2(82, CONSOLE_Y + 8), "MSL", LABEL_DIM, 8)
	_label(root, Vector2(111, CONSOLE_Y + 6), "TIME", LABEL_DIM, 8)
	_label(root, Vector2(186, CONSOLE_Y + 6), "EVD", Color("2f8a82"), 8)  # K4 lamp
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


## v4a: a whole-screen tint pop that fades over FLASH_FADE. Returns false (and
## does nothing) inside FLASH_GAP_MS of the last one — the 3-a-second cap.
func flash_tint(color: Color, strength: float) -> bool:
	var now := Time.get_ticks_msec()
	if now - _tint_last_ms < FLASH_GAP_MS:
		return false
	_tint_last_ms = now
	_tint_a0 = clampf(strength, 0.0, 0.6) * (FLASH_REDUCED if GameState.reduce_flashing else 1.0)
	_tint_flash.color = Color(color.r, color.g, color.b, _tint_a0)
	return true


## V2.0 plasma bomb white-out — bright pop that fades over ~0.4 s.
func flash_white() -> void:
	# M1.2: the full-screen white-out is the one effect here that plausibly crosses
	# the photosensitivity threshold, so the comfort option removes it outright
	# rather than dimming it — a faint grey wash reads as a bug, not a bomb.
	_bomb_flash.color.a = 0.10 if GameState.reduce_flashing else 0.55


func set_kill_counter(kills: int, target: int) -> void:
	_kills = kills
	_kill_target = target


func set_boss_name(text: String) -> void:
	_boss_name.text = text


## V2.2 L1e: 4 corner ticks pop off the crosshair for a beat on every kill.
func flash_kill_tick() -> void:
	_kill_tick_t = 0.15
	_crosshair.queue_redraw()


## V2.2 L1e: red arc at the screen edge pointing at whoever just hit us.
func show_damage_from(world_pos: Vector3) -> void:
	if player == null:
		return
	var local := (world_pos - player.position).rotated(Vector3.UP, -player.rotation.y)
	_dmg_arcs.append({"angle": atan2(local.x, -local.z), "t": 0.4})
	_crosshair.queue_redraw()


func _process(delta: float) -> void:
	_msg_t -= delta
	_msg.visible = _msg_t > 0.0
	_bomb_flash.color.a = maxf(0.0, _bomb_flash.color.a - delta * 1.4)
	if _tint_flash.color.a > 0.0:
		_tint_flash.color.a = maxf(0.0, _tint_flash.color.a - delta * _tint_a0 / FLASH_FADE)
	if player:
		# v4a: red now means "you were hit" (flash_tint, capped); shake alone no
		# longer reddens the screen, so a nearby blast reads as a blast
		var a := 0.0
		# Phase J: low-shield warning pulse under everything else
		if GameState.shields < 25.0 and not GameState.is_dead:
			# re-audit Step 6: under REDUCE FLASH the warning is a steady tint, not a pulse
			a = maxf(a, 0.07 if GameState.reduce_flashing \
				else (sin(Time.get_ticks_msec() / 160.0) * 0.5 + 0.5) * 0.14)
		_flash.color.a = a
		# only rebuild the readout string when the shown integers change
		var vel := int(player.speed)
		var metric := int(player.ring_idx * PathGen.SEG) if GameState.gauntlet_mode \
			else GameState.level_index + 1
		if vel != _c_vel or metric != _c_metric:
			_c_vel = vel
			_c_metric = metric
			if GameState.gauntlet_mode:   # K5: distance is the score here
				_level_speed.text = "DIST %dm · VEL %d" % [metric, vel]
			else:
				_level_speed.text = "LVL %d · VEL %d" % [metric, vel]
	_threat = shot_mgr != null and shot_mgr.threat_near
	# (v4b: a mini-boss's name and bar wait until it wakes)
	var boss_live := enemy_mgr != null and enemy_mgr.boss_visible()
	_boss_name.visible = boss_live
	# V2.1: each dynamic layer redraws only on state change
	# re-audit Step 6: REDUCE FLASH holds the lamp lit instead of blinking it
	var blink := (1 if GameState.reduce_flashing else int(Time.get_ticks_msec() / 180) % 2) \
		if _threat else -1
	var boss_hp := int(enemy_mgr.boss.hp) if boss_live else -1
	var boss_flash: bool = boss_live and enemy_mgr.boss.flash_t > 0.0
	if _threat != _c_threat or blink != _c_blink or GameState.plasma_bombs != _c_pips \
			or boss_hp != _c_boss_hp or boss_flash != _c_boss_flash:
		_c_threat = _threat
		_c_blink = blink
		_c_pips = GameState.plasma_bombs
		_c_boss_hp = boss_hp
		_c_boss_flash = boss_flash
		_canopy.queue_redraw()
	var dodge_busy := player != null and player.dodge_cd > 0.0
	var tsec := int(player.elapsed) if player else 0
	# 3.0 phase 4: the top lit SHLD segment blinks while shields are critical
	var led_blink := (0 if GameState.reduce_flashing else int(Time.get_ticks_msec() / 200) % 2) \
		if GameState.shields < GameState.max_shields() * 0.25 and not GameState.is_dead else -1
	if GameState.weapon_index != _c_wpn or GameState.missiles != _c_missiles \
			or tsec != _c_tsec or _kills != _c_kills or _kill_target != _c_ktarget \
			or dodge_busy or dodge_busy != _c_dodge or led_blink != _led_blink:
		_c_wpn = GameState.weapon_index
		_c_missiles = GameState.missiles
		_c_tsec = tsec
		_c_kills = _kills
		_c_ktarget = _kill_target
		_c_dodge = dodge_busy
		_led_blink = led_blink
		_console_draw.queue_redraw()
	if GameState.is_overheated != _c_hot:
		_c_hot = GameState.is_overheated
		_crosshair.queue_redraw()
		_console_draw.queue_redraw()   # HEAT LEDs go all-red on overheat
	_update_powers()
	# V2.2 L1e: tick down transient feedback; keep redrawing while live (the
	# final redraw after a timer expires is what clears it from the layer)
	if _kill_tick_t > 0.0:
		_kill_tick_t -= delta
		_crosshair.queue_redraw()
	if not _dmg_arcs.is_empty():
		for i in range(_dmg_arcs.size() - 1, -1, -1):
			_dmg_arcs[i].t -= delta
			if _dmg_arcs[i].t <= 0.0:
				_dmg_arcs.remove_at(i)
		_crosshair.queue_redraw()
	# V2.2 L2c: style meter animates only while a streak is live (dirty rule:
	# the one extra redraw after it dies is what clears the bar)
	if _style_pop_t > 0.0:
		_style_pop_t -= delta
		_style_name.scale = Vector2.ONE * (2.0 if _style_pop_t > 0.45 else 1.0)
	var style_live := GameState.style_grade() > 0
	if style_live:
		_style_name.text = GameState.STYLE_NAMES[GameState.style_grade()]
		_style_draw.queue_redraw()
	elif _c_style_live:
		_style_draw.queue_redraw()
	_style_name.visible = style_live
	_c_style_live = style_live


## 3.0 phase 5: re-pack the power-up stack as clocks start and run out, blink a
## name through its last two seconds, glaze the view during PHASE SHIELD, and
## tint the crosshair for the live power.
func _update_powers() -> void:
	var live := false
	var row := 0
	for kind: String in POWER_ORDER:
		var t: float = GameState.power_t[kind]
		var pl: Label = _power_labels[kind]
		if t > 0.0:
			live = true
			pl.position.y = POWER_Y + row * POWER_ROW
			pl.visible = t > 2.0 or int(t * 6.0) % 2 == 0
			row += 1
		else:
			pl.visible = false
	if live or _c_power_live:
		_power_draw.queue_redraw()   # the extra redraw after the last one ends clears it
	_c_power_live = live
	if GameState.power_on("phase"):
		_phase_tint.color.a = 0.07 if GameState.reduce_flashing \
			else 0.05 + 0.03 * sin(Time.get_ticks_msec() / 150.0)
	else:
		_phase_tint.color.a = 0.0
	var xmode := 3 if GameState.is_overheated else (2 if GameState.power_on("powercore") \
		else (1 if GameState.power_on("overdrive") else 0))
	if xmode != _c_xmode:
		_c_xmode = xmode
		_crosshair.queue_redraw()


## One draining bar under each live power-up's name, right-aligned with it.
func _draw_power() -> void:
	var row := 0
	for kind: String in POWER_ORDER:
		var t: float = GameState.power_t[kind]
		if t <= 0.0:
			continue
		var y := POWER_Y + row * POWER_ROW + 9
		var frac := clampf(t / float(GameState.POWER_TIME[kind]), 0.0, 1.0)
		_power_draw.draw_rect(Rect2(254, y, 40, 3), PANEL_DARK)
		_power_draw.draw_rect(Rect2(254, y, 40.0 * frac, 3), Palette.ramp(POWER_RAMPS[kind], 11))
		row += 1


## V2.2 L2c: signal-driven pop so the name scales up for a beat on every grade-up.
func _on_style_changed(grade: int) -> void:
	if grade > 0:
		_style_pop_t = 0.6
	_style_draw.queue_redraw()


## Bar fill = window time remaining × progress toward the next grade — it reads
## as "keep killing to hold the rank", which is exactly the mechanic.
func _draw_style() -> void:
	var g := GameState.style_grade()
	if g <= 0:
		return
	var time_frac := clampf(GameState.combo_t / GameState.COMBO_WINDOW, 0.0, 1.0)
	var prog := 1.0
	if g < 4:
		prog = float(GameState.combo - STYLE_TH[g]) / float(STYLE_TH[g + 1] - STYLE_TH[g])
	var fill := clampf(time_frac * clampf(prog, 0.0, 1.0), 0.0, 1.0)
	_style_draw.draw_rect(Rect2(0, 0, 42, 5), PANEL_DARK)
	_style_draw.draw_rect(Rect2(1, 1, 40.0 * fill, 3), Color("62ffd0"))


func _draw_crosshair() -> void:
	# overheat red wins; otherwise a live power-up tints it (3.0)
	var col := Color("62ffd0")
	match _c_xmode:
		3:
			col = Color("ff5030")
		2:
			col = Palette.ramp(Palette.MAGENTA, 13)
		1:
			col = Palette.ramp(Palette.GOLD, 14)
	for arm in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		_crosshair.draw_line(arm * 3.0, arm * 8.0, col, 1.0)
	# V2.2 L1e: kill tick — short diagonals off the crosshair corners
	if _kill_tick_t > 0.0:
		for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			_crosshair.draw_line(d * 9.0, d * 13.0, Color("ffd34d"), 1.0)
	# V2.2 L1e: damage arcs — screen-edge segments toward the shooter, angle 0 =
	# dead ahead = top of screen; draw_arc's 0 rad points right, hence the -PI/2
	for a in _dmg_arcs:
		var ca: float = a.angle - PI / 2.0
		_crosshair.draw_arc(Vector2.ZERO, 58.0, ca - 0.45, ca + 0.45, 10,
			Color(1.0, 0.28, 0.16, clampf(a.t / 0.4, 0.0, 1.0)), 3.0)


## G4: canopy frame — angled side struts with brace lines and the THREAT panel
## plate. 3.0 phase 4 skins them in brushed steel (HudArt.steel_tile, repeated),
## a shade darker than the console plate so the frame recedes.
## Drawn ONCE at boot (V2.1) — only the lamps/pips/boss bar live on the dynamic
## layer above.
func _draw_canopy_static() -> void:
	var c := _canopy_static
	c.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var tile := HudArt.steel_tile()
	var floor_y := float(CONSOLE_Y)
	var groove := Palette.ramp(Palette.STEEL, 2)
	for side in [1.0, -1.0]:
		# side = 1 draws the left strut; -1 mirrors every x onto the right one
		var ox := 0.0 if side > 0.0 else float(W)
		var upper := PackedVector2Array([
			Vector2(ox, 0), Vector2(ox + 24 * side, 0), Vector2(ox + 9 * side, 46), Vector2(ox, 62),
		])
		var lower := PackedVector2Array([
			Vector2(ox, floor_y), Vector2(ox, floor_y - 34), Vector2(ox + 12 * side, floor_y),
		])
		for poly in [upper, lower]:
			var uvs := PackedVector2Array()
			for p in poly:
				uvs.append(p / float(HudArt.TILE))
			c.draw_colored_polygon(poly, Color.WHITE, uvs, tile)
		c.draw_line(Vector2(ox + 24 * side, 0), Vector2(ox + 9 * side, 46), PANEL_EDGE)
		c.draw_line(Vector2(ox + 9 * side, 46), Vector2(ox, 62), PANEL_EDGE)
		c.draw_line(Vector2(ox, floor_y - 34), Vector2(ox + 12 * side, floor_y), PANEL_EDGE)
		c.draw_line(Vector2(ox + 14 * side, 8), Vector2(ox + 6 * side, 30), groove)
		# two rivets down each strut
		for rp in [Vector2(5, 6), Vector2(4, 40)]:
			var rx: float = ox + rp.x * side - (1.0 if side < 0.0 else 0.0)
			c.draw_rect(Rect2(rx, rp.y, 1, 1), Palette.ramp(Palette.STEEL, 12))
			c.draw_rect(Rect2(rx + 1, rp.y + 1, 1, 1), Palette.ramp(Palette.STEEL, 2))
	# THREAT panel plate top-center
	c.draw_texture_rect(tile, Rect2(W / 2.0 - 20, 0, 40, 11), true)
	c.draw_rect(Rect2(W / 2.0 - 20, 10, 40, 1), PANEL_EDGE)
	c.draw_rect(Rect2(W / 2.0 - 16, 2, 36, 7), PANEL_DARK)
	_draw_text3x5(c, Vector2(W / 2.0 - 6, 3), "-", 1, DIGIT_DIM)  # spacer tick


## Dynamic canopy layer: threat lamp/bar, plasma pips, boss bar. Redrawn only
## when one of those inputs changes (see the dirty caches in _process).
func _draw_canopy() -> void:
	var c := _canopy
	var lit := _threat and (GameState.reduce_flashing or int(Time.get_ticks_msec() / 180) % 2 == 0)
	c.draw_rect(Rect2(W / 2.0 - 14, 3, 5, 5), Color("ff3018") if lit else Color(0.22, 0.09, 0.07))
	var threat_col := Color("ff5030") if _threat else Color(0.36, 0.20, 0.16)
	c.draw_rect(Rect2(W / 2.0 - 4, 4, 22, 3), threat_col)
	# V2.0 plasma bomb rack, top-right (the original kept its counter there):
	# one hot pip per bomb held, empty sockets stay dark
	for i in GameState.PLASMA_MAX:
		var lit_pip := i < GameState.plasma_bombs
		c.draw_rect(Rect2(W - 60 + i * 8, 4, 5, 5),
			Color("ff9a30") if lit_pip else Color(0.16, 0.12, 0.09))
		if lit_pip:
			c.draw_rect(Rect2(W - 59 + i * 8, 5, 2, 2), Color("ffe0a0"))
	# Phase J: boss health bar under the THREAT panel — chunky rect, white damage
	# flash, tick marks at the 66%/33% phase gates (v4b: a mini-boss's one at 50%)
	if enemy_mgr and enemy_mgr.boss_visible():
		var b: Dictionary = enemy_mgr.boss
		c.draw_rect(Rect2(100, 13, 120, 8), PANEL_DARK)
		c.draw_rect(Rect2(100, 13, 120, 8), PANEL_EDGE, false)
		var frac: float = b.hp / float(b.max_hp)
		var fill_col := Color("e8ecf4") if b.flash_t > 0.0 else Color("ff3838")
		c.draw_rect(Rect2(102, 15, maxf(0.0, 116.0 * frac), 4), fill_col)
		for gate in boss_gates(b):
			c.draw_rect(Rect2(102 + int(116 * gate), 14, 1, 6), PANEL_EDGE)


## v4b: where the boss bar's phase ticks sit: a mini-boss turns at 50%, a boss at
## 66% and 33%.
static func boss_gates(b: Dictionary) -> Array:
	return [0.5] if b.get("miniboss", false) else [0.66, 0.33]


## Dynamic console layer: weapon slots, MSL digits, EVD lamp, TIME clock, the
## LED gauges and the kill counter — redrawn only when one of those changes.
func _draw_console() -> void:
	var c := _console_draw
	# weapon slots 1-4: the armed one glows amber, the rest are dark keycaps
	for i in 4:
		var r := Rect2(8 + i * 13, CONSOLE_Y + 6, 11, 11)
		var on := i == GameState.weapon_index
		c.draw_rect(r, Palette.ramp(Palette.ORANGE, 3) if on else Palette.ramp(Palette.STEEL, 2))
		c.draw_rect(r, DIGIT_COL if on else Palette.ramp(Palette.STEEL, 6), false)
		_draw_text3x5(c, r.position + Vector2(4, 3), str(i + 1), 1,
			DIGIT_COL if on else Palette.ramp(Palette.STEEL, 8))
	# MSL ammo (live with Phase I2)
	_draw_text3x5(c, Vector2(64, CONSOLE_Y + 7), "%02d" % GameState.missiles, 2,
		DIGIT_COL if GameState.missiles > 0 else Color("ff3018"))
	# K4: evade lamp — refills through the cooldown, bright cyan when ready
	if player:
		var frac := 1.0 - clampf(player.dodge_cd / PlayerShip.DODGE_CD, 0.0, 1.0)
		c.draw_rect(Rect2(184, CONSOLE_Y + 16, 22, 7), Palette.ramp(Palette.STEEL, 1))
		c.draw_rect(Rect2(185, CONSOLE_Y + 17, 20.0 * frac, 5),
			Palette.ramp(Palette.CYAN, 14) if frac >= 1.0 else Palette.ramp(Palette.CYAN, 6))
	# TIME clock, centred in its well (long runs drop to the small digits)
	var ts := _time_string()
	var px := 2 if ts.length() <= 4 else 1
	var tw := (ts.length() * 4 - 1) * px
	_draw_text3x5(c, Vector2(floorf(123.0 - tw / 2.0), CONSOLE_Y + (16 if px == 2 else 19)),
		ts, px, DIGIT_COL)
	# LED gauges — SHLD shifts green -> gold -> red as it drains (its top lit
	# segment blinks when critical); HEAT runs gold -> orange -> red along its
	# length and goes all-red on overheat
	var sf := GameState.shields / GameState.max_shields()
	var s_ramp := Palette.GREEN if sf > 0.5 else (Palette.GOLD if sf > 0.25 else Palette.RED)
	var s_lit := _led.x - (1 if _led_blink == 1 else 0)
	for i in LED_N:
		_draw_led(c, i, CONSOLE_Y + 7, i < s_lit, s_ramp)
		_draw_led(c, i, CONSOLE_Y + 15, i < _led.y, Palette.CYAN)
		var h_ramp := Palette.RED if GameState.is_overheated or i >= 9 \
			else (Palette.ORANGE if i >= 6 else Palette.GOLD)
		_draw_led(c, i, CONSOLE_Y + 23, i < _led.z, h_ramp)
	# kill counter over the radar (only while an arena lock is active)
	if _kill_target > 0:
		var s := "%03d/%03d" % [_kills, _kill_target]
		_draw_text3x5(c, Vector2(W / 2.0 - s.length() * 2.0, CONSOLE_Y - 8), s, 1, DIGIT_COL)


## One LED segment: lit ones glow with a hot highlight row, dark ones still show
## their socket in a deep shade of the same hue.
func _draw_led(c: CanvasItem, i: int, y: float, lit: bool, ramp: int) -> void:
	var r := Rect2(LED_X + i * (LED_W + 1), y, LED_W, 5)
	if lit:
		c.draw_rect(r, Palette.ramp(ramp, 11))
		c.draw_rect(Rect2(r.position, Vector2(LED_W, 1)), Palette.ramp(ramp, 15))
	else:
		c.draw_rect(r, Palette.ramp(ramp, 2))


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


## Signal-driven: recount the lit LEDs and redraw the console only when a count
## moves (a partial segment still lights, so 1 shield point shows one LED).
func _update_bars() -> void:
	var led := Vector3i(
		ceili(clampf(GameState.shields / GameState.max_shields(), 0.0, 1.0) * LED_N),
		ceili(clampf(GameState.energy / GameState.max_energy(), 0.0, 1.0) * LED_N),
		ceili(clampf(GameState.heat / GameState.MAX_HEAT, 0.0, 1.0) * LED_N))
	_shield_num.text = str(int(GameState.shields))
	var sf := GameState.shields / GameState.max_shields()
	var ramp := Palette.GREEN if sf > 0.5 else (Palette.GOLD if sf > 0.25 else Palette.RED)
	_shield_num.add_theme_color_override("font_color", Palette.ramp(ramp, 13))
	if led != _led:
		_led = led
		_console_draw.queue_redraw()


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
