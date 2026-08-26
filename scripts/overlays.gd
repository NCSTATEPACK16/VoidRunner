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
signal warning_acknowledged   # M1.2: photosensitivity notice dismissed

const BG := Color(0.008, 0.012, 0.03, 0.975)   # near-opaque so the HUD (score, canopy) doesn't bleed through result screens
const TITLE_COL := Color("62ffd0")
const TEXT_COL := Color("8fb8cc")
const KEY_COL := Color("ffd34d")
const ORANGE_COL := Color("ff9c40")

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

var _panels := {}
var _settings_labels := {}       # H: setting key -> its value Label/Button
var _settings_return := "start"  # where the settings BACK button returns to
var _bay_rows := {}              # V2.2 L3d: row id -> {status: Label, buy: Button}
var _bay_salvage_label: Label

# Phase J: sector select + records on the start screen
var _sector := 0
var _sector_names: Array[String] = []
var _sector_label: Label
var _high_label: Label
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
	_build_bay()
	_build_warning()
	show_only("warning" if not GameState.seen_warning else "start")


func show_only(panel_name: String) -> void:
	for key in _panels:
		_panels[key].visible = key == panel_name
	if panel_name == "start":
		_refresh_start()
	# D11: beforeinstallprompt fires asynchronously and may not have arrived yet when
	# these panels were first built at boot (Overlays._ready() runs as early as
	# anything in the pipeline) — re-check live every time a panel that can show the
	# button becomes visible, instead of baking a one-time answer into construction.
	if panel_name in ["start", "game_over", "victory"]:
		_refresh_install_buttons()
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
	(p.get_node("Title") as Label).text = level_name + " CLEAR"
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
	var secondary_line := ("\n" + " · ".join(extras)) if not extras.is_empty() else ""
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
	_title(p, "BEYOND THE", 10, TITLE_COL, 6)
	_title(p, "VOID RUNNER", 18, TITLE_COL, 18)
	_line(p, 38, "RUN. SURVIVE. ESCAPE THE VOID.", 7, Color("5fb6d8"))
	_line(p, 44, "9-LEVEL CAMPAIGN · SECTOR RUN", 7, Color("5fb6d8"))
	_high_label = _line(p, 50, "", 7, KEY_COL)
	_box(p, Rect2(8, 71, 304, 60), TITLE_COL, "SYSTEM_BACKSTORY.DAT")
	_line(p, 73, "TRANSMISSION LOG — SECTOR ALPHA", 7, KEY_COL)
	_wrap_line(p, 85, Lore.story(0), 7, TEXT_COL, 30, 260)
	_wrap_line(p, 107,
		"Fly the tunnels, or the dark wins.",
		7, TEXT_COL, 24, 272)
	_line(p, 119, "TERMINAL STATUS: CRITICAL", 7, KEY_COL)
	# M1.5: the label is centred across the full 320 px and reads "SECTOR: <NAME>";
	# at font 8 the longest sector name runs to roughly x=218, which is exactly
	# where the old right arrow sat. Both arrows now live outside that span.
	_button(p, Vector2(26, 133), "<", func() -> void: _adjust_sector(-1))
	_sector_label = _line(p, 139, "", 8, KEY_COL)
	_button(p, Vector2(286, 133), ">", func() -> void: _adjust_sector(1))
	_box(p, Rect2(30, 155, 260, 18), TITLE_COL, "TERMINAL_PROMPT.EXE")
	_button(p, Vector2(38, 157), "C:VOID_RUNNER> RUN.EXE", func() -> void:
		AudioSys.unlock()
		launch_requested.emit())
	_button(p, Vector2(16, 176), "? CONTROLS", func() -> void: show_only("help"),
		Color("55ffee"))
	_button(p, Vector2(120, 176), "* SETTINGS", func() -> void:
		_settings_return = "start"
		show_only("settings"), ORANGE_COL)
	# K5: endless survival mode — the button doubles as the audio-unlock gesture
	_button(p, Vector2(224, 176), "% GAUNTLET", func() -> void:
		AudioSys.unlock()
		gauntlet_requested.emit())
	# M1.4: build stamp, so a bug report can name the build it came from
	_at(p, Vector2(4, 190), BuildInfo.label(), 7, Color("3d4a63"))
	_install_button(p, Vector2(176, 176))   # D11: quiet, next to the build stamp


