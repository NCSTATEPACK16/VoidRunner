class_name Overlays
extends CanvasLayer
## All full-screen game-flow overlays, built in code at the 320x200 design size:
## start screen, controls guide, mission briefing (PLAN.md E5), pause, game over,
## level clear, campaign victory, settings, upgrade bay and the safety notice.
## Buttons emit signals; game.gd drives the flow. The start/briefing buttons double
## as the browser audio unlock + mouse capture gesture, exactly like the v2.2 web
## build's Start click.
##
## 3.0 Phase 4: rebuilt as DOS-style text-mode windows — a shadowed box with a
## double border and an inverted title bar, menu items that light up as a solid
## highlight bar under the mouse or keyboard focus (arrows + ENTER navigate every
## screen), all in PixelFont. The start screen is translucent over the attract-
## mode flythrough game.gd runs behind it, under a chrome LogoGen title.
##
## Title redesign (option B, "PRESS START"): the title opens as pure attract mode —
## the big two-line logo, a blinking PRESS ENTER and a scrolling ticker (records +
## the story line). A press slides the logo up and raises one row of cards:
## CONTINUE / NEW GAME / GAUNTLET / SETUP. Sector, difficulty and the manual moved
## behind NEW GAME, into their own small window.

signal launch_requested       # from start screen or a briefing's LAUNCH
signal gauntlet_requested     # K5: endless mode from the start screen
signal next_level_requested
signal retry_requested
signal new_campaign_requested
signal warning_acknowledged   # M1.2: photosensitivity notice dismissed
signal resume_requested       # re-audit Step 2: pause menu RESUME
signal quit_to_title_requested   # re-audit Step 2: pause menu QUIT TO TITLE (confirmed)
signal continue_requested        # re-audit Step 4: title CONTINUE (resume the checkpoint)
signal retry_checkpoint_requested   # re-audit Step 4: game over RETRY FROM CHECKPOINT

const BG := Color(0.008, 0.012, 0.03, 0.975)   # full screens: the HUD must not bleed through
const START_BG := Color(0.0, 0.0, 0.02, 0.38)  # the title lets the attract flythrough show
const WIN_BG := Color(0.02, 0.035, 0.09, 0.94)
const WIN_EDGE := Color("55ffee")
const WIN_EDGE_DIM := Color(0.12, 0.36, 0.42)
const BAR_FG := Color(0.02, 0.03, 0.08)
const TITLE_COL := Color("62ffd0")
const TEXT_COL := Color("a8c8d8")
const DIM_COL := Color("55647d")
const KEY_COL := Color("ffd34d")
const ORANGE_COL := Color("ff9c40")
const RED_COL := Color("ff5040")

# V2.2 L3d: Upgrade Bay — cost to reach the NEXT tier, indexed by current tier.
const WEAPON_COST := [60, 140]              # MK I->II, MK II->III
const BAY_WEAPONS := ["NEUTRON", "SCATTER", "BOLT", "MISSILE"]
const BAY_SHIP := [   # [GameState.ship_ranks key, display label]
	["shield", "SHIELD"], ["heat", "HEAT SINK"], ["energy", "ENERGY"],
	["rack", "MSL RACK"], ["magnet", "MAGNET"], ["hull", "HULL"],
]
const SHIP_COST := {   # cost per rank; array length = max rank
	"shield": [120, 260], "heat": [120, 260], "energy": [120, 260],
	"rack": [120, 260], "magnet": [180], "hull": [180],
}
const CRT_NAMES := ["OFF", "SCANLINES", "CRT"]

var _panels := {}
var _focus := {}                 # panel name -> Button that takes keyboard focus on show
var _settings_labels := {}       # H: setting key -> its value Label/Button
var _settings_return := "start"  # where the settings BACK button returns to
var _help_return := "start"      # re-audit Step 2: the manual opens from pause too
var _help_start: Button          # "> START" — only offered when opened from the title
var _help_back: Button
var _quit_btn: Button
var _quit_armed := false
var _bay_rows := {}              # V2.2 L3d: row id -> {status: Label, buy: Button}
var _bay_salvage_label: Label

# Phase J: sector select + records on the start screen
var _sector := 0
var _sector_names: Array[String] = []
var _sector_label: Label
var _high_label: Label
var _difficulty_btn: Button   # Step 3: NEW GAME row, shows the current preset
# title option B: attract state, then a card row
const START_SUBS := ["settings", "help", "difficulty", "new_game"]   # BACK returns open
const CARD_Y := 142.0
const LOGO_LIFT := 24.0
const TICKER_SPEED := 28.0   # px/s
var _shown := ""                 # the panel show_only() last made visible
var _start_open := false         # false: attract (PRESS ENTER); true: the card row
var _start_card := 0             # last focused card, refocused on returning
var _press_btn: Button           # full-screen, invisible: any press opens the menu
var _press_label: Label
var _logo_root: Control
var _strip: Control
var _cards: Array[Button] = []   # CONTINUE, NEW GAME, GAUNTLET, SETUP
var _card_sub: Label
var _ticker: Label
var _ticker_w := 0.0
var _blink_t := 0.0
var _start_tween: Tween
## Re-audit Step 5: set by game.gd in touch mode; the FLIGHT MANUAL then shows the
## touch layout instead of keys
var touch_mode := false
var _help_keys: Control
var _help_touch: Control
# re-audit Step 4: checkpoint rows
var _continue_btn: Button
var _new_btn: Button
var _continue_tag := ""          # "L4" when a checkpoint exists, "" otherwise
var _briefing_launch: Button
var _go_retry: Button
var _go_restart: Button
var _go_difficulty: Button
var _go_feedback: Button
var _difficulty_return := "start"   # where the difficulty panel's BACK returns to
var _help_pad: Label   # K6: gamepad line on the controls screen, shown only when enabled

# D11: install-nudge buttons (start/game_over/victory), built once at boot but
# hidden/shown live — see _refresh_install_buttons().
var _install_buttons: Array[Button] = []


func _ready() -> void:
	_build_start()
	_build_help()
	_build_briefing()
	_build_pause()
	_build_game_over()
	_build_level_clear()
	_build_victory()
	_build_settings()
	_build_difficulty()
	_build_bay()
	_build_warning()
	show_only("warning" if not GameState.seen_warning else "start")


