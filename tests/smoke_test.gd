extends Node
## Headless smoke test: godot --headless tests/smoke_test.tscn
## Boots the real game scene, forces the briefing->launch flow, then steps the
## simulation with a fixed delta while holding the fire action — exercising flight,
## wall bounce, chunk streaming, enemies, shots, heat/overheat, and arena locks.


func _ready() -> void:
	_run()


func _run() -> void:
	# PathGen unit pass over all five levels first
	for i in 5:
		var level: LevelDef = load("res://resources/levels/level_%d.tres" % (i + 1))
		var path := PathGen.new()
		path.generate(level.rings, level.level_seed, level.spawn_arena)
		assert(path.rings.size() == level.rings)
		var locked := 0
		var final_count := 0
		for arena in path.arenas:
			if arena.is_final:
				final_count += 1
			elif arena.door_ring >= 0:
				locked += 1
				assert(not arena.spawn_rings.is_empty())
		assert(final_count == 1)
		print("L%d: rings=%d arenas=%d locked=%d" % [
			i + 1, path.rings.size(), path.arenas.size(), locked])
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	print("boot ok — state=%d" % game.state)
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
	print("SMOKE TEST COMPLETE")
	get_tree().quit()
