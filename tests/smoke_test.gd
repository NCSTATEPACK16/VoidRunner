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
	# pin the campaign start to L1: game._ready() loads records.cfg, and the start
	# screen pre-selects the furthest unlocked sector — on a machine with progress
	# that would launch a later (even boss) level and break the L1 asserts below
	GameState.unlocked_level = 0
	game.overlays._sector = 0
	game._on_launch()   # MENU -> BRIEFING
	# V2.1: the briefing pump must finish the whole finite level before launch
	for f in 20:
		game._process(1.0 / 60.0)
	assert(game.world.is_prebuilt())
	game._on_launch()   # BRIEFING -> PLAYING
	await get_tree().process_frame
	assert(game.state == game.State.PLAYING)
	var dt := 1.0 / 60.0
	var built0: int = game.world._built_up_to
	# V2.1 draw window: chunks far past the fog stay resident but invisible
	for f in 3:
		game._process(dt)
	var all_far_hidden := true
	var near_visible := false
	for c in game.world._chunks:
		if c.start > game.player.ring_idx + WorldBuilder.VIS_AHEAD:
			all_far_hidden = all_far_hidden and not c.node.visible
		elif c.end >= game.player.ring_idx:
			near_visible = near_visible or c.node.visible
	assert(all_far_hidden and near_visible)
	print("prebuild ok — %d rings built at briefing, draw window active" % built0)
	# --- K3: L1 has fuel cells (secondary objective) but no crushers ---
	assert(GameState.level_props_total > 0)
	assert(game.prop_mgr.props.size() == GameState.level_props_total)
	assert(game.hazard_mgr._traps.is_empty())
	game.prop_mgr.damage_prop(0, 99)
	for f in 30:
		game._process(dt)
	assert(GameState.level_props == 1)   # cell exploded and was counted
	print("props ok — %d cells placed, detonation counted" % GameState.level_props_total)
	# --- K4: dodge roll — spends energy, grants brief i-frames, shifts laterally ---
	var ring0: Dictionary = game.path.rings[game.player.ring_idx]
	var lat0: float = (game.player.position - ring0.p as Vector3).dot(ring0.r)
	var energy0: float = GameState.energy
	game.player._try_dodge(1.0)
	assert(game.player.iframes_t > 0.0)
	assert(GameState.energy <= energy0 - PlayerShip.DODGE_COST + 0.01)
	var sh0: float = GameState.shields
	game.player.take_damage(10.0, "TEST SHOT")
	assert(GameState.shields == sh0)   # i-frames absorb non-wall damage
	for f in 20:
		game._process(dt)
	var ring1: Dictionary = game.path.rings[game.player.ring_idx]
	var lat1: float = (game.player.position - ring1.p as Vector3).dot(ring1.r)
	assert(lat1 - lat0 > 3.0)          # visibly displaced to the roll side
	assert(game.player.dodge_cd > 0.0)
	print("dodge ok — lat %.1f -> %.1f, energy %.0f -> %.0f" % [
		lat0, lat1, energy0, GameState.energy])
	# --- V2.0 secrets: phantom panel placed, brushing it reveals the cache ---
	assert(GameState.level_secrets_total >= 1)
	var sec: Dictionary = game._secrets[0]
	assert(is_instance_valid(sec.node))
	var sring: Dictionary = game.path.rings[sec.ring]
	game.player.ring_idx = sec.ring
	game.player.position = sring.p + sring.r * (sec.side * (sring.hw - 1.7))
	var score_before: int = GameState.score
	var pickups_before: int = game.pickup_mgr._pickups.size()
	game._update_secrets()
	assert(sec.found)
	assert(GameState.level_secrets == 1)
	assert(GameState.score == score_before + 250)
	assert(game.pickup_mgr._pickups.size() > pickups_before)   # the cache spilled
	game._update_secrets()   # re-entering the spot must not double-count
	assert(GameState.level_secrets == 1)
	print("secrets ok — %d placed on L1, discovery pays and spills a cache" %
		GameState.level_secrets_total)
	# put the probe back at the start so the flight loop runs its usual course
	game.player.reset_to_start()
	Input.action_press("fire")
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
	# V2.1: a finite level never builds a chunk mid-flight (the web-stall cause),
	# and the spawn cursor keeps tunnel enemies coming past the old ~25-ring wall
	assert(game.world._built_up_to == built0)
	assert(peak_enemies > 0)
	print("end state=%d ring=%d/%d shields=%.0f score=%d peak_enemies=%d overheat=%s" % [
		game.state, game.player.ring_idx, game.path.rings.size(),
		GameState.shields, GameState.score, peak_enemies, overheated_seen])
	# --- V2.1 pooling: hidden free nodes, per-class caps hold under a 50-boom burst,
	# and every effect returns to the pool (no node is ever freed mid-play) ---
	for n in game.shot_mgr._pool_free:
		assert(not n.visible)
	for b in 50:
		game.shot_mgr.spawn_explosion(game.player.position + Vector3(b, 0, 0), b % 2 == 0)
	assert(game.shot_mgr._pool_total <= ShotManager.POOL_HARD_CAP)
	assert(game.shot_mgr._explosions.size() <= ShotManager.EXPLOSION_CAP)
	assert(game.shot_mgr._sparks.size() <= ShotManager.SPARK_CAP)
	assert(game.shot_mgr._eshots.size() <= ShotManager.ESHOT_CAP)
	for f in 90:   # explosions/sparks live 0.6 s — let the burst drain back
		game.shot_mgr.update_shots(dt)
	assert(game.shot_mgr._explosions.is_empty() and game.shot_mgr._sparks.is_empty())
	print("pool ok — total=%d free=%d after 50-boom burst" % [
		game.shot_mgr._pool_total, game.shot_mgr._pool_free.size()])
	# --- K3: L2 places crushers in plain tunnel, clear of arenas and doors ---
	GameState.reset_run()
	GameState.level_index = 1
	game._launch_level()
	await get_tree().process_frame
	assert(game.hazard_mgr._traps.size() >= 1)
	for t in game.hazard_mgr._traps:
		assert(game.path.rings[t.ring].arena_id < 0)
	for f in 200:   # cycle the pistons through a full period
		game._process(dt)
	print("hazards ok — %d crushers on L2, cycling" % game.hazard_mgr._traps.size())
	# --- V2.0 wall turrets: fixed anchor, fires from the wall, dies to damage ---
	var t0: int = game.enemy_mgr.enemies.size()
	game.enemy_mgr.spawn(game.player.ring_idx + 4, -1, "turret")
	assert(game.enemy_mgr.enemies.size() == t0 + 1)
	var tur: Dictionary = game.enemy_mgr.enemies.back()
	assert(tur.type == "turret" and not tur.seeker)   # L2: no seekers yet
	var tpos: Vector3 = tur.node.position
	var fired := false
	for f in 60 * 6:   # max fire_t is ~3.5 s — 6 s guarantees at least one shot
		game._process(dt)
		GameState.shields = 100.0
		if tur.fire_t < 1.4:   # cadence timer moved => the turret is engaging
			fired = true
	assert(is_instance_valid(tur.node) and tur.node.position == tpos)  # never moved
	assert(fired)
	var ti: int = game.enemy_mgr.enemies.find(tur)
	assert(ti >= 0)
	game.enemy_mgr.hit_enemy(ti, 999)
	assert(game.enemy_mgr.enemies.find(tur) == -1)   # dead and removed
	print("turret ok — wall-anchored, fireable, killable")
	# --- Phase J: boss level — spawn, dormant portal, kill wakes the exit ring ---
	GameState.reset_run()
	GameState.level_index = 2   # L3 · DOCK SENTINEL
	game._launch_level()
	await get_tree().process_frame
	assert(not game.enemy_mgr.boss.is_empty())
	assert(not game.world.portal_active)
	assert(GameState.level_props_total == 0)   # K3: boss rooms stay clean
	assert(game.hazard_mgr._traps.is_empty())
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
	# --- K5: Void Gauntlet — endless path grows, arenas stream in, chunks stay bounded ---
	GameState.reset_run()
	seed(20260711)          # pin the run layout — the gauntlet seed comes from randi()
	game._on_gauntlet()     # MENU-independent: flips mode + builds behind a briefing
	game._launch_level()
	await get_tree().process_frame
	assert(game.path.is_endless)
	assert(GameState.gauntlet_mode)
	assert(not game.world.portal_active)   # no exit gate in the gauntlet
	var rings_initial: int = game.path.rings.size()
	for f in 60 * 90:   # 1.5 simulated minutes ≈ 135 rings of travel
		GameState.shields = 100.0          # the probe flies, it doesn't fight fair
		# rail-steer along the tunnel: a non-steering probe can grind to a stop
		# against a hard 90° corner and stall the whole run
		var pd: Vector3 = game.path.rings[mini(game.player.ring_idx + 2,
			game.path.rings.size() - 1)].d
		game.player.yaw = atan2(-pd.x, -pd.z)
		game.player.pitch = clampf(asin(pd.y), -0.6, 0.6)
		if f % 240 == 0:                   # clear arena stands so bulkheads open
			game.enemy_mgr.splash_damage(game.player.position, 200.0, 999)
		game._process(dt)
	assert(game.path.rings.size() > rings_initial)   # extend_to() grew the path
	assert(game.path.arenas.size() >= 2)             # stands were discovered…
	assert(game.world._doors.size() == game.path.arenas.size())  # …and got doors
	assert(game.world._chunks.size() <= 12)          # streaming stays bounded
	# V2.1: discovery side effects drain within frames — never a same-frame burst
	assert(game._door_queue.is_empty() and game._spawn_queue.is_empty())
	var gdist := int(game.player.ring_idx * PathGen.SEG)
	assert(gdist > 800)                              # bulkheads never soft-locked the run
	GameState.record_gauntlet(gdist)
	assert(GameState.gauntlet_best_dist >= gdist)
	print("gauntlet ok — dist=%dm rings=%d arenas=%d tier=%d" % [
		gdist, game.path.rings.size(), game.path.arenas.size(), game._gauntlet_tier])
	# --- K6: opt-in gamepad — joy bindings appear and disappear with the toggle ---
	var is_joy := func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton or e is InputEventJoypadMotion
	assert(not Array(InputMap.action_get_events("fire")).any(is_joy))
	GameState.gamepad_enabled = true
	GameState.apply_settings()
	assert(Array(InputMap.action_get_events("fire")).any(is_joy))
	assert(Array(InputMap.action_get_events("pause_game")).any(is_joy))
	GameState.gamepad_enabled = false
	GameState.apply_settings()
	assert(not Array(InputMap.action_get_events("fire")).any(is_joy))
	print("gamepad ok — joy bindings toggle with the setting")
	# --- V2.0 plasma bomb: P is bomb, Space still fires, Enter pauses ---
	var has_key := func(action: String, key: Key) -> bool:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and ev.physical_keycode == key:
				return true
		return false
	assert(has_key.call("fire", KEY_SPACE))
	assert(has_key.call("plasma_bomb", KEY_P))
	assert(has_key.call("pause_game", KEY_ENTER))
	assert(not has_key.call("pause_game", KEY_P))
	# room-clear: bombs kill every enemy in range and the counter decrements
	GameState.plasma_bombs = 2
	for s in 3:
		game.enemy_mgr.spawn(game.player.ring_idx, -1, "drone")
	game._fire_plasma_bomb()
	assert(GameState.plasma_bombs == 1)
	var near := 0
	for e in game.enemy_mgr.enemies:
		if e.node.position.distance_squared_to(game.player.position) < 120.0 * 120.0:
			near += 1
	assert(near == 0)
	GameState.plasma_bombs = 0
	game._fire_plasma_bomb()   # empty rack: no crash, stays at zero
	assert(GameState.plasma_bombs == 0)
	print("plasma bomb ok — room cleared, counter %d, keys remapped" % GameState.plasma_bombs)
	print("SMOKE TEST COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