func show_only(panel_name: String) -> void:
	for key in _panels:
		_panels[key].visible = key == panel_name
	if panel_name == "start":
		# fresh arrivals (boot, the notice, quit to title) get attract mode; BACK from
		# one of the title's own sub-panels lands on the card row it left
		if not (_shown in START_SUBS):
			_start_open = false
		_refresh_start()
		_apply_start_state(false)
	_shown = panel_name
	# D11: beforeinstallprompt fires asynchronously and may not have arrived yet when
	# these panels were first built at boot (Overlays._ready() runs as early as
	# anything in the pipeline) — re-check live every time a panel that can show the
	# button becomes visible, instead of baking a one-time answer into construction.
	if panel_name in ["start", "game_over", "victory"]:
		_refresh_install_buttons()
	if panel_name == "help" and _help_keys:
		_help_keys.visible = not touch_mode   # re-audit Step 5
		_help_touch.visible = touch_mode
	if panel_name == "help" and _help_pad:
		_help_pad.text = "PAD  stick · A/RT fire · X/B roll" \
			if GameState.gamepad_enabled else ""
	if panel_name == "help" and _help_start:
		# from pause the manual is reference only: no START, BACK returns to pause
		_help_start.visible = _help_return in ["start", "new_game"]
		_focus["help"] = _help_start if _help_start.visible else _help_back
	if panel_name == "pause":
		_disarm_quit()
	if panel_name != "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# 3.0: keyboard-drivable menus — the panel's first action takes focus
		var fb: Button = _focus.get(panel_name)
		if fb and fb.is_inside_tree():
			fb.grab_focus.call_deferred()


## Phase J: called once by game.gd with all level display names; the picker is
## clamped to what the player has unlocked and defaults to their furthest sector.
func set_campaign(names: Array[String]) -> void:
	_sector_names = names
	_sector = mini(GameState.unlocked_level, names.size() - 1)
	_refresh_start()


func selected_sector() -> int:
	return _sector


## Re-audit Step 4: game.gd names the checkpoint's sector ("L4"), or "" for none.
func set_continue(sector_tag: String) -> void:
	_continue_tag = sector_tag
	_refresh_start()


## Re-audit Step 4: a briefing opened to resume a checkpoint says so on its button.
func set_launch_label(text: String) -> void:
	if _briefing_launch:
		_briefing_launch.text = text


func _on_go_retry() -> void:
	if _go_restart.visible:
		retry_checkpoint_requested.emit()
	else:
		retry_requested.emit()


## Re-audit Step 4: with a mid-sector checkpoint, game over offers it first (and a
## full sector restart second); without one, the plain RETRY LEVEL as before.
func set_retry_options(has_checkpoint: bool) -> void:
	_go_retry.text = "@ RETRY FROM CHECKPOINT" if has_checkpoint else "@ RETRY LEVEL"
	_go_restart.visible = has_checkpoint
	var y := 116.0 if has_checkpoint else 104.0
	for b in [_go_difficulty, _go_feedback]:
		if b:
			y += 12.0
			b.position.y = y


func _adjust_sector(dir: int) -> void:
	var max_sector: int = mini(GameState.unlocked_level, _sector_names.size() - 1)
	_sector = clampi(_sector + dir, 0, max_sector)
	_refresh_start()   # (the arrow buttons play the select blip themselves)


func _refresh_start() -> void:
	if _sector_names.is_empty() or _sector_label == null:
		return
	var max_sector: int = mini(GameState.unlocked_level, _sector_names.size() - 1)
	_sector = clampi(_sector, 0, max_sector)
	_sector_label.text = "SECTOR: %s" % _sector_names[_sector]
	if _difficulty_btn:
		_difficulty_btn.text = "DIFFICULTY: %s" % GameState.difficulty_name()
	if _continue_btn:
		# no save, no card: the row re-centres on the three that work, and the
		# default focus moves to NEW GAME
		var has_save := _continue_tag != ""
		_continue_btn.disabled = not has_save
		_continue_btn.visible = has_save
		_continue_btn.focus_mode = Control.FOCUS_ALL if has_save else Control.FOCUS_NONE
		_layout_cards()
	var records := ""
	if GameState.high_score > 0:
		records = "HIGH SCORE %d" % GameState.high_score
	if GameState.gauntlet_best_dist > 0:
		records += ("  ·  " if records != "" else "") \
			+ "GAUNTLET BEST %dm" % GameState.gauntlet_best_dist
	_high_label.text = records
	_ticker.text = (records + "  ·  " if records != "" else "") + Lore.story(0) + "  ·  "
	_ticker_w = _ticker.text.length() * PixelFont.ADVANCE
	_ticker.size = Vector2(_ticker_w, 9)
	_press_label.text = "TAP TO START" if touch_mode else "PRESS ENTER"
	_card_sub.text = _card_text(_start_card)


## The one-line caption under the card row, for whichever card has focus.
func _card_text(i: int) -> String:
	match i:
		0:
			var li := clampi(_continue_tag.trim_prefix("L").to_int() - 1, 0,
				maxi(_sector_names.size() - 1, 0))
			if _continue_tag == "" or _sector_names.is_empty():
				return "NO SAVED RUN YET"
			return "%s · %s" % [_sector_names[li], GameState.difficulty_name()]
		1:
			return "PICK A SECTOR AND DIFFICULTY"
		2:
			if GameState.gauntlet_best_dist > 0:
				return "ENDLESS RUN · BEST %dm" % GameState.gauntlet_best_dist
			return "ENDLESS RUN · HOW FAR CAN YOU GO?"
		_:
			return "SOUND · CONTROLS · DISPLAY"


## Centres the visible cards as one row; a card is its label plus 6 px each side.
func _layout_cards() -> void:
	var shown: Array[Button] = []
	for c in _cards:
		if c.visible:
			shown.append(c)
	var total := -4.0
	for c in shown:
		total += c.text.length() * PixelFont.ADVANCE + 12 + 4
	var x := roundf(160.0 - total * 0.5)
	for c in shown:
		var w := float(c.text.length() * PixelFont.ADVANCE + 12)
		c.position = Vector2(x, CARD_Y)
		c.size = Vector2(w, 13)
		x += w + 4
	if _start_card == 0 and not _continue_btn.visible:
		_start_card = 1


## Attract mode <-> card row. Animated on a press; instant when the panel is (re)shown.
func _apply_start_state(animate: bool) -> void:
	if _logo_root == null:
		return
	_press_btn.visible = not _start_open
	_press_label.visible = not _start_open
	# closed, the row is hidden outright (not just parked off-screen), so arrow keys
	# in attract mode can't walk focus onto an invisible card
	_strip.visible = _start_open
	var logo_y := -LOGO_LIFT if _start_open else 0.0
	var strip_y := 0.0 if _start_open else 64.0
	if _start_tween:
		_start_tween.kill()
	if animate:
		# stepped, like a '95 menu wipe: 6 whole-pixel jumps, not a smooth glide
		_start_tween = create_tween().set_parallel()
		_start_tween.tween_method(func(v: float) -> void:
			_logo_root.position.y = snappedf(v, LOGO_LIFT / 6.0),
			_logo_root.position.y, logo_y, 0.3)
		_start_tween.tween_method(func(v: float) -> void:
			_strip.position.y = snappedf(v, 64.0 / 6.0),
			_strip.position.y, strip_y, 0.3)
	else:
		_logo_root.position.y = logo_y
		_strip.position.y = strip_y
	if _start_open:
		var c: Button = _cards[_start_card]
		_focus["start"] = c if c.visible else _new_btn
	else:
		_focus["start"] = _press_btn
	var fb: Button = _focus["start"]
	if _panels.start.visible and fb.is_inside_tree():
		fb.grab_focus.call_deferred()