func _build_help() -> void:
	var p := _panel("help")
	_title(p, "FLIGHT MANUAL", 14, TITLE_COL)
	var left := [
		"FLIGHT", "MOUSE / ARROWS  steer", "W or RMB  afterburner", "S  retro brake",
		"A / D  evade roll", "", "SYSTEM", "ENTER or ESC  pause",
	]
	# M3: the beta ask belongs with the other key bindings, and appending it here
	# (rather than placing it absolutely) keeps _help_pad and everything below it
	# flowing — an absolute line landed exactly on the gamepad row.
	if Feedback.is_configured():
		left.append("F  send beta feedback")
	var right := [
		"WEAPONS", "LMB / SPACE / X  fire", "1 NEUTRON  2 SCATTER", "3 BOLT  4 MISSILE",
		"BACKSPACE  cycle", "P  plasma bomb", "", "Locked bulkheads open when",
		"every hostile is down.",
	]
	for i in left.size():
		_at(p, Vector2(36, 52 + i * 11), left[i], 8,
			TITLE_COL if left[i] in ["FLIGHT", "SYSTEM"] else TEXT_COL)
	_help_pad = _at(p, Vector2(36, 52 + left.size() * 11), "", 8, TEXT_COL)
	for i in right.size():
		_at(p, Vector2(172, 52 + i * 11), right[i], 8,
			TITLE_COL if right[i] == "WEAPONS" else TEXT_COL)
	# M3: the short version. The full privacy note lives in the README and on the
	# form itself — anything longer than one line here and nobody reads any of it.
	_line(p, 162, "No cookies, no accounts, no personal data.", 7, Color("55647d"))
	_button(p, Vector2(88, 172), "> START", func() -> void:
		AudioSys.unlock()
		launch_requested.emit())
	_button(p, Vector2(168, 172), "< BACK", func() -> void: show_only("start"))


func _build_briefing() -> void:
	var p := _panel("briefing")
	var t := _title(p, "", 14, TITLE_COL)
	t.name = "Title"
	# V2.2 story pass: three stacked bands — dim story paragraph (lore), objective
	# block (up to 3 lines on spur levels), tactical body — sized so the worst case
	# never overlaps and the body bottom stays above the buttons at y=164.
	var s := _line(p, 48, "", 8, Color("5fb6d8"))
	s.name = "Story"
	s.position.x = 30
	s.size = Vector2(260, 36) * 2  # _line labels are 2x-size, 0.5-scale (see _line)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var o := _line(p, 86, "", 8, KEY_COL)
	o.name = "Objective"
	var b := _line(p, 124, "", 8, TEXT_COL)
	b.name = "Body"
	b.position.x = 30
	b.size = Vector2(260, 36) * 2
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(p, Vector2(58, 164), "* UPGRADE BAY", func() -> void:
		_refresh_bay()
		show_only("bay"))
	_button(p, Vector2(196, 164), "> LAUNCH", func() -> void:
		AudioSys.unlock()
		launch_requested.emit())


func _build_pause() -> void:
	var p := _panel("pause")
	# clicks must fall through so game.gd's _unhandled_input can resume
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title(p, "PAUSED", 16, TITLE_COL)
	_line(p, 100, "Click or press ENTER to re-engage", 8, TEXT_COL)
	_at(p, Vector2(4, 190), BuildInfo.label(), 7, Color("3d4a63"))   # M1.4


func _build_game_over() -> void:
	var p := _panel("game_over")
	_title(p, "HULL BREACH", 20, Color("ff5040"))
	var s := _line(p, 88, "SCORE 0", 10, KEY_COL)
	s.name = "Score"
	var rec := _line(p, 104, "", 8, Color("5fb6d8"))
	rec.name = "Record"
	_button(p, Vector2(120, 132), "@ RETRY LEVEL", func() -> void: retry_requested.emit())
	_feedback_button(p, Vector2(104, 158))   # M3
	_install_button(p, Vector2(104, 182))   # D11


func _build_level_clear() -> void:
	var p := _panel("level_clear")
	var t := _title(p, "LEVEL CLEAR", 16, TITLE_COL)
	t.name = "Title"
	# the body grew to 4 lines (KILLS / SECRETS / BONUS+SCORE / NEXT); RANK sits
	# clearly below it and the button below RANK, so nothing overlaps
	var b := _line(p, 58, "", 8, TEXT_COL)
	b.name = "Body"
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.position.x = 0
	b.size = Vector2(320, 44) * 2  # _line labels are 2x-size, 0.5-scale (see _line)
	var r := _line(p, 120, "", 14, KEY_COL)
	r.name = "Rank"
	_button(p, Vector2(120, 156), "> NEXT LEVEL", func() -> void: next_level_requested.emit())


