extends Node
## Headless campaign probe (v4d): godot --headless tests/campaign_probe.tscn
## Plays the whole campaign, L1 to L9, the way a player would, through the real buttons:
##   warning notice -> PRESS ENTER -> card row -> NEW GAME -> LAUNCH -> episode title card ->
##   briefing LAUNCH -> fly (rail, god mode, fire held, RailAssist does the guards, hub keys
##   and objectives) -> tally (L1 left to reveal on its own, the rest skipped by a real input
##   event) -> NEXT / CONTINUE -> episode ending on L3, L6 and L9 -> the next title card ->
##   ... -> the victory panel.
## It records the sequence of (state, panel) stops and compares it with the expected list, and
## keeps the old soak probe's checks:
##   - every enemy type in EnemyManager.TYPES spawned somewhere in the campaign,
##   - every boss reached phase 3 and died,
##   - every mini-boss woke, reached phase 2 and died, and no boss_killed came of it.
## A stuck level or screen prints where it stuck and exits non-zero after a wall-clock limit
## (no asserts: a failed assert hangs headless Godot). Seeded, so a run is repeatable.
## Restores records/settings/checkpoint on exit, like the other probes.

const RailAssist := preload("res://tests/rail_assist.gd")
## Same seed the soak settled on (v4c: 4040 never rolled a WARDEN on L8). VR_CAMPAIGN_SEED overrides it.
const CAMPAIGN_SEED := 4041
const MAX_STEPS := 60 * 300       # per sector: five minutes of flight is a stuck run
const LEVEL_WALL_SECS := 240.0    # per sector wall-clock limit, flight included
const WAIT_SECS := 20.0           # any one menu wait (briefing build, tally, panel change)

var _saved := {}
var _seq: Array[String] = []
var _game: Node3D
var _where := "boot"              # what the probe is doing, for the stuck message


func _ready() -> void:
	_run()


## Print, restore the player's files and exit non-zero. Never returns (quit lands at frame end).
func _fail(msg: String) -> void:
	print("CAMPAIGN PROBE FAILED at %s: %s" % [_where, msg])
	if _game != null:
		print("  state=%d panel=%s level=%d" % [_game.state, _game.overlays._shown,
			GameState.level_index + 1])
	print("  sequence so far: %s" % ", ".join(_seq))
	_restore()
	get_tree().quit(1)
	while true:
		await get_tree().process_frame


func _restore() -> void:
	for f in _saved:
		if _saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(_saved[f])
			fh.close()


## Wait for `cond` to hold (checked once per frame) for at most WAIT_SECS of wall clock.
func _until(cond: Callable, what: String) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - t0) / 1000.0 > WAIT_SECS:
			await _fail("timed out waiting for " + what)
		await get_tree().process_frame


## The game must be in `state` with `panel` showing; the stop is recorded in the sequence.
func _at(state: int, panel: String, label: String) -> void:
	_where = label
	var ov: Overlays = _game.overlays
	if _game.state != state or ov._shown != panel or not (ov._panels[panel] as Control).visible:
		await _fail("expected state %d with panel '%s'" % [state, panel])
	_seq.append(label)


## A real press, delivered through the input pipeline (the overlays' _input sees it).
func _press_key() -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ENTER
		k.physical_keycode = KEY_ENTER
		k.pressed = down
		Input.parse_input_event(k)
		await get_tree().process_frame


func _click() -> void:
	for down in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.position = Vector2(160, 100)
		m.pressed = down
		Input.parse_input_event(m)
		await get_tree().process_frame


func _press_button(b: Button, what: String) -> void:
	if b == null or not b.is_visible_in_tree() or b.disabled:
		await _fail("button not pressable: " + what)
	b.pressed.emit()
	await get_tree().process_frame


func _button_with_text(panel: Control, text: String) -> Button:
	for c in panel.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
	return null


func _expected_sequence() -> Array[String]:
	var want: Array[String] = ["warning", "title:attract", "title:cards", "title:new_game"]
	for li in 9:
		if li % 3 == 0:
			want.append("episode_title:E%d" % (li / 3 + 1))
		want.append("briefing:L%d" % (li + 1))
		want.append("playing:L%d" % (li + 1))
		want.append("tally:L%d" % (li + 1))
		if li % 3 == 2:
			want.append("episode_end:E%d" % (li / 3 + 1))
	want.append("victory")
	return want