func _open_start_menu() -> void:
	AudioSys.unlock()   # the first press doubles as the browser audio gesture
	_start_open = true
	_apply_start_state(true)


func _close_start_menu() -> void:
	_start_open = false
	_apply_start_state(true)


## Leaves the title for one of its sub-panels, remembering the card for BACK.
func _start_sub(card: int, panel_name: String) -> void:
	_start_card = card
	show_only(panel_name)


func _process(delta: float) -> void:
	if _logo_root == null or not _panels.start.visible:
		return
	_ticker.position.x -= TICKER_SPEED * delta
	if _ticker.position.x < -_ticker_w:
		_ticker.position.x += _ticker_w + 320.0
	_blink_t += delta
	_press_label.modulate.a = 1.0 if GameState.reduce_flashing \
		or fmod(_blink_t, 1.0) < 0.6 else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _start_open and _panels.start.visible and event.is_action_pressed("ui_cancel"):
		_close_start_menu()
		get_viewport().set_input_as_handled()


func hide_all() -> void:
	show_only("")


func set_briefing(level: LevelDef) -> void:
	var p: Control = _panels.briefing
	(p.get_node("Title") as Label).text = level.display_name
	var objective := "PRIMARY: " + level.objective
	if level.kind == "tunnel":
		objective += "\nSECONDARY: DESTROY ALL FUEL CELLS"   # K3 (not boss/endless)
	if level.spur_count > 0:   # V2.2 L5: optional side-spur supply caches
		objective += "\nOPTIONAL: SUPPLY CACHE DETECTED (%d)" % level.spur_count
	(p.get_node("Objective") as Label).text = objective
	(p.get_node("Body") as Label).text = level.briefing
	# V2.2 story pass: the narrative paragraph comes from the lore module (-1 = gauntlet)
	(p.get_node("Story") as Label).text = \
		Lore.story(-1 if GameState.gauntlet_mode else GameState.level_index)


func set_level_clear(level_name: String, bonus: int, score: int, next_name: String,
		kills: int, acc: int, time: float, rank: String, secondary := false,
		secrets := 0, secrets_total := 0, style_peak := 0, salvage := 0,
		caches := 0, caches_total := 0) -> void:
	var p: Control = _panels.level_clear
	(p.get_node("Title") as Label).text = "%s CLEAR · %s" % [level_name,
		GameState.difficulty_name()]   # Step 3: the tally names the preset
	var extras: Array[String] = []
	if secondary:
		extras.append("SECONDARY COMPLETE +400")
	if secrets_total > 0:   # V2.0 phantom-wall caches
		extras.append("SECRETS %d/%d" % [secrets, secrets_total])
	if style_peak > 0:   # V2.2 L2c: best style grade pays out
		extras.append("STYLE: %s +%d" % [GameState.STYLE_NAMES[style_peak], style_peak * 100])
	if salvage > 0:   # V2.2 L3: salvage hauled this level (banked at completion)
		extras.append("SALVAGE +%d" % salvage)
	if caches_total > 0:   # V2.2 L5: optional supply caches collected
		extras.append("CACHES %d/%d" % [caches, caches_total])
	var lines := PackedStringArray([
		"KILLS %d · ACCURACY %d%% · TIME %s" % [kills, acc, _fmt_time(time)]])
	# two extras per line keeps every line inside the window
	for i in range(0, extras.size(), 2):
		lines.append(" · ".join(extras.slice(i, i + 2)))
	lines.append("EXIT BONUS +%d · SCORE %d" % [bonus, score])
	lines.append("NEXT: %s" % next_name)
	(p.get_node("Body") as Label).text = "\n".join(lines)
	var r := p.get_node("Rank") as Label
	r.text = "RANK " + rank
	r.add_theme_color_override("font_color", _rank_color(rank))


## dist >= 0 marks a gauntlet run (K5): the tally shows distance and compares
## against the gauntlet bests instead of the campaign high score.
func set_final_score(panel_name: String, score: int, new_record := false,
		dist := -1) -> void:
	var score_line := "SCORE %d · %s" % [score, GameState.difficulty_name()]   # Step 3
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

func _panel(panel_name: String, bg := BG) -> Control:
	var p := ColorRect.new()
	p.color = bg
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.visible = false
	add_child(p)
	_panels[panel_name] = p
	return p


func _build_start() -> void:
	var p := _panel("start", START_BG)
	# attract mode: one invisible button over everything, so ENTER, a pad's A, a
	# click or a tap anywhere all open the menu the same way
	_press_btn = Button.new()
	_press_btn.flat = true
	_press_btn.focus_mode = Control.FOCUS_ALL
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		_press_btn.add_theme_stylebox_override(state, none)
	_press_btn.pressed.connect(_open_start_menu)
	_press_btn.pressed.connect(AudioSys.play_select)
	p.add_child(_press_btn)
	_press_btn.position = Vector2.ZERO
	_press_btn.size = Vector2(320, 200)
	_focus["start"] = _press_btn
	# the big two-line chrome logo; slides up when the menu opens
	_logo_root = Control.new()
	_logo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_root.size = Vector2(320, 200)
	p.add_child(_logo_root)
	_shade(_logo_root, Rect2(0, 34, 320, 92), 0.35)
	_center(_logo_root, 40, "B E Y O N D   T H E", Color("9fb4ff"))
	var y := 52.0
	for word in ["VOID", "RUNNER"]:
		var logo := TextureRect.new()
		logo.texture = LogoGen.chrome(word, 4)
		logo.position = Vector2(roundf(160.0 - logo.texture.get_width() * 0.5), y)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_logo_root.add_child(logo)
		y += 36.0
	_press_label = _center(p, 150, "PRESS ENTER", KEY_COL)
	# the ticker: records and the story line, scrolling like a demo-scene scroller
	var tick := Control.new()
	tick.clip_contents = true
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.size = Vector2(320, 10)
	p.add_child(tick)
	_shade(tick, Rect2(0, 0, 320, 10), 0.7)
	_ticker = _text(tick, Vector2(320, 1), "", Color("5dff8a"))
	# the card row, on a dark band that rises from the bottom edge
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.size = Vector2(320, 200)
	p.add_child(_strip)
	_shade(_strip, Rect2(0, CARD_Y - 10, 320, 210 - CARD_Y), 0.6)
	_continue_btn = _card_button(_strip, "CONTINUE", 0, func() -> void:
		AudioSys.unlock()
		continue_requested.emit())
	_new_btn = _card_button(_strip, "NEW GAME", 1, func() -> void:
		_start_sub(1, "new_game"))
	# K5: endless survival mode — the button doubles as the audio-unlock gesture
	_card_button(_strip, "GAUNTLET", 2, func() -> void:
		AudioSys.unlock()
		gauntlet_requested.emit())
	_card_button(_strip, "SETUP", 3, func() -> void:
		_settings_return = "start"
		_start_sub(3, "settings"))
	_card_sub = _center(_strip, CARD_Y + 18, "", Color("55e0ff"))
	_layout_cards()
	_high_label = _center(_strip, CARD_Y + 30, "", DIM_COL)
	_high_label.visible = false   # the records ride the ticker; kept for tests/reuse
	# M1.4: build stamp, so a bug report can name the build it came from
	_text(p, Vector2(8, 189), BuildInfo.label(), Color("3d4a63"))
	_install_button(p, Vector2(246, 187))   # D11: quiet, opposite the build stamp
	_build_new_game()
	_apply_start_state(false)


