extends Node
## Headless soak run (v4b): godot --headless tests/soak_probe.tscn
## Flies the whole campaign, sector 1 to 9, on the rail in god mode with fire held.
## Every so often it clears the regular enemies near the ship (so bulkheads open and
## the run moves on), and it walks each boss down through its phases. It asserts:
##   - every enemy type in EnemyManager.TYPES spawned somewhere in the campaign,
##   - every boss reached phase 3 and died,
##   - every mini-boss (v4b) woke, reached phase 2 and died, and no boss_killed came of it,
##   - every sector completed, ending in victory,
## and prints each sector's census and worst step. Seeded, so a run is repeatable.
## Restores records/settings/checkpoint on exit, like the other probes.

const SOAK_SEED := 4040
const MAX_STEPS := 60 * 300       # per sector: five minutes of flight is a stuck run
const CLEAR_EVERY := 45           # steps between clears of the regular enemies...
const CLEAR_R := 45.0             # ...within this far of the ship
const BOSS_HIT_EVERY := 60        # steps between the soak's hits on an engaged boss
const BOSS_HIT := 0.12            # each takes this share of its max HP


func _ready() -> void:
	_run()


func _run() -> void:
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg", "user://checkpoint.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	seed(SOAK_SEED)
	GameState.reset_run()
	GameState.unlocked_level = 8
	GameState.level_index = 0
	GameState.score = 0
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
	var dt := 1.0 / 60.0
	var completed := 0
	for li in game.levels.size():
		GameState.level_index = li
		game._show_briefing()
		for i in 3:
			await get_tree().process_frame
		game._on_launch()
		assert(game.state == game.State.PLAYING)
		var types_here := {}
		var worst_us := 0
		var steps := 0
		Input.action_press("fire")
		for f in MAX_STEPS:
			GameState.shields = 100.0
			GameState.is_dead = false
			# steer for the centreline a few rings ahead, as attract mode does, so a drift
			# off-centre always closes and the ship meets the exit portal square on
			var ahead: Vector3 = game.path.rings[mini(game.player.ring_idx + 3,
				game.path.main_ring_count - 1)].p
			var to: Vector3 = (ahead - game.player.position).normalized()
			game.player.yaw = atan2(-to.x, -to.z)
			game.player.pitch = clampf(asin(clampf(to.y, -1.0, 1.0)), -0.6, 0.6)
			if f % CLEAR_EVERY == 0:
				for k in range(em.enemies.size() - 1, -1, -1):
					var e: Dictionary = em.enemies[k]
					if not e.get("is_boss", false) \
							and e.node.position.distance_to(game.player.position) < CLEAR_R:
						em.hit_enemy(k, 999)
			# (a mini-boss only once it has woken in its room)
			if em.boss_visible() and f % BOSS_HIT_EVERY == 0 \
					and em.boss.node.position.distance_to(game.player.position) \
						< EnemyManager.BOSS_ENGAGE:
				em.hit_enemy(em.enemies.find(em.boss), maxi(1, int(em.boss.max_hp * BOSS_HIT)))
			var t0 := Time.get_ticks_usec()
			game._process(dt)
			worst_us = maxi(worst_us, Time.get_ticks_usec() - t0)
			steps += 1
			for e in em.enemies:
				types_here[e.type if e.has("type") else e.get("model", "boss")] = true
			if game.state != game.State.PLAYING:
				break
		Input.action_release("fire")
		var done: bool = game.state == game.State.LEVEL_CLEAR or game.state == game.State.VICTORY
		var census := types_here.keys()
		census.sort()
		print("[soak] L%d %s: %s after %d steps (%.0f s), worst step %.1f ms, ring %d/%d · %s" % [
			li + 1, game.levels[li].kind, "CLEAR" if done else "STUCK state=%d" % game.state,
			steps, steps * dt, worst_us / 1000.0, game.player.ring_idx, game.path.main_ring_count,
			", ".join(census)])
		assert(done)
		completed += 1
		seen.merge(types_here)
	var missing: Array = []
	for id in EnemyManager.TYPES:
		if not seen.has(id):
			missing.append(id)
	print("[soak] types never spawned: %s" % (str(missing) if not missing.is_empty() else "none"))
	assert(missing.is_empty())
	var minis := 0
	for li in game.levels.size():
		var lv: LevelDef = game.levels[li]
		var got: Array = phases.get(li, [])
		if lv.kind == "boss":
			print("[soak] L%d %s phases %s" % [li + 1, lv.boss_name, str(got)])
			assert(got.has(2) and got.has(3))
		elif lv.miniboss_model != "":
			print("[soak] L%d mini-boss %s phases %s" % [li + 1, lv.miniboss_name, str(got)])
			assert(got == [2])
			minis += 1
	assert(boss_deaths[0] == 3 and mini_deaths[0] == minis and minis == 3)
	assert(completed == game.levels.size())
	assert(game.state == game.State.VICTORY)
	print("SOAK PROBE COMPLETE — %d sectors, %d types, %d bosses and %d mini-bosses down" % [
		completed, seen.size(), boss_deaths[0], mini_deaths[0]])
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
