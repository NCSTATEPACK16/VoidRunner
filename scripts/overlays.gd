class_name Overlays
extends CanvasLayer
## All full-screen game-flow overlays, built in code at the 320x200 design size:
## start screen, controls guide, mission briefing (PLAN.md E5), pause, game over,
## level clear, and campaign victory. Buttons emit signals; game.gd drives the flow.
## The start/briefing buttons double as the browser audio unlock + mouse capture
## gesture, exactly like the v2.2 web build's Start click.

signal launch_requested       # from start screen or a briefing's LAUNCH
signal gauntlet_requested     # K5: endless mode from the start screen
signal next_level_requested
signal retry_requested
signal new_campaign_requested

const BG := Color(0.008, 0.012, 0.03, 0.92)
const TITLE_COL := Color("62ffd0")
const TEXT_COL := Color("8fb8cc")
const KEY_COL := Color("ffd34d")

var _panels := {}
var _settings_labels := {}       # H: setting key -> its value Label/Button
var _settings_return := "start"  # where the settings BACK button returns to

# Phase J: sector select + records on the start screen
var _sector := 0
var _sector_names: Array[String] = []
var _sector_label: Label
var _high_label: Label
var _help_pad: Label   # K6: gamepad line on the controls screen, shown only when enabled


func _ready() -> void:
	_build_start()
	_build_help()
	_build_briefing()
	_build_pause()
	_build_game_over()
	_build_level_clear()
	_build_victory()
	_build_settings()
	show_only("start")


func show_only(panel_name: String) -> void:
	for key in _panels:
		_panels[key].visible = key == panel_name
	if panel_name == "start":
		_refresh_start()
	if panel_name == "help" and _help_pad:
		_help_pad.text = "PAD  stick · A/RT fire · X/B roll" \
			if GameState.gamepad_enabled else ""
	if panel_name != "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Phase J: called once by game.gd with all level display names; the picker is
## clamped to what the player has unlocked and defaults to their furthest sector.
func set_campaign(names: Array[String]) -> void:
	_sector_names = names
	_sector = mini(GameState.unlocked_level, names.size() - 1)
	_refresh_start()


func selected_sector() -> int:
	return _sector


func _adjust_sector(dir: int) -> void:
	var max_sector: int = mini(GameState.unlocked_level, _sector_names.size() - 1)
	_sector = clampi(_sector + dir, 0, max_sector)
	AudioSys.play_select()
	_refresh_start()


func _refresh_start() -> void:
	if _sector_names.is_empty() or _sector_label == null:
		return
	var max_sector: int = mini(GameState.unlocked_level, _sector_names.size() - 1)
	_sector = clampi(_sector, 0, max_sector)
	_sector_label.text = "SECTOR: %s" % _sector_names[_sector]
	var records := ""
	if GameState.high_score > 0:
		records = "HIGH SCORE %d" % GameState.high_score
	if GameState.gauntlet_best_dist > 0:
		records += ("  ·  " if records != "" else "") \
			+ "GAUNTLET %dm" % GameState.gauntlet_best_dist
	_high_label.text = records


func hide_all() -> void:
	show_only("")


func set_briefing(level: LevelDef) -> void:
	var p: Control = _panels.briefing
	(p.get_node("Title") as Label).text = level.display_name
	var objective := "PRIMARY: " + level.objective
	if level.kind == "tunnel":
		objective += "\nSECONDARY: DESTROY ALL FUEL CELLS"   # K3 (not boss/endless)
	(p.get_node("Objective") as Label).text = objective
	(p.get_node("Body") as Label).text = level.briefing


func set_level_clear(level_name: String, bonus: int, score: int, next_name: String,
		kills: int, acc: int, time: float, rank: String, secondary := false) -> void:
	var p: Control = _panels.level_clear
	(p.get_node("Title") as Label).text = level_name + " CLEAR"
	var secondary_line := "\nSECONDARY COMPLETE +400" if secondary else ""
	(p.get_node("Body") as Label).text = \
		"KILLS %d · ACCURACY %d%% · TIME %s%s\nEXIT BONUS +%d · SCORE %d\nNEXT: %s" % [
			kills, acc, _fmt_time(time), secondary_line, bonus, score, next_name]
	var r := p.get_node("Rank") as Label
	r.text = "RANK " + rank
	r.add_theme_color_override("font_color", _rank_color(rank))


## dist >= 0 marks a gauntlet run (K5): the tally shows distance and compares
## against the gauntlet bests instead of the campaign high score.
func set_final_score(panel_name: String, score: int, new_record := false,
		dist := -1) -> void:
	var score_line := "SCORE %d" % score
	if dist >= 0:
		score_line = "DIST %dm  ·  SCORE %d" % [dist, score]
	(_panels[panel_name].get_node("Score") as Label).text = score_line
	var rec := _panels[panel_name].get_node_or_null("Record") as Label
	if rec:
		if dist >= 0:
			rec.text = "*** NEW BEST ***" if new_record \
				else "BEST %dm · %d" % [GameState.gauntlet_best_dist, GameState.gauntlet_best_score]
		else:
			rec.text = "*** NEW RECORD ***" if new_record \
				else "HIGH SCORE %d" % GameState.high_score