## Title option B: NEW GAME's own window — the sector picker, the preset, the
## manual and LAUNCH, all of which used to crowd the main menu.
func _build_new_game() -> void:
	var p := _panel("new_game", START_BG)
	_shade(p, Rect2(0, 44, 320, 102), 0.5)
	_window(p, Rect2(36, 56, 248, 78), "NEW GAME")
	# M1.5: the sector label is centred on the window and the arrows sit at the
	# window's edges, outside the span of even the longest sector name.
	_menu_button(p, Rect2(40, 70, 12, 11), "<", func() -> void: _adjust_sector(-1),
		KEY_COL, true)
	_sector_label = _center(p, 72, "", KEY_COL)
	_menu_button(p, Rect2(268, 70, 12, 11), ">", func() -> void: _adjust_sector(1),
		KEY_COL, true)
	_difficulty_btn = _menu_button(p, Rect2(58, 86, 204, 11), "", func() -> void:
		open_difficulty("new_game"), KEY_COL)
	_menu_button(p, Rect2(58, 98, 204, 11), "FLIGHT MANUAL", func() -> void:
		_help_return = "new_game"
		show_only("help"))
	var launch := _menu_button(p, Rect2(58, 116, 100, 11), "> LAUNCH", func() -> void:
		AudioSys.unlock()
		launch_requested.emit(), TITLE_COL, true)
	_menu_button(p, Rect2(162, 116, 100, 11), "< BACK", func() -> void:
		show_only("start"), TEXT_COL, true)
	_focus["new_game"] = launch


