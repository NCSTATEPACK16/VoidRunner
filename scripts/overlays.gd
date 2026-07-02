class_name Overlays
extends CanvasLayer
## All full-screen game-flow overlays, built in code at the 320x200 design size:
## start screen, controls guide, mission briefing (PLAN.md E5), pause, game over,
## level clear, and campaign victory. Buttons emit signals; game.gd drives the flow.
## The start/briefing buttons double as the browser audio unlock + mouse capture
## gesture, exactly like the v2.2 web build's Start click.

signal launch_requested       # from start screen or a briefing's LAUNCH
signal next_level_requested
signal retry_requested
signal new_campaign_requested

const BG := Color(0.008, 0.012, 0.03, 0.92)
const TITLE_COL := Color("62ffd0")
const TEXT_COL := Color("8fb8cc")
const KEY_COL := Color("ffd34d")

var _panels := {}


func _ready() -> void:
	_build_start()
	_build_help()
	_build_briefing()
	_build_pause()
	_build_game_over()
	_build_level_clear()
	_build_victory()
	show_only("start")


func show_only(panel_name: String) -> void:
	for key in _panels:
		_panels[key].visible = key == panel_name
	if panel_name != "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_all() -> void:
	show_only("")


func set_briefing(level: LevelDef) -> void:
	var p: Control = _panels.briefing
	(p.get_node("Title") as Label).text = level.display_name
	(p.get_node("Objective") as Label).text = "PRIMARY: " + level.objective
	(p.get_node("Body") as Label).text = level.briefing


func set_level_clear(level_name: String, bonus: int, score: int, next_name: String) -> void:
	var p: Control = _panels.level_clear
	(p.get_node("Title") as Label).text = level_name + " CLEAR"
	(p.get_node("Body") as Label).text = \
		"EXIT BONUS +%d · SCORE %d\nNEXT: %s" % [bonus, score, next_name]


func set_final_score(panel_name: String, score: int) -> void:
	(_panels[panel_name].get_node("Score") as Label).text = "SCORE %d" % score


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
	_line(p, 58, "5-LEVEL CAMPAIGN · SECTOR RUN", 8, Color("5fb6d8"))
	_line(p, 76, "Your fighter is locked in the labyrinth at constant burn.", 8, TEXT_COL)
	_line(p, 86, "Clear the tunnels. Survive the arenas. Watch the radar.", 8, TEXT_COL)
	_line(p, 100, "Cannons build HEAT — redline and weapons lock for 3 s.", 8, TEXT_COL)
	_line(p, 110, "Wall impacts drain shields. Shields at zero = hull breach.", 8, TEXT_COL)
	_button(p, Vector2(88, 136), "> START", func() -> void:
		AudioSys.unlock()
		launch_requested.emit())
	_button(p, Vector2(168, 136), "? CONTROLS", func() -> void: show_only("help"))


func _build_help() -> void:
	var p := _panel("help")
	_title(p, "FLIGHT MANUAL", 14, TITLE_COL)
	var left := [
		"FLIGHT", "MOUSE / ARROWS  steer", "W or RMB  afterburner", "S  retro brake",
		"", "SYSTEM", "P or ESC  pause",
	]
	var right := [
		"WEAPONS", "LMB / SPACE / X  fire", "1 NEUTRON  2 SCATTER", "3 BOLT  4 MISSILE",
		"BACKSPACE  cycle", "", "Locked bulkheads open when", "every hostile is down.",
	]
	for i in left.size():
		_at(p, Vector2(36, 52 + i * 11), left[i], 8,
			TITLE_COL if left[i] in ["FLIGHT", "SYSTEM"] else TEXT_COL)
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
	b.size = Vector2(260, 80)
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
	var s := _line(p, 90, "SCORE 0", 10, KEY_COL)
	s.name = "Score"
	_button(p, Vector2(120, 130), "@ RETRY LEVEL", func() -> void: retry_requested.emit())


func _build_level_clear() -> void:
	var p := _panel("level_clear")
	var t := _title(p, "LEVEL CLEAR", 16, TITLE_COL)
	t.name = "Title"
	var b := _line(p, 84, "", 8, TEXT_COL)
	b.name = "Body"
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.position.x = 0
	b.size.x = 320
	_button(p, Vector2(120, 136), "> NEXT LEVEL", func() -> void: next_level_requested.emit())


func _build_victory() -> void:
	var p := _panel("victory")
	_title(p, "CAMPAIGN COMPLETE", 16, TITLE_COL)
	_line(p, 78, "ALL 5 SECTORS CLEARED · THE RIFT IS SHUT", 8, Color("5fb6d8"))
	var s := _line(p, 96, "SCORE 0", 10, KEY_COL)
	s.name = "Score"
	_button(p, Vector2(112, 136), "@ NEW CAMPAIGN", func() -> void: new_campaign_requested.emit())


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


func _line(p: Control, y: float, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
	l.size = Vector2(320, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
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