func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _rank_color(rank: String) -> Color:
	match rank:
		"S":
			return Color("ffd34d")
		"A":
			return Color("55ffee")
		"B":
			return Color("4a90d8")
	return TEXT_COL


# ---------- builders ----------

func _panel(panel_name: String) -> Control:
	var p := ColorRect.new()
	p.color = BG
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.visible = false
	add_child(p)
	_panels[panel_name] = p
	return p


func _build_start() -> void:
	var p := _panel("start")
	_title(p, "VOID RUNNER", 24, TITLE_COL)
	_line(p, 58, "9-LEVEL CAMPAIGN · SECTOR RUN", 8, Color("5fb6d8"))
	_high_label = _line(p, 70, "", 8, KEY_COL)
	_line(p, 82, "Your fighter runs the labyrinth at constant burn.", 8, TEXT_COL)
	_line(p, 92, "Clear tunnels, survive arenas, watch the radar.", 8, TEXT_COL)
	_line(p, 102, "Cannons build HEAT — redline locks them 3 s.", 8, TEXT_COL)
	_line(p, 112, "Wall hits drain shields. At zero: hull breach.", 8, TEXT_COL)
	_button(p, Vector2(84, 126), "<", func() -> void: _adjust_sector(-1))
	_sector_label = _line(p, 132, "", 8, KEY_COL)
	_button(p, Vector2(216, 126), ">", func() -> void: _adjust_sector(1))
	_button(p, Vector2(88, 152), "> START", func() -> void:
		AudioSys.unlock()
		launch_requested.emit())
	_button(p, Vector2(168, 152), "? CONTROLS", func() -> void: show_only("help"))
	_button(p, Vector2(70, 174), "* SETTINGS", func() -> void:
		_settings_return = "start"
		show_only("settings"))
	# K5: endless survival mode — the button doubles as the audio-unlock gesture
	_button(p, Vector2(170, 174), "% GAUNTLET", func() -> void:
		AudioSys.unlock()
		gauntlet_requested.emit())


func _build_help() -> void:
	var p := _panel("help")
	_title(p, "FLIGHT MANUAL", 14, TITLE_COL)
	var left := [
		"FLIGHT", "MOUSE / ARROWS  steer", "W or RMB  afterburner", "S  retro brake",
		"A / D  evade roll", "", "SYSTEM", "P or ESC  pause",
	]
	var right := [
		"WEAPONS", "LMB / SPACE / X  fire", "1 NEUTRON  2 SCATTER", "3 BOLT  4 MISSILE",
		"BACKSPACE  cycle", "", "Locked bulkheads open when", "every hostile is down.",
	]
	for i in left.size():
		_at(p, Vector2(36, 52 + i * 11), left[i], 8,
			TITLE_COL if left[i] in ["FLIGHT", "SYSTEM"] else TEXT_COL)
	_help_pad = _at(p, Vector2(36, 52 + left.size() * 11), "", 8, TEXT_COL)
	for i in right.size():
		_at(p, Vector2(172, 52 + i * 11), right[i], 8,
			TITLE_COL if right[i] == "WEAPONS" else TEXT_COL)
	_button(p, Vector2(88, 160), "> START", func() -> void:
		AudioSys.unlock()
		launch_requested.emit())
	_button(p, Vector2(168, 160), "< BACK", func() -> void: show_only("start"))


func _build_briefing() -> void:
	var p := _panel("briefing")
	var t := _title(p, "", 14, TITLE_COL)
	t.name = "Title"
	var o := _line(p, 60, "", 8, KEY_COL)
	o.name = "Objective"
	var b := _line(p, 76, "", 8, TEXT_COL)
	b.name = "Body"
	b.position.x = 30
	b.size = Vector2(260, 80) * 2  # _line labels are 2x-size, 0.5-scale (see _line)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(p, Vector2(128, 164), "> LAUNCH", func() -> void:
		AudioSys.unlock()
		launch_requested.emit())


func _build_pause() -> void:
	var p := _panel("pause")
	# clicks must fall through so game.gd's _unhandled_input can resume
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title(p, "PAUSED", 16, TITLE_COL)
	_line(p, 100, "Click or press P to re-engage", 8, TEXT_COL)


func _build_game_over() -> void:
	var p := _panel("game_over")
	_title(p, "HULL BREACH", 20, Color("ff5040"))
	var s := _line(p, 88, "SCORE 0", 10, KEY_COL)
	s.name = "Score"
	var rec := _line(p, 104, "", 8, Color("5fb6d8"))
	rec.name = "Record"
	_button(p, Vector2(120, 132), "@ RETRY LEVEL", func() -> void: retry_requested.emit())