## A title card: a framed label that lights cyan under focus or the mouse, and
## names itself in the caption line below the row.
func _card_button(p: Control, text: String, idx: int, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_color_override("font_color", Color("7f8bb8"))
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color",
			"font_hover_pressed_color"]:
		b.add_theme_color_override(state, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", DIM_COL)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 6.0
		sb.content_margin_right = 6.0
		sb.content_margin_top = 3.0
		sb.content_margin_bottom = 2.0
		sb.set_border_width_all(1)
		sb.bg_color = Color(0.027, 0.04, 0.11, 0.92)
		sb.border_color = Color("2a3560")
		if state in ["hover", "focus", "hover_pressed", "pressed"]:
			sb.bg_color = Color("0a2a40")
			sb.border_color = WIN_EDGE
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(on_press)
	b.pressed.connect(AudioSys.play_select)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	b.focus_entered.connect(func() -> void:
		_start_card = idx
		_card_sub.text = _card_text(idx))
	p.add_child(b)
	_cards.append(b)
	return b


func _build_help() -> void:
	var p := _panel("help")
	_window(p, Rect2(6, 6, 308, 188), "FLIGHT MANUAL")
	# re-audit Step 5: two pages share the window — keys/mouse, and the touch layout
	_help_keys = _help_page(p)
	_help_touch = _help_page(p)
	var left := [
		"FLIGHT", "MOUSE/ARROWS steer", "W or RMB  afterburn", "S         brake",
		"A / D     evade roll", "", "SYSTEM", "ENTER/ESC pause", "TAB       automap",
	]
	# M3: the beta ask belongs with the other key bindings, and appending it here
	# (rather than placing it absolutely) keeps _help_pad and everything below it
	# flowing — an absolute line landed exactly on the gamepad row.
	if Feedback.is_configured():
		left.append("F  send feedback")
	# 3.0: the bulkhead tip lives in the L1 briefing now; this corner explains
	# the timed power-ups instead
	var right := [
		"WEAPONS", "LMB/SPACE/X  fire", "1 NEUTRON 2 SCATTER", "3 BOLT    4 MISSILE",
		"BACKSPACE cycle", "P  plasma bomb", "", "POWER-UPS", "OVERDRIVE  rapid fire",
		"POWER CORE 2x damage", "PHASE      invulnerable",
	]
	_help_columns(_help_keys, left, right)
	_help_pad = _text(_help_keys, Vector2(16, 22 + left.size() * 11), "", TEXT_COL)
	_help_columns(_help_touch, [
		"FLIGHT", "LEFT THUMB  steer", "DOUBLE-TAP  afterburn", "  (left side, on/off)",
		"FLICK TWICE evade roll", "", "SYSTEM", "II (top right) pause",
	], [
		"WEAPONS", "HOLD FIRE   shoot", "WPN  next weapon", "BOMB plasma bomb", "",
		"POWER-UPS", "OVERDRIVE  rapid fire", "POWER CORE 2x damage", "PHASE      invulnerable",
	])
	# M3: the short version. The full privacy note lives in the README and on the
	# form itself — anything longer than one line here and nobody reads any of it.
	_center(p, 154, "No cookies, no accounts, no personal data.", DIM_COL)
	_help_start = _menu_button(p, Rect2(84, 170, 70, 11), "> START", func() -> void:
		AudioSys.unlock()
		launch_requested.emit(), TITLE_COL, true)
	_help_back = _menu_button(p, Rect2(166, 170, 70, 11), "< BACK", func() -> void:
		show_only(_help_return), TEXT_COL, true)
	_focus["help"] = _help_start


func _help_page(p: Control) -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(page)
	return page


func _help_columns(page: Control, left: Array, right: Array) -> void:
	for i in left.size():
		_text(page, Vector2(16, 22 + i * 11), left[i],
			TITLE_COL if left[i] in ["FLIGHT", "SYSTEM"] else TEXT_COL)
	for i in right.size():
		_text(page, Vector2(166, 22 + i * 11), right[i],
			TITLE_COL if right[i] in ["WEAPONS", "POWER-UPS"] else TEXT_COL)


func _build_briefing() -> void:
	var p := _panel("briefing")
	_window(p, Rect2(6, 6, 308, 188), "MISSION BRIEFING")
	var t := _center(p, 22, "", TITLE_COL, 16)
	t.name = "Title"
	# V2.2 story pass: three stacked bands — dim story paragraph (lore), objective
	# block (up to 3 lines on spur levels), tactical body — sized so the worst case
	# never overlaps and the body bottom stays above the buttons at y=164.
	var s := _wrap(p, Rect2(16, 44, 288, 30), "", Color("5fb6d8"))
	s.name = "Story"
	var o := _wrap(p, Rect2(16, 80, 288, 30), "", KEY_COL)
	o.name = "Objective"
	var b := _wrap(p, Rect2(16, 116, 288, 30), "", TEXT_COL)
	b.name = "Body"
	_menu_button(p, Rect2(40, 172, 110, 11), "* UPGRADE BAY", func() -> void:
		_refresh_bay()
		show_only("bay"), ORANGE_COL, true)
	var launch := _menu_button(p, Rect2(170, 172, 110, 11), "> LAUNCH", func() -> void:
		AudioSys.unlock()
		launch_requested.emit(), TITLE_COL, true)
	_focus["briefing"] = launch
	_briefing_launch = launch   # re-audit Step 4: reads "> RESUME" for a checkpoint


## Re-audit Step 2: a real menu instead of "click to re-engage". The panel now
## swallows clicks and taps, so a stray one can't resume (or fire); RESUME, ENTER,
## ESC or the pad's START do. Touch players reach it from the on-screen II tab.
func _build_pause() -> void:
	var p := _panel("pause", Color(0.0, 0.0, 0.02, 0.55))
	_window(p, Rect2(84, 40, 152, 112), "PAUSED")
	var resume := _menu_button(p, Rect2(96, 54, 128, 11), "> RESUME", func() -> void:
		resume_requested.emit(), TITLE_COL, true)
	_focus["pause"] = resume
	_menu_button(p, Rect2(96, 66, 128, 11), "DIFFICULTY", func() -> void:
		open_difficulty("pause"), KEY_COL, true)   # Step 3: change it mid-run
	_menu_button(p, Rect2(96, 78, 128, 11), "FLIGHT MANUAL", func() -> void:
		_help_return = "pause"
		show_only("help"), TEXT_COL, true)
	_menu_button(p, Rect2(96, 90, 128, 11), "SETTINGS", func() -> void:
		_settings_return = "pause"
		show_only("settings"), ORANGE_COL, true)
	_feedback_button(p, Rect2(96, 102, 128, 11))   # M3: touch has no F key
	_quit_btn = _menu_button(p, Rect2(96, 114, 128, 11), "QUIT TO TITLE", _on_quit_pressed,
		RED_COL, true)
	_center(p, 136, "ENTER / ESC  RESUME", DIM_COL)
	_text(p, Vector2(3, 190), BuildInfo.label(), Color("3d4a63"))   # M1.4


## Quitting ends the run, so the first press only arms it: the row asks again, and
## the second press quits. Re-showing the pause menu disarms it.
func _on_quit_pressed() -> void:
	if not _quit_armed:
		_quit_armed = true
		_quit_btn.text = "QUIT? PRESS AGAIN"
		return
	_disarm_quit()
	quit_to_title_requested.emit()


func _disarm_quit() -> void:
	_quit_armed = false
	if _quit_btn:
		_quit_btn.text = "QUIT TO TITLE"


func _build_game_over() -> void:
	var p := _panel("game_over")
	_window(p, Rect2(40, 34, 240, 138), "SIGNAL LOST", RED_COL)
	_center(p, 50, "HULL BREACH", RED_COL, 16)
	var s := _center(p, 76, "SCORE 0", KEY_COL)
	s.name = "Score"
	var rec := _center(p, 90, "", Color("5fb6d8"))
	rec.name = "Record"
	# re-audit Step 4: the first row resumes the checkpoint when there is one
	# (set_retry_options relabels it and lays the rows out)
	_go_retry = _menu_button(p, Rect2(80, 104, 160, 11), "@ RETRY LEVEL", _on_go_retry,
		TITLE_COL, true)
	_focus["game_over"] = _go_retry
	_go_restart = _menu_button(p, Rect2(80, 116, 160, 11), "RESTART SECTOR", func() -> void:
		retry_requested.emit(), TEXT_COL, true)
	_go_restart.visible = false
	_go_difficulty = _menu_button(p, Rect2(80, 116, 160, 11), "DIFFICULTY", func() -> void:
		open_difficulty("game_over"), KEY_COL, true)   # Step 3
	_go_feedback = _feedback_button(p, Rect2(80, 128, 160, 11))   # M3
	_install_button(p, Vector2(136, 156))   # D11


func _build_level_clear() -> void:
	var p := _panel("level_clear")
	_window(p, Rect2(10, 20, 300, 160), "SECTOR CLEAR")
	var t := _center(p, 36, "LEVEL CLEAR", TITLE_COL)
	t.name = "Title"
	# up to 6 lines: KILLS / extras (2 per line) / BONUS+SCORE / NEXT
	var b := _center(p, 52, "", TEXT_COL)
	b.name = "Body"
	b.size = Vector2(320, 64)
	b.add_theme_constant_override("line_spacing", 1)
	var r := _center(p, 124, "", KEY_COL, 16)
	r.name = "Rank"
	var next := _menu_button(p, Rect2(110, 160, 100, 11), "> NEXT LEVEL", func() -> void:
		next_level_requested.emit(), TITLE_COL, true)
	_focus["level_clear"] = next


func _build_victory() -> void:
	var p := _panel("victory")
	_window(p, Rect2(20, 36, 280, 132), "TRANSMISSION ENDS", KEY_COL)
	_center(p, 52, "CAMPAIGN COMPLETE", TITLE_COL, 16)
	_center(p, 74, "ALL 9 SECTORS CLEARED · THE RIFT IS SHUT", Color("5fb6d8"))
	var s := _center(p, 90, "SCORE 0", KEY_COL)
	s.name = "Score"
	var rec := _center(p, 104, "", Color("5fb6d8"))
	rec.name = "Record"
	var again := _menu_button(p, Rect2(100, 122, 120, 11), "@ NEW CAMPAIGN", func() -> void:
		new_campaign_requested.emit(), TITLE_COL, true)
	_focus["victory"] = again
	_feedback_button(p, Rect2(100, 136, 120, 11))   # M3
	_install_button(p, Vector2(136, 156))   # D11


## Step 3 (M5b): preset + assists in one DOS window, reachable from the main menu,
## the pause menu and game over. Values live on GameState, which applies + saves.
func _build_difficulty() -> void:
	var p := _panel("difficulty")
	_window(p, Rect2(6, 6, 308, 188), "DIFFICULTY")
	_setting_row(p, 24, "PRESET", "difficulty")
	var blurb := _wrap(p, Rect2(20, 40, 280, 22), "", Color("5fb6d8"))
	_settings_labels["difficulty_blurb"] = blurb
	_center(p, 64, "Enemy numbers and levels never change.", DIM_COL)
	_window(p, Rect2(12, 82, 296, 48), "ASSIST", WIN_EDGE_DIM)
	_setting_row(p, 96, "DAMAGE TAKEN", "assist_dmg")
	_setting_row(p, 110, "GAME SPEED", "assist_spd")
	_center(p, 140, "Change these any time. Progress is kept.", TEXT_COL)
	var back := _menu_button(p, Rect2(130, 170, 60, 11), "< BACK", func() -> void:
		show_only(_difficulty_return), TEXT_COL, true)
	_focus["difficulty"] = back
	_refresh_settings()


func open_difficulty(from: String) -> void:
	_difficulty_return = from
	_refresh_settings()
	show_only("difficulty")


## Step 3: after repeated deaths in one sector, game over points at RECRUIT.
func suggest_recruit() -> void:
	var rec := _panels.game_over.get_node_or_null("Record") as Label
	if rec:
		rec.text = "TOUGH SECTOR? TRY RECRUIT"   # the panel says progress is kept


## H + M2 + 3.0: four stepper rows (volume, mouse, field of view, CRT filter),
## then the 2x4 comfort/display toggle grid. Every value lives on GameState,
## which applies + persists it; rows just adjust + refresh.
##
## M4c final review: a GYRO AIM row briefly lived here and was removed — Godot
## 4.7's web export has no device-orientation source feeding Input.get_gyroscope(),
## and web is this game's only mobile delivery, so the toggle was inert.
## GameState.gyro_aim_enabled and player.gd's additive nudge stay as dormant
## scaffolding for a future real JS bridge; with no UI to set the flag, nothing
## can turn them on.
func _build_settings() -> void:
	var p := _panel("settings")
	_window(p, Rect2(6, 6, 308, 188), "SETTINGS")
	_setting_row(p, 22, "VOLUME", "volume")
	_setting_row(p, 35, "MOUSE SENS", "sens")
	_setting_row(p, 48, "FIELD OF VIEW", "fov")
	_setting_row(p, 61, "CRT FILTER", "crt")
	_window(p, Rect2(12, 80, 296, 72), "COMFORT & DISPLAY", WIN_EDGE_DIM)
	# left column
	_toggle_row(p, Vector2(20, 94), "DITHER", "dither", func() -> void:
		GameState.dither_enabled = not GameState.dither_enabled)
	_toggle_row(p, Vector2(20, 108), "AMBER TERM", "amber", func() -> void:
		GameState.amber_mode = not GameState.amber_mode)
	_toggle_row(p, Vector2(20, 122), "GAMEPAD", "gamepad", func() -> void:
		GameState.gamepad_enabled = not GameState.gamepad_enabled)
	_toggle_row(p, Vector2(20, 136), "INVERT Y", "invert_y", func() -> void:
		GameState.invert_y = not GameState.invert_y)
	# right column
	_toggle_row(p, Vector2(166, 94), "SCREEN SHAKE", "shake", func() -> void:
		GameState.screen_shake = not GameState.screen_shake)
	_toggle_row(p, Vector2(166, 108), "REDUCE FLASH", "reduce_flash", func() -> void:
		GameState.reduce_flashing = not GameState.reduce_flashing)
	_toggle_row(p, Vector2(166, 122), "REDUCE ROLL", "reduce_roll", func() -> void:
		GameState.reduce_roll = not GameState.reduce_roll)
	_toggle_row(p, Vector2(166, 136), "TOUCH D-PAD", "dpad", func() -> void:
		GameState.touch_dpad_enabled = not GameState.touch_dpad_enabled)
	var back := _menu_button(p, Rect2(130, 170, 60, 11), "< BACK", func() -> void:
		show_only(_settings_return), TEXT_COL, true)
	_focus["settings"] = back
	_refresh_settings()


func _setting_row(p: Control, y: float, label: String, key: String) -> void:
	_text(p, Vector2(20, y + 1), label, TEXT_COL)
	_menu_button(p, Rect2(196, y, 12, 11), "-", func() -> void: _adjust_setting(key, -1),
		TITLE_COL, true)
	var val := _text(p, Vector2(212, y + 1), "", KEY_COL)
	val.size.x = 76
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_labels[key] = val
	_menu_button(p, Rect2(290, y, 12, 11), "+", func() -> void: _adjust_setting(key, 1),
		TITLE_COL, true)


## One label + ON/OFF button pair. The callable flips the GameState field; saving
## and refreshing are handled here so no caller can forget either.
func _toggle_row(p: Control, pos: Vector2, label: String, key: String,
		flip: Callable) -> void:
	_text(p, pos + Vector2(0, 1), label, TEXT_COL)
	var b := _menu_button(p, Rect2(pos.x + 96, pos.y, 34, 11), "", func() -> void:
		flip.call()
		GameState.apply_settings()
		_refresh_settings(), TEXT_COL, true)
	_settings_labels[key] = b


func _adjust_setting(key: String, dir: int) -> void:
	if key == "volume":
		GameState.master_volume = clampf(GameState.master_volume + dir * 0.1, 0.0, 1.0)
	elif key == "sens":
		GameState.mouse_sens_mult = clampf(GameState.mouse_sens_mult + dir * 0.1, 0.3, 2.5)
	elif key == "fov":
		# M2.2: 60 is tight-but-period-correct, 100 is the modern comfort end
		GameState.view_fov = clampf(GameState.view_fov + dir * 4.0, 60.0, 100.0)
	elif key == "crt":
		GameState.crt_mode = clampi(GameState.crt_mode + dir, 0, CRT_NAMES.size() - 1)
	elif key == "difficulty":   # Step 3
		GameState.difficulty = clampi(GameState.difficulty + dir, 0,
			GameState.DIFFICULTY_NAMES.size() - 1)
	elif key == "assist_dmg":
		GameState.assist_damage = clampi(GameState.assist_damage + dir, 0,
			GameState.ASSIST_DAMAGE.size() - 1)
	elif key == "assist_spd":
		GameState.assist_speed = clampi(GameState.assist_speed + dir, 0,
			GameState.ASSIST_SPEED.size() - 1)
	GameState.apply_settings()
	_refresh_settings()


func _refresh_settings() -> void:
	_set_label("volume", "%d%%" % roundi(GameState.master_volume * 100.0))
	_set_label("sens", "%d%%" % roundi(GameState.mouse_sens_mult * 100.0))
	_set_label("fov", "%d" % roundi(GameState.view_fov))
	_set_label("crt", CRT_NAMES[clampi(GameState.crt_mode, 0, CRT_NAMES.size() - 1)])
	_set_toggle("dither", GameState.dither_enabled)
	_set_toggle("gamepad", GameState.gamepad_enabled)
	_set_toggle("amber", GameState.amber_mode)
	_set_toggle("shake", GameState.screen_shake)
	_set_toggle("reduce_flash", GameState.reduce_flashing)
	_set_toggle("reduce_roll", GameState.reduce_roll)
	_set_toggle("invert_y", GameState.invert_y)
	_set_toggle("dpad", GameState.touch_dpad_enabled)
	_set_label("difficulty", GameState.difficulty_name())   # Step 3
	_set_label("difficulty_blurb", GameState.DIFFICULTY_BLURBS[GameState.difficulty])
	_set_label("assist_dmg", "%d%%" % roundi(GameState.ASSIST_DAMAGE[GameState.assist_damage] * 100.0))
	_set_label("assist_spd", "%d%%" % roundi(GameState.ASSIST_SPEED[GameState.assist_speed] * 100.0))


func _set_label(key: String, text: String) -> void:
	if _settings_labels.has(key):
		(_settings_labels[key] as Label).text = text


func _set_toggle(key: String, on: bool) -> void:
	if _settings_labels.has(key):
		var b := _settings_labels[key] as Button
		b.text = "ON" if on else "OFF"
		b.add_theme_color_override("font_color", KEY_COL if on else DIM_COL)


## M1.2: shown once, before anything else, on a build that strobes and white-outs.
## Acknowledgement persists in settings.cfg so it never nags a returning player.
func _build_warning() -> void:
	var p := _panel("warning")
	_window(p, Rect2(16, 30, 288, 140), "! PHOTOSENSITIVITY NOTICE", ORANGE_COL)
	_wrap(p, Rect2(26, 50, 268, 40),
		"VOID RUNNER contains flashing light, strobing effects and a bright "
		+ "full-screen flash when a plasma bomb detonates.", TEXT_COL)
	_wrap(p, Rect2(26, 94, 268, 40),
		"If you are sensitive to flashing images, turn on REDUCE FLASH in "
		+ "SETTINGS before you fly. It stays on for good.", TEXT_COL)
	_menu_button(p, Rect2(36, 148, 112, 11), "* OPEN SETTINGS", func() -> void:
		_ack_warning()
		_settings_return = "start"
		show_only("settings"), ORANGE_COL, true)
	var ok := _menu_button(p, Rect2(172, 148, 112, 11), "> UNDERSTOOD", func() -> void:
		_ack_warning()
		show_only("start"), TITLE_COL, true)
	_focus["warning"] = ok


func _ack_warning() -> void:
	GameState.seen_warning = true
	GameState.apply_settings()
	warning_acknowledged.emit()


## V2.2 L3d: Upgrade Bay — reached from the briefing (a button swaps to this panel).
## Weapon marks are per-run, ship ranks persist; buying draws from salvage (the run
## haul first, then the bank) via GameState.spend_salvage. One place, no shop sprawl.
func _build_bay() -> void:
	var p := _panel("bay")
	_window(p, Rect2(6, 6, 308, 188), "UPGRADE BAY")
	_text(p, Vector2(16, 22), "WEAPON MARKS", KEY_COL)
	for i in BAY_WEAPONS.size():
		_bay_row(p, 16, 36 + i * 14, "w%d" % i, BAY_WEAPONS[i])
	_text(p, Vector2(166, 22), "SHIP SYSTEMS", KEY_COL)
	for i in BAY_SHIP.size():
		_bay_row(p, 166, 36 + i * 14, "s:" + BAY_SHIP[i][0], BAY_SHIP[i][1])
	_bay_salvage_label = _text(p, Vector2(16, 128), "", KEY_COL)
	_wrap(p, Rect2(16, 142, 288, 20),
		"Marks last the run. Ship systems are yours for good.", DIM_COL)
	_menu_button(p, Rect2(60, 172, 90, 11), "< BACK", func() -> void: show_only("briefing"),
		TEXT_COL, true)
	var launch := _menu_button(p, Rect2(170, 172, 90, 11), "> LAUNCH", func() -> void:
		AudioSys.unlock()
		launch_requested.emit(), TITLE_COL, true)
	_focus["bay"] = launch
	_refresh_bay()


func _bay_row(p: Control, x: float, y: float, id: String, label: String) -> void:
	_text(p, Vector2(x, y + 1), label, TEXT_COL)
	var status := _text(p, Vector2(x + 60, y + 1), "", Color("5fb6d8"))
	var buy := _menu_button(p, Rect2(x + 98, y, 36, 11), "", func() -> void: _bay_buy(id),
		KEY_COL, true)
	_bay_rows[id] = {"status": status, "buy": buy}


func _bay_buy(id: String) -> void:
	if id.begins_with("s:"):
		bay_buy_ship(id.substr(2))
	else:
		bay_buy_weapon(int(id.substr(1)))


## Purchase entries the Bay buttons call — also the testable seam. Return false when
## already maxed or salvage is short (spend_salvage leaves the balance untouched).
func bay_buy_weapon(widx: int) -> bool:
	var mk: int = GameState.weapon_marks[widx]
	if mk >= WEAPON_COST.size():
		return false
	if not GameState.spend_salvage(WEAPON_COST[mk]):
		return false
	GameState.weapon_marks[widx] = mk + 1
	AudioSys.play_select()
	_refresh_bay()
	return true


func bay_buy_ship(key: String) -> bool:
	var rank: int = GameState.ship_ranks[key]
	var costs: Array = SHIP_COST[key]
	if rank >= costs.size():
		return false
	if not GameState.spend_salvage(costs[rank]):
		return false
	GameState.ship_ranks[key] = rank + 1
	AudioSys.play_select()
	_refresh_bay()
	return true


func _refresh_bay() -> void:
	if _bay_rows.is_empty():
		return
	for i in BAY_WEAPONS.size():
		var mk: int = GameState.weapon_marks[i]
		var row: Dictionary = _bay_rows["w%d" % i]
		(row.status as Label).text = "MK%d" % (mk + 1)
		var buy := row.buy as Button
		if mk >= WEAPON_COST.size():
			buy.text = "MAX"
			buy.disabled = true
		else:
			buy.text = str(WEAPON_COST[mk])
			buy.disabled = GameState.salvage_total() < WEAPON_COST[mk]
	for row_def in BAY_SHIP:
		var key: String = row_def[0]
		var rank: int = GameState.ship_ranks[key]
		var costs: Array = SHIP_COST[key]
		var srow: Dictionary = _bay_rows["s:" + key]
		(srow.status as Label).text = "%d/%d" % [rank, costs.size()]
		var sbuy := srow.buy as Button
		if rank >= costs.size():
			sbuy.text = "MAX"
			sbuy.disabled = true
		else:
			sbuy.text = str(costs[rank])
			sbuy.disabled = GameState.salvage_total() < costs[rank]
	if _bay_salvage_label:
		_bay_salvage_label.text = "SALVAGE: %d" % GameState.salvage_total()


# ---------- widget helpers ----------

## A DOS text-mode window: drop shadow, dark fill, double border, and an inverted
## title bar. Decoration only (no input); callers add Labels/Buttons to `p`
## directly, so every control stays a direct child of its panel.
func _window(p: Control, rect: Rect2, title: String, accent := WIN_EDGE) -> void:
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.6)
	shadow.position = rect.position + Vector2(4, 4)
	shadow.size = rect.size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(shadow)
	var box := Panel.new()
	box.position = rect.position
	box.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = WIN_BG
	sb.border_color = accent
	sb.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(box)
	var inner := Panel.new()
	inner.position = rect.position + Vector2(2, 2)
	inner.size = rect.size - Vector2(4, 4)
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0, 0, 0, 0)
	isb.border_color = accent.darkened(0.45)
	isb.set_border_width_all(1)
	inner.add_theme_stylebox_override("panel", isb)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(inner)
	if title != "":
		var tw := title.length() * PixelFont.ADVANCE + 12
		var bar := ColorRect.new()
		bar.color = accent
		bar.position = Vector2(roundf(rect.position.x + (rect.size.x - tw) * 0.5), rect.position.y - 4)
		bar.size = Vector2(tw, 11)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(bar)
		var l := Label.new()
		l.text = title
		l.position = bar.position + Vector2(6, 1)
		l.add_theme_color_override("font_color", BAR_FG)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(l)