func _build_victory() -> void:
	var p := _panel("victory")
	_title(p, "CAMPAIGN COMPLETE", 16, TITLE_COL)
	_line(p, 74, "ALL 9 SECTORS CLEARED · THE RIFT IS SHUT", 8, Color("5fb6d8"))
	var s := _line(p, 92, "SCORE 0", 10, KEY_COL)
	s.name = "Score"
	var rec := _line(p, 108, "", 8, Color("5fb6d8"))
	rec.name = "Record"
	_button(p, Vector2(112, 136), "@ NEW CAMPAIGN", func() -> void: new_campaign_requested.emit())
	_feedback_button(p, Vector2(104, 160))   # M3
	_install_button(p, Vector2(104, 184))   # D11


## H: volume + mouse sensitivity (stepper rows) and a dither on/off toggle. All
## values live on GameState, which applies + persists them; rows just adjust + refresh.
## Phase H settings, rebuilt at M2 and extended at M4c: eleven controls — three
## adjustable stepper rows across the top, then a 2x4 toggle grid. 320x200 has no
## room for eleven stacked rows, and a scrolling settings panel in a DOS cockpit
## would look wrong.
##
## M4c final review: a twelfth control (GYRO AIM) briefly lived above the box and
## pushed everything below it down by 18, which clipped the BACK button against the
## canvas bottom. It was removed — Godot 4.7's web export has no device-orientation
## source feeding Input.get_gyroscope() (grep the exported index.js: zero
## deviceorientation/devicemotion handlers), and web is this game's only mobile
## delivery, so the toggle was inert. GameState.gyro_aim_enabled and player.gd's
## additive nudge stay as dormant scaffolding for a future real JS bridge; with no
## UI to set the flag, nothing can turn them on. The layout below is back to its
## pre-gyro geometry.
func _build_settings() -> void:
	var p := _panel("settings")
	_title(p, "SETTINGS", 14, TITLE_COL, 4)
	_setting_row(p, 28, "VOLUME", "volume")
	_setting_row(p, 46, "MOUSE SENS", "sens")
	_setting_row(p, 64, "FIELD OF VIEW", "fov")
	_box(p, Rect2(8, 88, 304, 78), TITLE_COL, "COMFORT & DISPLAY")
	# left column
	_toggle_row(p, Vector2(14, 92), "DITHER", "dither", func() -> void:
		GameState.dither_enabled = not GameState.dither_enabled)
	_toggle_row(p, Vector2(14, 110), "AMBER TERM", "amber", func() -> void:
		GameState.amber_mode = not GameState.amber_mode)
	_toggle_row(p, Vector2(14, 128), "GAMEPAD", "gamepad", func() -> void:
		GameState.gamepad_enabled = not GameState.gamepad_enabled)
	_toggle_row(p, Vector2(14, 146), "INVERT Y", "invert_y", func() -> void:
		GameState.invert_y = not GameState.invert_y)
	# right column
	_toggle_row(p, Vector2(166, 92), "SCREEN SHAKE", "shake", func() -> void:
		GameState.screen_shake = not GameState.screen_shake)
	_toggle_row(p, Vector2(166, 110), "REDUCE FLASH", "reduce_flash", func() -> void:
		GameState.reduce_flashing = not GameState.reduce_flashing)
	_toggle_row(p, Vector2(166, 128), "REDUCE ROLL", "reduce_roll", func() -> void:
		GameState.reduce_roll = not GameState.reduce_roll)
	_toggle_row(p, Vector2(166, 146), "TOUCH D-PAD", "dpad", func() -> void:
		GameState.touch_dpad_enabled = not GameState.touch_dpad_enabled)
	# BACK is a plain (non-_compact) Button, so its stylebox makes it ~20 units tall:
	# y=174 puts its bottom edge at ~194, clear of the 200-unit canvas floor.
	_button(p, Vector2(134, 174), "< BACK", func() -> void: show_only(_settings_return))
	_refresh_settings()


func _setting_row(p: Control, y: float, label: String, key: String) -> void:
	_at(p, Vector2(14, y + 1), label, 8, TEXT_COL)
	_compact(_button(p, Vector2(214, y), "-", func() -> void: _adjust_setting(key, -1)))
	var val := _at(p, Vector2(240, y + 1), "", 8, KEY_COL)
	_settings_labels[key] = val
	_compact(_button(p, Vector2(276, y), "+", func() -> void: _adjust_setting(key, 1)))