func _build_level_clear() -> void:
	var p := _panel("level_clear")
	var t := _title(p, "LEVEL CLEAR", 16, TITLE_COL)
	t.name = "Title"
	var b := _line(p, 70, "", 8, TEXT_COL)
	b.name = "Body"
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.position.x = 0
	b.size = Vector2(320, 40) * 2  # _line labels are 2x-size, 0.5-scale (see _line)
	var r := _line(p, 108, "", 14, KEY_COL)
	r.name = "Rank"
	_button(p, Vector2(120, 142), "> NEXT LEVEL", func() -> void: next_level_requested.emit())


func _build_victory() -> void:
	var p := _panel("victory")
	_title(p, "CAMPAIGN COMPLETE", 16, TITLE_COL)
	_line(p, 74, "ALL 9 SECTORS CLEARED · THE RIFT IS SHUT", 8, Color("5fb6d8"))
	var s := _line(p, 92, "SCORE 0", 10, KEY_COL)
	s.name = "Score"
	var rec := _line(p, 108, "", 8, Color("5fb6d8"))
	rec.name = "Record"
	_button(p, Vector2(112, 136), "@ NEW CAMPAIGN", func() -> void: new_campaign_requested.emit())


## H: volume + mouse sensitivity (stepper rows) and a dither on/off toggle. All
## values live on GameState, which applies + persists them; rows just adjust + refresh.
func _build_settings() -> void:
	var p := _panel("settings")
	_title(p, "SETTINGS", 16, TITLE_COL)
	_setting_row(p, 74, "VOLUME", "volume")
	_setting_row(p, 98, "MOUSE SENS", "sens")
	_at(p, Vector2(60, 124), "DITHER (DOS LOOK)", 8, TEXT_COL)
	var dbtn := _button(p, Vector2(214, 122), "ON", func() -> void:
		GameState.dither_enabled = not GameState.dither_enabled
		GameState.apply_settings()
		_refresh_settings())
	_settings_labels["dither"] = dbtn
	# K6: gamepad stays opt-in — flying with a pad is a choice, never a surprise
	_at(p, Vector2(60, 144), "GAMEPAD", 8, TEXT_COL)
	var gbtn := _button(p, Vector2(214, 142), "OFF", func() -> void:
		GameState.gamepad_enabled = not GameState.gamepad_enabled
		GameState.apply_settings()
		_refresh_settings())
	_settings_labels["gamepad"] = gbtn
	_button(p, Vector2(130, 168), "< BACK", func() -> void: show_only(_settings_return))
	_refresh_settings()


func _setting_row(p: Control, y: float, label: String, key: String) -> void:
	_at(p, Vector2(60, y + 2), label, 8, TEXT_COL)
	_button(p, Vector2(184, y), "-", func() -> void: _adjust_setting(key, -1))
	var val := _at(p, Vector2(216, y + 2), "", 8, KEY_COL)
	_settings_labels[key] = val
	_button(p, Vector2(246, y), "+", func() -> void: _adjust_setting(key, 1))


func _adjust_setting(key: String, dir: int) -> void:
	if key == "volume":
		GameState.master_volume = clampf(GameState.master_volume + dir * 0.1, 0.0, 1.0)
	elif key == "sens":
		GameState.mouse_sens_mult = clampf(GameState.mouse_sens_mult + dir * 0.1, 0.3, 2.5)
	GameState.apply_settings()
	_refresh_settings()


func _refresh_settings() -> void:
	if _settings_labels.has("volume"):
		(_settings_labels["volume"] as Label).text = "%d%%" % roundi(GameState.master_volume * 100.0)
	if _settings_labels.has("sens"):
		(_settings_labels["sens"] as Label).text = "%d%%" % roundi(GameState.mouse_sens_mult * 100.0)
	if _settings_labels.has("dither"):
		(_settings_labels["dither"] as Button).text = "ON" if GameState.dither_enabled else "OFF"
	if _settings_labels.has("gamepad"):
		(_settings_labels["gamepad"] as Button).text = "ON" if GameState.gamepad_enabled else "OFF"


# ---------- widget helpers ----------

func _title(p: Control, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, 28)
	l.size = Vector2(320, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	p.add_child(l)
	return l


## Body-text lines render at double font size scaled 0.5: at size 8 the default
## font's advances carry half-pixel fractions that snap during painting, so long
## centered lines drift right ~0.5 design px per glyph; size-16 advances are
## integer-exact. Anyone overriding a _line label's size must use 2x local units.
func _line(p: Control, y: float, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
	l.size = Vector2(640, 24)
	l.scale = Vector2(0.5, 0.5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size * 2)
	l.add_theme_color_override("font_color", color)
	p.add_child(l)
	return l


func _at(p: Control, pos: Vector2, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	p.add_child(l)
	return l


func _button(p: Control, pos: Vector2, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_color_override("font_color", TITLE_COL)
	b.pressed.connect(on_press)
	p.add_child(b)
	return b
