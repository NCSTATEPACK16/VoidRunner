extends Node
## Headless smoke test: godot --headless tests/smoke_test.tscn
## Boots the real game scene, forces the briefing->launch flow, then steps the
## simulation with a fixed delta while holding the fire action — exercising flight,
## wall bounce, chunk streaming, enemies, shots, heat/overheat, and arena locks.
## Phase J adds: probe-loop over all 9 levels, boss-room PathGen invariants, and a
## scripted boss kill that must wake the exit portal.


func _ready() -> void:
	_run()


func _run() -> void:
	# the test completes levels — snapshot and restore the player's real records
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	# PathGen unit pass over every campaign level (probe loop = level count check)
	var count := 0
	var i := 1
	while ResourceLoader.exists("res://resources/levels/level_%d.tres" % i):
		var level: LevelDef = load("res://resources/levels/level_%d.tres" % i)
		var path := PathGen.new()
		var is_boss := level.kind == "boss"
		path.generate(level.rings, level.level_seed, level.spawn_arena, is_boss)
		assert(path.rings.size() == level.rings)
		var locked := 0
		for arena in path.arenas:
			if arena.door_ring >= 0:
				locked += 1
				assert(not arena.spawn_rings.is_empty())
		if is_boss:
			# one clean room: no bulkheads, no random pre-spawns, full width
			assert(path.arenas.size() == 1)
			assert(locked == 0)
			var room: Dictionary = path.arenas[0]
			assert(room.end - room.start >= 20)
			assert(path.rings[path.rings.size() - 1].hw > 40.0)
			assert(level.boss_hp > 0)
		# --- K2/V-08 geometry invariants ---
		var hard_corners := 0
		var min_dot := 1.0
		for ri in path.rings.size():
			var ring: Dictionary = path.rings[ri]
			assert(ring.fo >= 0.0 and ring.co >= 0.0)
			# flyable vertical span never pinches below the player's margins
			assert(2.0 * ring.hh - ring.fo - ring.co >= 6.0)
			if ring.arena_center:
				assert(ring.fo < 0.5 and ring.co < 0.5)  # combat spaces stay flat
			if ri > 0:
				var dot: float = path.rings[ri - 1].d.dot(ring.d)
				min_dot = minf(min_dot, dot)
				if dot < 0.95:
					hard_corners += 1
		assert(min_dot > 0.7)  # corners turn hard but never fold the tunnel back
		if is_boss:
			assert(hard_corners == 0)  # boss approach stays smooth
			for ri in range(path.arenas[0].start, path.rings.size()):
				assert(path.rings[ri].fo < 0.5 and path.rings[ri].co < 0.5)
		print("L%d(%s): rings=%d arenas=%d locked=%d corners=%d" % [
			i, level.kind, path.rings.size(), path.arenas.size(), locked, hard_corners])
		i += 1
		count += 1
	assert(count == 9)
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	print("boot ok — state=%d levels=%d" % [game.state, game.levels.size()])
	game._on_launch()   # MENU -> BRIEFING
	game._on_launch()   # BRIEFING -> PLAYING
	await get_tree().process_frame
	assert(game.state == game.State.PLAYING)
	Input.action_press("fire")
	var dt := 1.0 / 60.0
	var peak_enemies := 0
	var overheated_seen := false
	for f in 60 * 240:  # up to 4 simulated minutes
		game._process(dt)
		peak_enemies = maxi(peak_enemies, game.enemy_mgr.enemies.size())
		if GameState.is_overheated:
			overheated_seen = true
		if game.state != game.State.PLAYING:
			break
	Input.action_release("fire")
	print("end state=%d ring=%d/%d shields=%.0f score=%d peak_enemies=%d overheat=%s" % [
		game.state, game.player.ring_idx, game.path.rings.size(),
		GameState.shields, GameState.score, peak_enemies, overheated_seen])
	# --- Phase J: boss level — spawn, dormant portal, kill wakes the exit ring ---
	GameState.reset_run()
	GameState.level_index = 2   # L3 · DOCK SENTINEL
	game._launch_level()
	await get_tree().process_frame
	assert(not game.enemy_mgr.boss.is_empty())
	assert(not game.world.portal_active)
	# boss resupply stations: L3 = 1 shield + 1 missile on the back wall, and a
	# collected one respawns on replenish (wired to boss phase transitions)
	assert(game.pickup_mgr._stations.size() == 2)
	var st: Dictionary = game.pickup_mgr._stations[0]
	st.node.queue_free()
	st.node = null
	game.pickup_mgr.replenish_stations()
	assert(st.node != null)
	print("stations ok — %d placed, replenish respawns" % game.pickup_mgr._stations.size())
	var b: Dictionary = game.enemy_mgr.boss
	var hp0: int = b.hp
	game.enemy_mgr.splash_damage(b.node.position, 5.0, 60)
	assert(game.enemy_mgr.boss.hp == hp0 - 60)
	game._process(dt)   # lets the phase transition emit
	game.enemy_mgr.splash_damage(b.node.position, 5.0, 9999)
	await get_tree().process_frame
	assert(game.enemy_mgr.boss.is_empty())
	assert(game.world.portal_active)
	print("boss ok — hp %d -> dead, portal awake, score=%d" % [hp0, GameState.score])
	print("SMOKE TEST COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
