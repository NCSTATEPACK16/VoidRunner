extends Node
## Rendered screenshot probe (K7 gate prep): godot tests/screenshot_probe.tscn
## (NO --headless — it needs the real rasterizer). Boots the game, flies three
## representative moments, and saves the native 320x200 SubViewport frame as PNG:
##   1. L1 plain corridor in flight   -> shot_corridor.png
##   1b. Tab automap over explored L1  -> shot_automap.png
##   2. L1 first arena, guards live   -> shot_arena.png
##   2b. bolts, missile, fireballs    -> shot_combat.png
##   2b'. a kill's debris, still hot  -> shot_debris.png (v4)
##   2c. stinger/spinner/mines + power-up timers -> shot_threats.png
##   3. L3 boss room, boss in view    -> shot_boss.png
##   4. game-over / victory panels    -> shot_game_over.png / shot_victory.png
##   5. touch II tab over flight, then the pause menu -> shot_touch.png / shot_pause.png
##   6. difficulty panel (Step 3)      -> shot_difficulty.png
##   7. touch page of the manual (Step 5) -> shot_help_touch.png
## Output dir: VR_SHOT_DIR env var, else user://shots. Restores records/settings.


func _ready() -> void:
	_run()


func _shot_dir() -> String:
	var dir := OS.get_environment("VR_SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _capture(game: Node3D, file_name: String, dir: String) -> void:
	await RenderingServer.frame_post_draw
	var view: SubViewport = game.view
	var img: Image = view.get_texture().get_image()
	img.save_png(dir + "/" + file_name)
	# the state rides along so a stray auto-pause (focus loss under xvfb) shows up,
	# and so do the 3D view's draw calls and objects for that frame (v4 perf gate)
	print("[shot] %s/%s state=%d draws=%d objects=%d" % [dir, file_name, game.state,
		view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
			Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
			Viewport.RENDER_INFO_OBJECTS_IN_FRAME)])