## One label + ON/OFF button pair. The callable flips the GameState field; saving
## and refreshing are handled here so no caller can forget either.
func _toggle_row(p: Control, pos: Vector2, label: String, key: String,
		flip: Callable) -> void:
	_at(p, pos + Vector2(0, 2), label, 8, TEXT_COL)
	var b := _compact(_button(p, pos + Vector2(104, 0), "", func() -> void:
		flip.call()
		GameState.apply_settings()
		_refresh_settings()))
	_settings_labels[key] = b


func _adjust_setting(key: String, dir: int) -> void:
	if key == "volume":
		GameState.master_volume = clampf(GameState.master_volume + dir * 0.1, 0.0, 1.0)
	elif key == "sens":
		GameState.mouse_sens_mult = clampf(GameState.mouse_sens_mult + dir * 0.1, 0.3, 2.5)
	elif key == "fov":
		# M2.2: 60 is tight-but-period-correct, 100 is the modern comfort end
		GameState.view_fov = clampf(GameState.view_fov + dir * 4.0, 60.0, 100.0)
	GameState.apply_settings()
	_refresh_settings()


func _refresh_settings() -> void:
	_set_label("volume", "%d%%" % roundi(GameState.master_volume * 100.0))
	_set_label("sens", "%d%%" % roundi(GameState.mouse_sens_mult * 100.0))
	_set_label("fov", "%d" % roundi(GameState.view_fov))
	_set_toggle("dither", GameState.dither_enabled)
	_set_toggle("gamepad", GameState.gamepad_enabled)
	_set_toggle("amber", GameState.amber_mode)
	_set_toggle("shake", GameState.screen_shake)
	_set_toggle("reduce_flash", GameState.reduce_flashing)
	_set_toggle("reduce_roll", GameState.reduce_roll)
	_set_toggle("invert_y", GameState.invert_y)
	_set_toggle("dpad", GameState.touch_dpad_enabled)


func _set_label(key: String, text: String) -> void:
	if _settings_labels.has(key):
		(_settings_labels[key] as Label).text = text


func _set_toggle(key: String, on: bool) -> void:
	if _settings_labels.has(key):
		var b := _settings_labels[key] as Button
		b.text = "ON" if on else "OFF"
		b.add_theme_color_override("font_color", KEY_COL if on else Color("55647d"))


## M1.2: shown once, before anything else, on a build that strobes and white-outs.
## Acknowledgement persists in settings.cfg so it never nags a returning player.
func _build_warning() -> void:
	var p := _panel("warning")
	_title(p, "! PHOTOSENSITIVITY NOTICE", 12, Color("ff9c40"), 26)
	_wrap_line(p, 56,
		"VOID RUNNER contains flashing light, strobing effects and a bright "
		+ "full-screen flash when a plasma bomb detonates.",
		8, TEXT_COL, 30, 260)
	_wrap_line(p, 96,
		"If you are sensitive to flashing images, turn on REDUCE FLASH in "
		+ "SETTINGS before you fly. It stays on for good.",
		8, TEXT_COL, 30, 260)
	_button(p, Vector2(40, 150), "* OPEN SETTINGS", func() -> void:
		_ack_warning()
		_settings_return = "start"
		show_only("settings"), ORANGE_COL)
	_button(p, Vector2(186, 150), "> UNDERSTOOD", func() -> void:
		_ack_warning()
		show_only("start"))


func _ack_warning() -> void:
	GameState.seen_warning = true
	GameState.apply_settings()
	warning_acknowledged.emit()


## V2.2 L3d: Upgrade Bay — reached from the briefing (a button swaps to this panel).
## Weapon marks are per-run, ship ranks persist; buying draws from salvage (the run
## haul first, then the bank) via GameState.spend_salvage. One place, no shop sprawl.
func _build_bay() -> void:
	var p := _panel("bay")
	_title(p, "UPGRADE BAY", 14, TITLE_COL)
	_at(p, Vector2(20, 50), "WEAPON MARKS", 8, KEY_COL)
	for i in BAY_WEAPONS.size():
		_bay_row(p, 20, 64 + i * 13, "w%d" % i, BAY_WEAPONS[i])
	_at(p, Vector2(168, 50), "SHIP SYSTEMS", 8, KEY_COL)
	for i in BAY_SHIP.size():
		_bay_row(p, 168, 64 + i * 13, "s:" + BAY_SHIP[i][0], BAY_SHIP[i][1])
	_bay_salvage_label = _at(p, Vector2(20, 172), "", 8, KEY_COL)
	_button(p, Vector2(150, 180), "< BACK", func() -> void: show_only("briefing"))
	_button(p, Vector2(224, 180), "> LAUNCH", func() -> void:
		AudioSys.unlock()
		launch_requested.emit())
	_refresh_bay()