## A translucent darkening band (title screen: keeps text readable over the flythrough).
func _shade(p: Control, rect: Rect2, alpha: float) -> void:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0.02, alpha)
	r.position = rect.position
	r.size = rect.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(r)


func _text(p: Control, pos: Vector2, text: String, color: Color, font_size := 8) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return l


## A label centred across the full 320 px width (PixelFont advances are integers,
## so centred text lands on whole pixels — the old 2x/0.5 trick is gone).
func _center(p: Control, y: float, text: String, color: Color, font_size := 8) -> Label:
	var l := _text(p, Vector2(0, y), text, color, font_size)
	l.size = Vector2(320, 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A word-wrapping, centred label confined to `rect`. Godot's Control.size clamps up
## to the Label's combined minimum size, and once a Label with autowrap still OFF has
## joined the tree at a wide size, a narrower .size set afterward does NOT shrink it
## back — so autowrap_mode and the final size are both set BEFORE add_child.
func _wrap(p: Control, rect: Rect2, text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = rect.position
	l.size = rect.size
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return l


## A menu item: plain colored text that becomes a solid highlight bar (inverted
## colors) under the mouse or keyboard focus — the DOS setup-program look. Fixed
## to `rect` (clip off), content margins zeroed so an 11 px row is exactly that.
func _menu_button(p: Control, rect: Rect2, text: String, on_press: Callable,
		color: Color = TITLE_COL, centered := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_color_override("font_color", color)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color",
			"font_hover_pressed_color"]:
		b.add_theme_color_override(state, BAR_FG)
	b.add_theme_color_override("font_disabled_color", DIM_COL)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 3.0
		sb.content_margin_right = 3.0
		sb.content_margin_top = 1.0
		sb.content_margin_bottom = 0.0
		sb.bg_color = Color(0, 0, 0, 0)
		if state in ["hover", "focus", "hover_pressed"]:
			sb.bg_color = color
		elif state == "pressed":
			sb.bg_color = color.lightened(0.3)
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(on_press)
	b.pressed.connect(AudioSys.play_select)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	p.add_child(b)
	# geometry LAST: a Control's size only ever clamps UP to its minimum, and the
	# default stylebox (before the overrides above) makes that minimum 17 px tall
	b.position = rect.position
	b.size = rect.size
	return b


## M3: one feedback button, built the same way everywhere it appears. Absent
## rather than dead when no form is configured — a button that does nothing is
## worse than no button.
func _feedback_button(p: Control, rect: Rect2) -> Button:
	if not Feedback.is_configured():
		return null
	return _menu_button(p, rect, "F  SEND FEEDBACK", func() -> void: Feedback.open_form(),
		ORANGE_COL, true)


## D11: one install-nudge button, built the same way everywhere it appears.
## TEXT_COL rather than a CTA color, because this is a passive, always-skippable
## nudge, never a gate — "ask only at the end," per D11. Never built at all off the
## web (desktop/headless — JavaScriptBridge doesn't exist there and never will).
## On the web it IS always constructed, but starts hidden: beforeinstallprompt
## (which vrCanInstall() depends on) fires asynchronously and may not have arrived
## yet by the time this panel is first built at boot, so the yes/no answer can't be
## decided once here. _refresh_install_buttons() below re-checks live and shows/
## hides it whenever a panel that can display it is shown.
func _install_button(p: Control, pos: Vector2) -> void:
	if not OS.has_feature("web"):
		return
	var b := _menu_button(p, Rect2(pos, Vector2(66, 11)), "INSTALL APP", func() -> void:
		JavaScriptBridge.eval("if (window.vrPromptInstall) window.vrPromptInstall();"),
		TEXT_COL, true)
	b.visible = false
	_install_buttons.append(b)


## D11: re-evaluates window.vrCanInstall() and shows/hides every tracked install
## button to match. Called from show_only() whenever a panel that can display one
## becomes visible — cheap (a single JS bridge call), and correctly picks up a
## beforeinstallprompt that arrived after boot. A shown-but-hidden button on a
## panel that isn't the visible one costs nothing: Control visibility is AND'd
## with every ancestor's, so it stays invisible regardless of its own flag.
func _refresh_install_buttons() -> void:
	if _install_buttons.is_empty():
		return
	var can: bool = JavaScriptBridge.eval("window.vrCanInstall ? window.vrCanInstall() : false")
	for b in _install_buttons:
		b.visible = can