## Root-window capture — overlays (briefing/menus) render at native res OUTSIDE
## the 320x200 game SubViewport, so the in-view capture above can't see them.
func _capture_root(file_name: String, dir: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(dir + "/" + file_name)
	print("[shot] %s/%s" % [dir, file_name])


## Rail-steer like the smoke test so corners never stall the flight.
func _fly(game: Node3D, frames: int) -> void:
	for f in frames:
		GameState.shields = 100.0
		var pd: Vector3 = game.path.rings[mini(game.player.ring_idx + 2,
			game.path.rings.size() - 1)].d
		game.player.yaw = atan2(-pd.x, -pd.z)
		game.player.pitch = clampf(asin(pd.y), -0.6, 0.6)
		await get_tree().process_frame


func _run() -> void:
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg", "user://checkpoint.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var dir := _shot_dir()
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.unlocked_level = 0
	game.overlays._sector = 0
	GameState.level_index = 0
	GameState.score = 0
	game.overlays.show_only("start")
	for i in 150:   # 3.0: let the attract-mode flythrough get going behind the title
		await get_tree().process_frame
	game.overlays.set_continue("L4")   # re-audit Step 4: the CONTINUE row lit
	await _capture_root("shot_start.png", dir)   # title option B: attract mode
	game.overlays._open_start_menu()
	for i in 30:   # past the stepped slide
		await get_tree().process_frame
	await _capture_root("shot_start_menu.png", dir)
	game.overlays._new_btn.pressed.emit()
	await _capture_root("shot_new_game.png", dir)
	# M1/M2: the two panels this session changed most — the settings grid now packs
	# ten controls into 320x200, and the photosensitivity notice is brand new.
	game.overlays.show_only("warning")
	await _capture_root("shot_warning.png", dir)
	game.overlays.show_only("settings")
	await _capture_root("shot_settings.png", dir)
	game.overlays.show_only("help")
	await _capture_root("shot_help.png", dir)   # M3 privacy + feedback lines
	game.overlays.touch_mode = true          # re-audit Step 5: the manual's touch page
	game.overlays.show_only("help")
	await _capture_root("shot_help_touch.png", dir)
	game.overlays.touch_mode = false
	game.overlays.open_difficulty("start")   # re-audit Step 3: preset + assists
	await _capture_root("shot_difficulty.png", dir)
	game.overlays.show_only("start")
	await get_tree().process_frame
	game._show_briefing()
	for i in 30:
		await get_tree().process_frame   # warm-up rig compiles behind the briefing
	# 0) the briefing itself — story/objective/body bands must not overlap (V2.2)
	await _capture_root("shot_briefing.png", dir)
	game._on_launch()
	await get_tree().process_frame
	# 1) corridor in flight — far enough in that fog/strip/lighting all read
	await _fly(game, 60 * 6)
	await _capture(game, "shot_corridor.png", dir)
	await _fly(game, 30)   # v4a: half a second on, the colour cycling has moved
	await _capture(game, "shot_corridor2.png", dir)
	# 1b) Tab automap over the explored corridor — must read as a 1995 automap
	game._open_automap()
	await _capture(game, "shot_automap.png", dir)
	game.automap.close()
	# 2) first arena with its guards still alive
	var arena: Dictionary = game.path.arenas[0]
	var aring: Dictionary = game.path.rings[arena.start + 2]
	game.player.ring_idx = arena.start + 2
	game.player.position = aring.p
	game.player.yaw = atan2(-aring.d.x, -aring.d.z)
	game.player.pitch = 0.0
	await _fly(game, 30)   # let enemies turn toward us and shots fly
	await _capture(game, "shot_arena.png", dir)
	# 2b) 3.0 combat: bolts in flight (lighting the walls), a missile trailing smoke,
	# and blasts at two stages of their fireball
	var fwd: Vector3 = game.player.forward()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	game.shot_mgr.spawn_explosion(game.player.position + fwd * 26.0 + right * 7.0, true)
	await _fly(game, 5)
	game.shot_mgr.spawn_explosion(game.player.position + fwd * 20.0 - right * 6.0, false)
	GameState.weapon_index = 3
	game.shot_mgr.fire_player(game.weapons[3])
	GameState.weapon_index = 0
	for k in 8:
		game.shot_mgr.fire_player(game.weapons[0])
		await _fly(game, 2)
	await _capture(game, "shot_combat.png", dir)
	# 2b') v4 hot debris: a kill's chunks, yellow-hot and cooling down the fire ramp
	game.gib_mgr.burst(game.player.position + fwd * 14.0, Vector3.ZERO,
		game.player.ring_idx, 20, EnemyManager.GIB_TINTS["drone"])
	await _fly(game, 9)   # ~0.15 s in: mid-cooling
	await _capture(game, "shot_debris.png", dir)
	# 2c) 3.0 phase 5 threats: a stinger mid-tell, a spinner's ring in flight and
	# two mines ahead (the near one arms as we close), with OVERDRIVE and POWER
	# CORE timers live on the HUD
	var em: EnemyManager = game.enemy_mgr
	em.clear_all()
	game.shot_mgr.clear_all()
	fwd = game.player.forward()
	right = fwd.cross(Vector3.UP).normalized()
	var pr: int = game.player.ring_idx
	em.spawn(pr, -1, "stinger")
	var sting: Dictionary = em.enemies.back()
	sting.node.position = game.player.position + fwd * 30.0 + right * 6.0 + Vector3.UP * 1.5
	sting.mode = "wind"
	sting.mode_t = 5.0   # hold the tell for the capture
	em.spawn(pr, -1, "spinner")
	var spinner: Dictionary = em.enemies.back()
	spinner.node.position = game.player.position + fwd * 44.0 - right * 5.0
	spinner.fire_t = 0.0
	for mp in [fwd * 18.0 - right * 7.0 - Vector3.UP * 2.0, fwd * 27.0 + right * 2.0 + Vector3.UP * 2.0]:
		em.spawn(pr, -1, "mine")
		em.enemies.back().node.position = game.player.position + mp
	GameState.grant_power("overdrive")
	GameState.grant_power("powercore")
	await _fly(game, 20)
	await _capture(game, "shot_threats.png", dir)
	GameState.clear_powers()
	# 2d) v4b roster (part 1), each mid-rule: a layer down the tunnel with a mine just
	# laid behind it, a rammer's red flare, a mender patching a drone (green sparks),
	# and a splitter beside the brood that just burst out of another
	em.clear_all()
	game.shot_mgr.clear_all()
	fwd = game.player.forward()
	right = fwd.cross(Vector3.UP).normalized()
	pr = game.player.ring_idx
	GameState.reduce_flashing = true   # holds the tells steady for the still
	var roster := {
		"layer": fwd * 46.0 + Vector3.UP * 1.5,
		"rammer": fwd * 34.0 - right * 5.0 + Vector3.UP * 2.0,
		"mender": fwd * 26.0 + right * 5.5 - Vector3.UP * 2.0,
		"splitter": fwd * 20.0 - right * 4.0 - Vector3.UP * 2.5,
	}
	for id in roster:
		em.spawn(pr, -1, id)
		var en: Dictionary = em.enemies.back()
		en.node.position = game.player.position + roster[id]
		en.facing = -fwd
	var medic: Dictionary = {}
	for en in em.enemies:
		match en.type:
			"layer":
				en.fire_t = 0.0   # a mine on its way down
			"rammer":
				en.mode = "rev"
				en.mode_t = 5.0
			"mender":
				medic = en
				en.fire_t = 0.0
	em.spawn(pr, -1, "drone")   # the mender's patient
	em.enemies.back().node.position = medic.node.position + right * 5.0
	em.enemies.back().hp = 1
	em.spawn(pr, -1, "splitter")   # and one that bursts into its brood
	em.enemies.back().node.position = game.player.position + fwd * 30.0 + right * 3.0
	em.hit_enemy(em.enemies.size() - 1, 99)
	await _fly(game, 6)
	await _capture(game, "shot_roster.png", dir)
	# 2e) v4b roster (part 2): a warden dead ahead turning a NEUTRON stream (blue
	# sparks), a wraith half-faded in (the REDUCE FLASH tell, held), a crawler bursting
	# from its wall and a carrier broadside, its bays toward us
	em.clear_all()
	game.shot_mgr.clear_all()
	game.gib_mgr.clear_all()
	# from the first long straight of plain tunnel, so the far ones aren't behind a door
	var open_r := pr
	for r in range(21, game.path.main_ring_count - 10):
		var open := true
		for q in range(r, r + 8):
			open = open and not game.path.rings[q].arena and em._straight(q)
		if open:
			open_r = r
			break
	var oring: Dictionary = game.path.rings[open_r]
	game.player.ring_idx = open_r
	game.player.position = oring.p
	game.player.yaw = atan2(-oring.d.x, -oring.d.z)
	game.player.pitch = 0.0
	await _fly(game, 2)
	fwd = game.player.forward()
	right = fwd.cross(Vector3.UP).normalized()
	pr = game.player.ring_idx
	var roster2 := {
		"warden": fwd * 20.0 - Vector3.UP * 1.5,
		"wraith": fwd * 14.0 - right * 6.0 + Vector3.UP * 2.0,
		"carrier": fwd * 34.0 + right * 3.0 + Vector3.UP * 3.0,
	}
	for id in roster2:
		em.spawn(pr, -1, id)
		var en: Dictionary = em.enemies.back()
		en.node.position = game.player.position + roster2[id]
		en.facing = -fwd
		match id:
			"wraith":
				en.mode = "shimmer"
				en.cloaked = false
				en.hit_r2 = 13.0
				en.tell = 8.0
				en.mode_t = 3.6   # hold the fade at half-light for the still
			"carrier":
				en.facing = right   # broadside, bays toward us
				en.side = -1.0      # (and turning to stay that way)
				en.launch_t = 99.0  # (a fresh drone would hide it)
				en.fire_t = 99.0
	em.spawn(pr + 2, -1, "crawler")
	var crawl: Dictionary = em.enemies.back()
	crawl.side = 1.0   # the right-hand wall
	crawl.fire_t = 0.0
	GameState.weapon_index = 0
	for k in 4:
		game.shot_mgr.fire_player(game.weapons[0])
		await _fly(game, 2)
	await _capture(game, "shot_roster2.png", dir)
	# 2f) the heavies beside their base types: each wears its base's sprite set with a
	# tint folded into the light (left column base, right column heavy)
	em.clear_all()
	game.shot_mgr.clear_all()
	game.gib_mgr.clear_all()
	var hv_row := 3.4
	for base_id in ["rammer", "splitter", "warden"]:
		for col in [-1.0, 1.0]:
			em.spawn(pr, -1, base_id if col < 0.0 else base_id + "_hv")
			var en: Dictionary = em.enemies.back()
			en.node.position = game.player.position + fwd * 30.0 + right * (5.0 * col) \
				+ Vector3.UP * hv_row
			en.facing = -fwd
			en.mode_t = 99.0   # (no rammer tell, no wind-up)
			en.fire_t = 99.0
		hv_row -= 3.4
	await _fly(game, 3)
	await _capture(game, "shot_heavies.png", dir)
	GameState.reduce_flashing = false
	# 3) L3 boss room with the boss in frame
	GameState.reset_run()
	GameState.level_index = 2
	game._launch_level()
	await get_tree().process_frame
	var room: Dictionary = game.path.arenas.back()
	# the boss sits at room.end - 8 and boss-level fog ends ~110 u: shoot from
	# ~5 rings (60 u) out so the signature is actually in frame
	var bidx: int = room.end - 13
	var bring: Dictionary = game.path.rings[bidx]
	game.player.ring_idx = bidx
	game.player.position = bring.p
	game.player.yaw = atan2(-bring.d.x, -bring.d.z)
	game.player.pitch = 0.0
	await _fly(game, 45)
	await _capture(game, "shot_boss.png", dir)
	# 3b) v4b mini-boss: L8's GATE WARDEN awake in its room behind its shield, its name
	# and bar (one tick, at 50%) on the HUD
	GameState.reset_run()
	GameState.level_index = 7
	game._launch_level()
	await get_tree().process_frame
	var mroom: Dictionary = game.path.arenas[game._miniboss_arena]
	for a in game.path.arenas:   # the bulkheads before its room, open (as a resume would)
		if a.door_ring >= 0 and a.door_ring < mroom.start:
			game.world.open_door(a.id)
	var mring_i: int = int(mroom.start) + 1
	var mring: Dictionary = game.path.rings[mring_i]
	game.player.ring_idx = mring_i
	game.player.position = mring.p
	game.player.yaw = atan2(-mring.d.x, -mring.d.z)
	game.player.pitch = 0.0
	game.enemy_mgr.boss.hp = int(game.enemy_mgr.boss.max_hp * 0.7)
	await _fly(game, 30)
	await _capture(game, "shot_miniboss.png", dir)
	# 5) re-audit Step 2: the touch layer's II pause tab over flight, then the menu
	var touch := TouchControls.new()
	add_child(touch)
	touch.enable(game.player)
	await _fly(game, 2)
	await _capture_root("shot_touch.png", dir)
	touch.set_flight_active(false)
	touch.queue_free()
	game._toggle_pause()
	await _capture_root("shot_pause.png", dir)
	game._toggle_pause()
	# 4) game-over and victory — Task 4's install-nudge button lands on both; these
	# overlays render outside the 320x200 SubViewport, hence _capture_root.
	game.overlays.set_final_score("game_over", 4200, false)
	game.overlays.suggest_recruit()   # Step 3: the repeat-death hint line
	game.overlays.set_retry_options(true)   # Step 4: checkpoint first, then restart
	game.overlays.show_only("game_over")
	await _capture_root("shot_game_over.png", dir)
	game.overlays.set_final_score("victory", 15800, true)
	game.overlays.show_only("victory")
	await _capture_root("shot_victory.png", dir)
	print("SCREENSHOT PROBE COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