func _bay_row(p: Control, x: float, y: float, id: String, label: String) -> void:
	_at(p, Vector2(x, y + 2), label, 8, TEXT_COL)
	var status := _at(p, Vector2(x + 58, y + 2), "", 8, Color("5fb6d8"))
	var buy := _button(p, Vector2(x + 92, y), "", func() -> void: _bay_buy(id))
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

func _title(p: Control, text: String, font_size: int, color: Color, y: float = 28) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
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


## A _line()-style label that actually word-wraps to a narrower width. Godot's
## Control.size clamps up to the Label's combined minimum size, and once a
## Label with autowrap still OFF has been added to the tree at a wide size,
## setting autowrap_mode + a narrower .size afterward does NOT shrink it back
## (verified: the wide size sticks even across frames) — so autowrap_mode and
## the final .size must both be set BEFORE the label joins the tree.
func _wrap_line(p: Control, y: float, text: String, font_size: int, color: Color,
		x: float, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.scale = Vector2(0.5, 0.5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size * 2)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = Vector2(x, y)
	l.size = Vector2(width, 24) * 2
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


func _button(p: Control, pos: Vector2, text: String, on_press: Callable, color: Color = TITLE_COL) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_color_override("font_color", color)
	b.pressed.connect(on_press)
	p.add_child(b)
	return b


## M3: one feedback button, built the same way everywhere it appears. Absent
## rather than dead when no form is configured — a button that does nothing is
## worse than no button.
func _feedback_button(p: Control, pos: Vector2) -> void:
	if not Feedback.is_configured():
		return
	_button(p, pos, "F  SEND FEEDBACK", func() -> void: Feedback.open_form(), ORANGE_COL)


## D11: one install-nudge button, built the same way everywhere it appears.
## Compact-styled (see _compact) and TEXT_COL rather than a CTA color, because
## this is a passive, always-skippable nudge, never a gate — "ask only at the
## end," per D11. Never built at all off the web (desktop/headless — JavaScriptBridge
## doesn't exist there and never will). On the web it IS always constructed, but
## starts hidden: beforeinstallprompt (which vrCanInstall() depends on) fires
## asynchronously and may not have arrived yet by the time this panel is first
## built at boot (Overlays._ready() runs as early as anything in the pipeline), so
## the yes/no answer can't be decided once here. _refresh_install_buttons() below
## re-checks live and shows/hides it whenever a panel that can display it is shown.
func _install_button(p: Control, pos: Vector2) -> void:
	if not OS.has_feature("web"):
		return
	var b := _compact(_button(p, pos, "INSTALL APP", func() -> void:
		JavaScriptBridge.eval("if (window.vrPromptInstall) window.vrPromptInstall();"), TEXT_COL))
	b.add_theme_font_size_override("font_size", 6)   # quieter still — narrow enough to sit in a row gap
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


## M2: Godot's default Button stylebox carries enough content margin that at font
## size 8 a button is ~20 design px tall — taller than a settings row's pitch, so
## stacked rows overlap. These flat, near-zero-margin boxes make a toggle button
## about as tall as its text, which is what the 320x200 grid was drawn for.
func _compact(b: Button) -> Button:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.content_margin_left = 2.0
		sb.content_margin_right = 2.0
		sb.content_margin_top = 0.0
		sb.content_margin_bottom = 0.0
		if state == "hover" or state == "focus":
			sb.border_color = TITLE_COL
			sb.set_border_width_all(1)
		b.add_theme_stylebox_override(state, sb)
	return b


func _box(p: Control, rect: Rect2, color: Color, label: String) -> Panel:
	var b := Panel.new()
	b.position = rect.position
	b.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.set_border_width_all(1)
	b.add_theme_stylebox_override("panel", sb)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(b)
	if label != "":
		var l := Label.new()
		l.text = "[ %s ]" % label
		l.position = Vector2(rect.position.x + 4, rect.position.y - 9)
		l.add_theme_font_size_override("font_size", 7)
		l.add_theme_color_override("font_color", color)
		p.add_child(l)
	return b