func _run() -> void:
	for f in ["user://records.cfg", "user://settings.cfg", "user://checkpoint.cfg"]:
		_saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var t_start := Time.get_ticks_msec()
	_game = load("res://scenes/game.tscn").instantiate()
	var game: Node3D = _game
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var seed_env := OS.get_environment("VR_CAMPAIGN_SEED")
	seed(int(seed_env) if seed_env != "" else CAMPAIGN_SEED)
	var ov: Overlays = game.overlays
	var em: EnemyManager = game.enemy_mgr
	var seen := {}               # every type that spawned, campaign-wide
	var phases := {}             # level index -> boss phases seen
	var boss_deaths := [0]
	var mini_deaths := [0]
	em.boss_phase.connect(func(p: int) -> void:
		var got: Array = phases.get(GameState.level_index, [])
		got.append(p)
		phases[GameState.level_index] = got)
	em.boss_killed.connect(func() -> void: boss_deaths[0] += 1)
	em.miniboss_killed.connect(func() -> void: mini_deaths[0] += 1)

	# ---- the title, as a first-time player meets it ----
	GameState.reset_run()
	GameState.score = 0
	GameState.unlocked_level = 0     # a fresh profile: NEW GAME offers sector 1
	GameState.seen_warning = false
	ov._sector = 0
	ov.show_only("warning")
	await get_tree().process_frame
	await _at(game.State.MENU, "warning", "warning")
	await _press_button(_button_with_text(ov._panels.warning, "> UNDERSTOOD"), "UNDERSTOOD")
	await _at(game.State.MENU, "start", "title:attract")
	if ov._start_open:
		await _fail("the title should open in attract mode")
	await _press_button(ov._press_btn, "PRESS ENTER")
	await _at(game.State.MENU, "start", "title:cards")
	if not ov._start_open or not ov._strip.visible:
		await _fail("PRESS ENTER should open the card row")
	await _press_button(ov._new_btn, "NEW GAME card")
	await _at(game.State.MENU, "new_game", "title:new_game")
	if not ov._sector_label.text.contains("L1 "):
		await _fail("NEW GAME should offer sector 1, shows '%s'" % ov._sector_label.text)

	var dt := 1.0 / 60.0
	var times: Array[float] = []
	var completed := 0
	var tallies_done := 0
	for li in game.levels.size():
		var lv: LevelDef = game.levels[li]
		var ep: int = li / 3
		var t_level := Time.get_ticks_msec()
		# -- into the level: LAUNCH (level 1) / NEXT, then the title card, then the briefing --
		if li == 0:
			await _press_button(ov._focus["new_game"], "new_game LAUNCH")
		if li % 3 == 0:
			await _at(game.State.EPISODE, "episode_title", "episode_title:E%d" % (ep + 1))
			if GameState.level_index != li:
				await _fail("the title card is for level %d, expected %d" % [
					GameState.level_index + 1, li + 1])
			var card: Control = ov._panels.episode_title
			if (card.get_node("Name") as Label).text != Lore.episode_name(ep) \
					or (card.get_node("Number") as Label).text != "EPISODE %d OF %d" % [
					ep + 1, Lore.EPISODE_COUNT]:
				await _fail("episode %d title card text is wrong" % (ep + 1))
			# dismiss: a key press, a click, then the card's own timer
			await _until(func() -> bool: return ov._title_t >= Overlays.TITLE_ARM + 0.05,
				"the title card to arm")
			if ep == 0:
				await _press_key()
			elif ep == 1:
				await _click()
			else:
				await _until(func() -> bool: return game.state != game.State.EPISODE,
					"the title card to time out")
			await _until(func() -> bool: return game.state == game.State.BRIEFING,
				"the briefing after the title card")
		await _at(game.State.BRIEFING, "briefing", "briefing:L%d" % (li + 1))
		var b_title := (ov._panels.briefing.get_node("Title") as Label).text
		if b_title != Overlays.sector_name(lv.display_name):
			await _fail("briefing title is '%s'" % b_title)
		# let the level build and the warm-up rig clear behind the briefing, as a reader would
		await _until(func() -> bool: return game._warmup_rig == null, "the warm-up rig to clear")
		for i in 3:
			await get_tree().process_frame
		await _press_button(ov._briefing_launch, "briefing LAUNCH")
		if game.state != game.State.PLAYING:
			await _fail("LAUNCH did not start flight")
		_seq.append("playing:L%d" % (li + 1))
		_where = "flying L%d" % (li + 1)

		# -- fly it --
		var types_here := {}
		var worst_us := 0
		var steps := 0
		Input.action_press("fire")
		for f in MAX_STEPS:
			GameState.shields = 100.0
			GameState.is_dead = false
			RailAssist.step(game, f, true)   # steer, clear guards, key, objectives, boss hits
			var t0 := Time.get_ticks_usec()
			game._process(dt)
			worst_us = maxi(worst_us, Time.get_ticks_usec() - t0)
			steps += 1
			for e in em.enemies:
				types_here[e.type if e.has("type") else e.get("model", "boss")] = true
			if game.state != game.State.PLAYING:
				break
			if f % 120 == 0 and (Time.get_ticks_msec() - t_level) / 1000.0 > LEVEL_WALL_SECS:
				break
		Input.action_release("fire")
		var census := types_here.keys()
		census.sort()
		var done: bool = game.state == game.State.LEVEL_CLEAR
		print("[campaign] L%d %s: %s after %d steps (%.0f s), worst step %.1f ms, ring %d/%d · %s" % [
			li + 1, lv.kind, "CLEAR" if done else "STUCK state=%d" % game.state,
			steps, steps * dt, worst_us / 1000.0, game.player.ring_idx, game.path.main_ring_count,
			", ".join(census)])
		if not done:
			await _fail("L%d did not reach LEVEL_CLEAR (limit %.0f s wall / %d steps)" % [
				li + 1, LEVEL_WALL_SECS, MAX_STEPS])
		seen.merge(types_here)
		completed += 1

		# -- the tally: L1 reveals on its own, the rest are skipped by a real key press --
		await _at(game.State.LEVEL_CLEAR, "level_clear", "tally:L%d" % (li + 1))
		var next_btn: Button = ov._focus["level_clear"]
		if next_btn.visible or ov.tally_done():
			await _fail("the tally should start hidden and revealing")
		if li == 0:
			await _until(func() -> bool: return ov.tally_done(), "the tally to reveal itself")
		else:
			await get_tree().process_frame
			await _press_key()
			if ov.tally_revealed() < 1 or next_btn.visible:
				await _fail("a key press should skip to the totals with NEXT held back")
			await _until(func() -> bool: return ov.tally_done(), "NEXT after a skipped tally")
		var body := (ov._panels.level_clear.get_node("Body") as Label).text
		var rank_lbl: Label = ov._panels.level_clear.get_node("Rank")
		var want_next := "> CONTINUE" if li % 3 == 2 else "> NEXT LEVEL"
		if not (ov.tally_done() and next_btn.visible and rank_lbl.visible and "SCORE " in body
				and next_btn.text == want_next):
			await _fail("tally totals/NEXT not shown right (next '%s', want '%s')" % [
				next_btn.text, want_next])
		tallies_done += 1
		times.append((Time.get_ticks_msec() - t_level) / 1000.0)
		print("[campaign] L%d tally ok · level took %.1f s wall" % [li + 1, times[li]])

		# -- on: NEXT; an episode's last sector shows its ending first --
		await _press_button(next_btn, "tally %s" % next_btn.text)
		if li % 3 == 2:
			await _at(game.State.EPISODE, "episode_end", "episode_end:E%d" % (ep + 1))
			var end: Control = ov._panels.episode_end
			if (end.get_node("Ending") as Label).text != Lore.episode_ending(ep) \
					or (end.get_node("Heading") as Label).text != "%s · %s" % [
					Lore.episode_id(ep), Lore.episode_name(ep)]:
				await _fail("episode %d ending text is wrong" % (ep + 1))
			await _press_button(ov._episode_btn, "ending CONTINUE")
			if li == game.levels.size() - 1:
				await _at(game.State.VICTORY, "victory", "victory")
			elif game.state != game.State.EPISODE or GameState.level_index != li + 1:
				await _fail("the ending should lead to the next episode's title card")
		elif game.state != game.State.BRIEFING or GameState.level_index != li + 1:
			await _fail("NEXT should open the next briefing")

	# ---- the verdict ----
	_where = "verdict"
	var want := _expected_sequence()
	if _seq != want:
		print("expected: %s" % ", ".join(want))
		await _fail("the state/panel sequence differs from the expected one")
	var missing: Array = []
	for id in EnemyManager.TYPES:
		if not seen.has(id):
			missing.append(id)
	print("[campaign] types never spawned: %s" % (str(missing) if not missing.is_empty() else "none"))
	if not missing.is_empty():
		await _fail("types never spawned: " + str(missing))
	var minis := 0
	for li in game.levels.size():
		var lv: LevelDef = game.levels[li]
		var got: Array = phases.get(li, [])
		if lv.kind == "boss":
			print("[campaign] L%d %s phases %s" % [li + 1, lv.boss_name, str(got)])
			if not (got.has(2) and got.has(3)):
				await _fail("L%d boss missed a phase" % (li + 1))
		elif lv.miniboss_model != "":
			print("[campaign] L%d mini-boss %s phases %s" % [li + 1, lv.miniboss_name, str(got)])
			if got != [2]:
				await _fail("L%d mini-boss phases %s, expected [2]" % [li + 1, str(got)])
			minis += 1
	if not (boss_deaths[0] == 3 and mini_deaths[0] == minis and minis == 3):
		await _fail("boss/mini-boss deaths %d/%d (minis %d), expected 3/3" % [
			boss_deaths[0], mini_deaths[0], minis])
	if completed != game.levels.size() or tallies_done != game.levels.size():
		await _fail("completed %d, tallies %d" % [completed, tallies_done])
	print("[campaign] sequence: %s" % ", ".join(_seq))
	var per_level: Array[String] = []
	for i in times.size():
		per_level.append("L%d %.0f s" % [i + 1, times[i]])
	print("[campaign] per-level wall time: %s" % ", ".join(per_level))
	print("CAMPAIGN PROBE COMPLETE — %d sectors, %d tallies, 3 episodes, %d types, %d bosses and %d mini-bosses down, victory (%.0f s)" % [
		completed, tallies_done, seen.size(), boss_deaths[0], mini_deaths[0],
		(Time.get_ticks_msec() - t_start) / 1000.0])
	_restore()
	get_tree().quit()
