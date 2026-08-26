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
	print("smoke: _run entered")
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
	# --- V2.2 L1a: gib fragment textures ---
	var gframes: Array = SpriteGen.gib_frames()
	assert(gframes.size() == 4)
	for gf in gframes:
		assert(gf is Texture2D and gf.get_width() >= 8)
	assert(SpriteGen.gib_frames()[0] == gframes[0])   # cached, not re-rendered
	print("gib frames ok — %d shapes" % gframes.size())
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
	# --- V2.2 L4a: Tab automap — explored polyline built, opening pauses, closing resumes ---
	game.automap.note_ring(30)
	game.automap.open()
	assert(get_tree().paused and game.automap.is_open())
	assert(game.automap._pts.size() >= 30)   # explored rings 0..30(+lookahead) drawn
	game.automap.close()
	assert(not get_tree().paused and not game.automap.is_open())
	print("automap ok — %d-ring explored polyline, pauses + resumes" % game.automap._pts.size())
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
	# --- V2.2 L1b: gibs — burst past the cap, ricochet sim, full drain ---
	var gm: GibManager = game.gib_mgr
	gm.burst(game.player.position + game.player.forward() * 10.0, Vector3(4, 2, -6),
		game.player.ring_idx, 60, Color.RED)   # 60 asked > 48 cap
	assert(gm.active_count() <= 48)
	assert(gm.active_count() > 0)
	for f in 400:   # ~4 s of physics — every chunk must expire and free its slot
		gm._sim(0.01)
	assert(gm.active_count() == 0)
	print("gibs ok — cap held, pool drained")
	# --- V2.2 L1c: hit-stop — crushes time, cooldown gates spam, real-time restore ---
	gm._stop_cooldown_ms = 0   # earlier live-fire kills may have armed the cooldown
	gm.hit_stop(50)
	assert(Engine.time_scale < 0.5)
	gm._stop_cooldown_ms = Time.get_ticks_msec() + 10000   # pin: cooldown live regardless of run speed
	var restore_before: int = gm._stop_restore_ms
	gm.hit_stop(200)   # lands inside the cooldown: must be ignored
	assert(gm._stop_restore_ms == restore_before)
	gm._stop_cooldown_ms = 0
	gm._stop_restore_ms = Time.get_ticks_msec() - 1   # force the restore due now
	gm._process(0.016)
	assert(is_equal_approx(Engine.time_scale, 1.0))
	print("hit-stop ok — crush + cooldown + restore")
	# --- V2.2 L1d: camera kick + shake respect the SCREEN SHAKE setting ---
	GameState.screen_shake = true
	game.player.shake = 0.0
	game.player.add_shake(0.5)
	assert(game.player.shake > 0.0)
	GameState.screen_shake = false
	game.player.shake = 0.0
	game.player.add_shake(0.5)
	assert(game.player.shake == 0.0)
	game.player._kick_pitch = 0.0   # clear residual decay from the earlier live-fire sim
	game.player.add_kick(1)
	assert(game.player._kick_pitch == 0.0)   # kick gated by the setting too
	GameState.screen_shake = true
	game.player.add_kick(1)
	assert(game.player._kick_pitch > 0.0)
	game.player._kick_pitch = 0.0
	print("shake ok — kick + shake behind SCREEN SHAKE setting")
	# --- V2.2 L1e: hit feedback — kill tick + directional damage arcs ---
	game.hud.flash_kill_tick()
	assert(game.hud._kill_tick_t > 0.0)   # kill tick armed
	game.hud.show_damage_from(game.player.position + Vector3(30, 0, 0))
	assert(game.hud._dmg_arcs.size() > 0)   # damage arc registered
	print("feedback ok — kill tick + damage arcs")
	# --- V2.2 L2a: three phase-aligned music mixes on synced players ---
	var mix_a: AudioStream = MusicGen.render_loop(0)
	var mix_b: AudioStream = MusicGen.render_loop(2)
	assert(is_equal_approx(mix_a.get_length(), mix_b.get_length()))   # phase-aligned
	assert(AudioSys._music.size() == 3)   # three synced players
	print("mixes ok — 3 phase-aligned music beds")
	# --- V2.2 L2b: combat-intensity engine — boss forces frenzy, calm decays ---
	GameState.boss_active = true
	AudioSys._update_intensity(0.1, game.player.position)
	assert(AudioSys._intensity >= 2.0)   # boss forces FRENZY
	GameState.boss_active = false
	GameState.arena_locked = false
	AudioSys._ramp_floor = 0.0
	AudioSys._intensity = 2.0
	for _calm_step in 100:
		AudioSys._update_intensity(0.1, Vector3(9999, 0, 9999))   # 10 s of calm
	assert(AudioSys._intensity < 1.0)   # decays once the calm window lapses
	print("intensity ok — frenzy on boss, decay after calm")
	# --- V2.2 L2c: style meter grades the combo streak ---
	GameState.reset_level_stats()
	for _sk in 6:
		GameState.register_kill(10)
	assert(GameState.style_grade() >= 2)   # 6-kill streak = STELLAR
	assert(GameState.peak_style >= 2)      # peak recorded for the tally
	GameState.reset_level_stats()
	assert(GameState.peak_style == 0)      # peak is per-level
	print("style ok — grades + peak")
	# --- V2.2 L3a: salvage economy + upgrade accessors ---
	GameState.reset_run()
	GameState.salvage_run = 50
	GameState.salvage_bank = 30
	assert(GameState.salvage_total() == 80)
	assert(GameState.spend_salvage(60) and GameState.salvage_run == 0 \
		and GameState.salvage_bank == 20)   # spend drains run first, then bank
	assert(not GameState.spend_salvage(999))   # can't overdraw
	GameState.weapon_marks[0] = 2
	assert(is_equal_approx(GameState.weapon_mult(0, "damage"), 1.75))   # NEUTRON MK III
	assert(GameState.weapon_add(1, "pellets") == 0)   # SCATTER still MK I
	GameState.ship_ranks.shield = 1
	assert(is_equal_approx(GameState.max_shields(), 120.0))   # shield cap rank 1
	GameState.save_records()
	GameState.ship_ranks.shield = 0
	GameState.load_records()
	assert(GameState.ship_ranks.shield == 1)   # ship rank persists
	GameState.reset_run()
	assert(GameState.weapon_marks[0] == 0)     # marks are per-run
	GameState.ship_ranks.shield = 0            # scrub test state for later sections
	GameState.salvage_bank = 0
	print("economy ok — salvage + marks + ranks")
	# --- V2.2 L3b: salvage drops ride the pickup pipeline ---
	GameState.reset_level_stats()
	game.pickup_mgr.clear_all()
	var pre_enemies: int = game.enemy_mgr.enemies.size()
	game.enemy_mgr.spawn(game.player.ring_idx + 3, -1, "hulk")
	assert(game.enemy_mgr.enemies.size() == pre_enemies + 1)
	game.enemy_mgr._kill(game.enemy_mgr.enemies.size() - 1, true)   # scored hulk kill
	var salv_pick: Dictionary = {}
	for pk in game.pickup_mgr._pickups:
		if pk.kind == "salvage":
			salv_pick = pk
	assert(not salv_pick.is_empty())   # hulk ALWAYS drops salvage
	assert(salv_pick.value == 15)
	game.player.position = salv_pick.node.position   # stand on it
	game.pickup_mgr.update_pickups(0.016)
	assert(GameState.salvage_run == 15)   # collected through the manager path
	print("salvage ok — hulk drop collected for 15")
	# --- V2.2 L3c: upgrade accessors reach every consumption site ---
	var base_pellets: int = game.shot_mgr.pellet_count(1)
	GameState.weapon_marks[1] = 2      # SCATTER MK III
	assert(game.shot_mgr.pellet_count(1) == base_pellets + 2)   # +2 pellets
	GameState.weapon_marks[1] = 0
	GameState.ship_ranks.hull = 1
	assert(is_equal_approx(game.player.wall_damage_mult(), 0.7))   # hull plating
	GameState.ship_ranks.hull = 0
	print("apply ok — marks + ranks reach the consumption sites")
	# --- V2.2 L3d: Upgrade Bay — buy weapon marks + ship ranks, bank at level end ---
	GameState.reset_run()
	GameState.salvage_run = 0
	GameState.salvage_bank = 500
	GameState.ship_ranks.shield = 0
	GameState.ship_ranks.magnet = 0
	assert(game.overlays.bay_buy_weapon(0))                       # MK I -> II, 60
	assert(GameState.weapon_marks[0] == 1 and GameState.salvage_total() == 440)
	assert(game.overlays.bay_buy_weapon(0))                       # MK II -> III, 140
	assert(GameState.weapon_marks[0] == 2 and GameState.salvage_total() == 300)
	assert(not game.overlays.bay_buy_weapon(0))                   # maxed — no charge
	assert(GameState.salvage_total() == 300)
	assert(game.overlays.bay_buy_ship("shield"))                 # rank 0 -> 1, 120
	assert(GameState.ship_ranks.shield == 1 and GameState.salvage_total() == 180)
	assert(game.overlays.bay_buy_ship("magnet"))                 # single rank, 180
	assert(GameState.ship_ranks.magnet == 1 and GameState.salvage_total() == 0)
	assert(not game.overlays.bay_buy_ship("magnet"))             # already maxed
	assert(not game.overlays.bay_buy_ship("shield"))             # can't afford rank 2 (260)
	# banking: the level's unbanked haul folds into the persistent bank
	GameState.reset_run()
	GameState.salvage_run = 45
	GameState.bank_salvage()
	assert(GameState.salvage_run == 0 and GameState.salvage_bank == 45)
	GameState.reset_run()
	GameState.salvage_bank = 0            # scrub bank + ranks for later sections
	GameState.ship_ranks.shield = 0
	GameState.ship_ranks.magnet = 0
	print("bay ok — marks + ranks bought, banking works")
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
	GameState.weapon_marks = [2, 2, 2, 2]   # a prior campaign's marks must not leak in
	seed(20260711)          # pin the run layout — the gauntlet seed comes from randi()
	game._on_gauntlet()     # MENU-independent: flips mode + builds behind a briefing
	assert(GameState.weapon_marks == [0, 0, 0, 0])   # L3e: gauntlet resets to MK I
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
	# L3e: the gauntlet run's salvage haul banks when the run ends (death path)
	GameState.salvage_bank = 0
	GameState.salvage_run = 20
	game._on_player_died()
	assert(GameState.salvage_bank == 20 and GameState.salvage_run == 0)
	GameState.salvage_bank = 0   # scrub for later sections
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
	# --- V2.2 L5a: PathGen dead-end spurs — appended, tagged, main path untouched ---
	var spg := PathGen.new()
	spg.generate(220, 424242, 0.18, false, false)
	var main_len: int = spg.rings.size()
	var main_end_p: Vector3 = spg.rings[main_len - 1].p
	spg.add_spurs(2)
	assert(spg.main_ring_count == main_len)              # main-path/spur boundary marked
	assert(spg.rings.size() > main_len)                  # spur rings appended past it
	assert(spg.rings[main_len - 1].p == main_end_p)      # main path byte-identical (cursor restored)
	assert(spg.spurs.size() == 2)
	for sp in spg.spurs:
		assert(sp.start > sp.entry and sp.end >= sp.start + 11)   # appended, >= 12 rings
		assert(spg.rings[sp.start].get("spur", -1) == sp.id)      # spur rings carry the id
		assert(spg.rings[sp.cache].hw > 10.0)                     # wide cache chamber
		assert(spg.rings[sp.entry].arena_id >= 0)                 # branches off a real arena
	var bpg := PathGen.new()
	bpg.generate(120, 7, 0.2, true, false)   # boss level
	bpg.add_spurs(2)
	assert(bpg.spurs.is_empty())             # boss levels never spur
	print("spurs ok — %d spurs appended, main path intact" % spg.spurs.size())
	# --- V2.2 L5b: spur hatch + ring-snap — crossing the mouth swaps ring index space ---
	game._gauntlet = false          # the gauntlet section above left this set
	GameState.gauntlet_mode = false
	GameState.reset_run()
	GameState.level_index = 4        # L5 · HIVE TRENCHES (spur_count = 2)
	game._launch_level()
	await get_tree().process_frame
	assert(not game.path.spurs.is_empty())                         # game wired add_spurs
	assert(game.spur_mgr._spurs.size() == game.path.spurs.size())  # a hatch per spur
	var msp: Dictionary = game.path.spurs[0]
	var mouth: Vector3 = game.path.rings[msp.start].p
	var toward_arena: Vector3 = (game.path.rings[msp.entry].p - mouth).normalized()
	# ENTER: tracked as the arena ring, just inside the mouth -> snap into the spur
	game.player.ring_idx = msp.entry
	game.player.position = mouth + toward_arena * 5.0
	game.spur_mgr.update(0.016)
	assert(game.player.ring_idx == msp.start)
	# reach the cache chamber: re-arms the snap and pays the +300/+25 bundle once
	var cache_score_before: int = GameState.score
	game.player.position = game.path.rings[msp.cache].p
	game.spur_mgr.update(0.016)
	assert(game.spur_mgr.caches_found >= 1)
	assert(GameState.score >= cache_score_before + 300)
	# EXIT: tracked as a spur ring, back at the mouth -> snap to the arena
	game.player.ring_idx = msp.cache
	game.player.position = mouth + toward_arena * 5.0
	game.spur_mgr.update(0.016)
	assert(game.player.ring_idx == msp.entry)
	print("spur snap ok — mouth crossing swaps ring index both ways; cache paid")
	# --- V2.2 L5c: spur guards spawned + contained; automap reveals seen spurs ---
	var guard_rings: Array[int] = []
	for e in game.enemy_mgr.enemies:
		if e.ring >= msp.start and e.ring <= msp.end:
			guard_rings.append(e.ring)
	assert(not guard_rings.is_empty())       # >=1 guard spawned inside spur 0
	game.player.ring_idx = msp.start + 2     # park mid-spur so guards track locally
	game.player.position = game.path.rings[msp.start + 2].p
	for _gstep in 100:
		game.enemy_mgr.update_enemies(0.016)
	var guard_contained := false
	for e in game.enemy_mgr.enemies:
		if e.ring >= msp.start and e.ring <= msp.end:
			guard_contained = true
	assert(guard_contained)                  # clamp_to_ring keeps guards in the spur
	game.automap.note_ring(msp.start + 2)    # seeing a spur ring reveals its branch
	game.automap._rebuild()
	assert(game.automap._spur_runs.size() >= 1)
	assert(game.automap._spur_runs[0].size() >= 3)
	print("spur guards+map ok — %d guard(s) contained; automap draws the branch" \
		% guard_rings.size())
	# --- V2.2 L5d: end-to-end spur pass on L2 — fly in, grab the cache, fly out ---
	GameState.reset_run()
	GameState.level_index = 1        # L2 · spur_count = 1
	game._launch_level()
	await get_tree().process_frame
	assert(game.path.spurs.size() == 1)
	var esp: Dictionary = game.path.spurs[0]
	var e_mouth: Vector3 = game.path.rings[esp.start].p
	var e_phase := 0                 # 0 fly-in, 1 to mouth, 2 to cache, 3 return + clear
	var prev_ring: int = game.player.ring_idx
	var e_done := false
	for f in 60 * 240:               # hard ceiling: 4 sim-minutes
		GameState.shields = 100.0    # the probe flies, it doesn't fight fair
		if e_phase == 0 and game.player.ring_idx >= esp.entry - 6:
			e_phase = 1
		if e_phase == 0:             # rail-steer the main tunnel (gauntlet idiom)
			var pd: Vector3 = game.path.rings[mini(game.player.ring_idx + 2, esp.entry)].d
			game.player.yaw = atan2(-pd.x, -pd.z)
			game.player.pitch = clampf(asin(pd.y), -0.6, 0.6)
		else:                        # position-steer at the current waypoint
			var e_target := e_mouth
			if e_phase == 1 and game.player.ring_idx >= esp.start:
				e_phase = 2          # mouth snap landed — we are in spur index space
			if e_phase == 2:
				e_target = game.path.rings[mini(
					maxi(game.player.ring_idx, esp.start) + 2, esp.cache)].p
				if game.spur_mgr.caches_found >= 1:
					e_phase = 3
			elif e_phase == 3 and game.player.ring_idx < esp.start:
				e_target = game.path.rings[esp.entry].p    # snapped back — clear the mouth
				if game.player.position.distance_squared_to(e_mouth) > 400.0:
					e_done = true
			var dirv: Vector3 = (e_target - game.player.position).normalized()
			game.player.yaw = atan2(-dirv.x, -dirv.z)
			game.player.pitch = clampf(asin(dirv.y), -0.9, 0.9)
		if f % 240 == 0:             # clear arena stands so bulkheads open
			game.enemy_mgr.splash_damage(game.player.position, 200.0, 999)
		game._process(dt)
		# ring continuity: only the mouth snap may leap index space
		if absi(game.player.ring_idx - prev_ring) > 30:
			assert(game.player.position.distance_squared_to(e_mouth) < 200.0)
		prev_ring = game.player.ring_idx
		if e_done:
			break
	assert(e_done)                   # full in-cache-out pass completed
	assert(game.spur_mgr.caches_found == 1)
	game.overlays.set_level_clear("L2", 0, 0, "L3", 0, 0, 0.0, "C", false, 0, 0, 0, 0,
		game.spur_mgr.caches_found, game.path.spurs.size())
	var clear_body: String = \
		(game.overlays._panels.level_clear.get_node("Body") as Label).text
	assert("CACHES 1/1" in clear_body)
	print("spur e2e ok — flew in, cached, flew out; tally CACHES 1/1")
	# --- V2.2 story pass: lore coverage + the briefing bands never overlap ---
	for lidx in 9:
		assert(Lore.story(lidx).length() > 20)            # every sector has a story
		assert(Lore.load_lines(lidx).size() >= 3)         # and overlay transmissions
	assert(Lore.story(-1).length() > 20)                  # gauntlet variant
	assert(Lore.load_lines(-1).size() >= 3)
	GameState.gauntlet_mode = false
	GameState.level_index = 4          # spur level: worst-case 3-line objective
	game.overlays.set_briefing(game.levels[4])
	await get_tree().process_frame
	var lore_p: Control = game.overlays._panels.briefing
	var lore_s: Label = lore_p.get_node("Story")
	var lore_o: Label = lore_p.get_node("Objective")
	var lore_b: Label = lore_p.get_node("Body")
	assert(lore_s.get_line_count() <= 3)                  # story fits its band
	assert(lore_b.get_line_count() <= 3)                  # tactical body fits its band
	assert(lore_o.text.count("\n") <= 2)                  # objective is at most 3 lines
	assert(lore_s.position.y + lore_s.size.y * lore_s.scale.y <= lore_o.position.y)
	assert(lore_o.position.y + 3 * 11.0 <= lore_b.position.y)
	assert(lore_b.position.y + lore_b.size.y * lore_b.scale.y <= 164.0)   # above buttons
	print("lore ok — 9+gauntlet stories + load lines; briefing bands don't overlap")
	# --- M1/M2 beta readiness: safety notice, comfort settings, build stamp ---
	# every new setting round-trips through settings.cfg
	GameState.reduce_flashing = true
	GameState.reduce_roll = true
	GameState.invert_y = true
	GameState.view_fov = 92.0
	GameState.seen_warning = true
	GameState.apply_settings()
	GameState.reduce_flashing = false
	GameState.reduce_roll = false
	GameState.invert_y = false
	GameState.view_fov = 78.0
	GameState.seen_warning = false
	GameState.load_settings()
	assert(GameState.reduce_flashing and GameState.reduce_roll and GameState.invert_y)
	assert(is_equal_approx(GameState.view_fov, 92.0))
	assert(GameState.seen_warning)
	# the settings panel exposes a control for every one of them
	var set_p: Control = game.overlays._panels.settings
	for k in ["volume", "sens", "fov", "dither", "amber", "gamepad", "shake",
			"reduce_flash", "reduce_roll", "invert_y", "dpad", "gyro"]:
		assert(game.overlays._settings_labels.has(k))
	# and none of its controls escapes the 320x200 design box
	for child in set_p.get_children():
		if child is Button or child is Label:
			var c := child as Control
			assert(c.position.x >= 0.0 and c.position.y >= 0.0)
			assert(c.position.y <= 190.0)
	# FOV clamps at both ends rather than running away
	for _i in 20:
		game.overlays._adjust_setting("fov", 1)
	assert(GameState.view_fov <= 100.0)
	for _i in 30:
		game.overlays._adjust_setting("fov", -1)
	assert(GameState.view_fov >= 60.0)
	# M1.2: reduce-flash suppresses the plasma white-out
	GameState.reduce_flashing = false
	game.hud.flash_white()
	var bright: float = game.hud._bomb_flash.color.a
	GameState.reduce_flashing = true
	game.hud.flash_white()
	assert(game.hud._bomb_flash.color.a < bright * 0.5)
	# ...and holds animated arena lights steady instead of strobing them
	game.world.animate(0.25)
	game.world.animate(0.25)
	for l in game.world._lights:
		assert(is_equal_approx(l.light.light_energy, l.energy))
	GameState.reduce_flashing = false
	# M2.2: invert-Y actually flips the pitch response
	game.player.pitch = 0.0
	GameState.invert_y = false
	game.player.apply_mouse_look(Vector2(0.0, 10.0))
	var normal_pitch: float = game.player.pitch
	game.player.pitch = 0.0
	GameState.invert_y = true
	game.player.apply_mouse_look(Vector2(0.0, 10.0))
	assert(signf(game.player.pitch) == -signf(normal_pitch))
	GameState.invert_y = false
	game.player.pitch = 0.0
	# M4c: touch d-pad toggle defaults off and can be flipped via the button
	assert(GameState.touch_dpad_enabled == false)   # default off, per D9
	var dpad_btn := game.overlays._settings_labels["dpad"] as Button
	dpad_btn.pressed.emit()
	assert(GameState.touch_dpad_enabled == true)
	dpad_btn.pressed.emit()
	assert(GameState.touch_dpad_enabled == false)
	# M4c: gyro fine-aim toggle defaults off and flips via the button, same
	# pattern as the D-pad toggle above.
	assert(GameState.gyro_aim_enabled == false)   # default off
	var gyro_btn := game.overlays._settings_labels["gyro"] as Button
	gyro_btn.pressed.emit()
	assert(GameState.gyro_aim_enabled == true)
	gyro_btn.pressed.emit()
	assert(GameState.gyro_aim_enabled == false)
	# Headless has no real gyroscope (Input.get_gyroscope() is always ZERO here),
	# so actual tilt response needs a real iOS/Android device (parked, like
	# M4a's Android check and M4b's touch feel). What IS verifiable here: the
	# real update_flight() code path runs without error both off and on, and is
	# a harmless no-op given a zero sensor reading. delta=0.0 isolates the gyro
	# term from every other per-frame effect (movement, energy, collision), so
	# yaw/pitch must come back exactly as they went in either way.
	assert(Input.get_gyroscope() == Vector3.ZERO)
	var gyro_yaw0: float = game.player.yaw
	var gyro_pitch0: float = game.player.pitch
	GameState.gyro_aim_enabled = false
	game.player.update_flight(0.0)
	assert(is_equal_approx(game.player.yaw, gyro_yaw0))
	assert(is_equal_approx(game.player.pitch, gyro_pitch0))
	GameState.gyro_aim_enabled = true
	game.player.update_flight(0.0)
	assert(is_equal_approx(game.player.yaw, gyro_yaw0))
	assert(is_equal_approx(game.player.pitch, gyro_pitch0))
	GameState.gyro_aim_enabled = false
	print("gyro ok — toggle round-trips; update_flight() path is inert with no real sensor")
	# M1.2: the warning panel exists and gates the start screen on a fresh profile
	assert(game.overlays._panels.has("warning"))
	GameState.seen_warning = false
	game.overlays.show_only("warning" if not GameState.seen_warning else "start")
	assert(game.overlays._panels.warning.visible)
	assert(not game.overlays._panels.start.visible)
	game.overlays._ack_warning()
	game.overlays.show_only("start")
	assert(GameState.seen_warning and game.overlays._panels.start.visible)
	# M1.4: a build stamp is present and non-placeholder-empty
	assert(BuildInfo.label().length() > 5)
	# M1.5: the sector arrows sit clear of the longest sector label. The label is a
	# 640-wide centred _line scaled 0.5, so its painted span is measured from the
	# text width, not the node's box.
	var arrows: Array[Button] = []
	for child in game.overlays._panels.start.get_children():
		if child is Button and (child as Button).text in ["<", ">"]:
			arrows.append(child as Button)
	assert(arrows.size() == 2)
	var longest := 0.0
	for lname in game.levels:
		var f: Font = game.overlays._sector_label.get_theme_default_font()
		var fs: int = game.overlays._sector_label.get_theme_font_size("font_size")
		var w: float = f.get_string_size("SECTOR: %s" % (lname as LevelDef).display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
		longest = maxf(longest, w)
	var label_left := 160.0 - longest * 0.5
	var label_right := 160.0 + longest * 0.5
	for a in arrows:
		var a_l: float = a.position.x
		var a_r: float = a.position.x + maxf(a.size.x, 8.0)
		assert(a_r <= label_left or a_l >= label_right)
	print("M1/M2 ok — settings round-trip, flash + roll + invert, stamp, arrows clear")
	# --- M3: feedback path + anonymous counters ---
	# the five questions are the single source shared by the form, the post and the
	# in-game prompt; drift between them makes answers incomparable
	assert(Feedback.QUESTIONS.size() == 5)
	for q in Feedback.QUESTIONS:
		assert((q as String).length() > 15)
	# counters never carry anything but an event name and a sector number
	assert(Feedback.EV_LOADED != "" and Feedback.EV_LEVEL_STARTED != "")
	assert(Feedback.EV_LEVEL_CLEARED != "" and Feedback.EV_FEEDBACK != "")
	# every call is inert off the web and inert unconfigured — no crash, no error
	Feedback.count(Feedback.EV_LOADED)
	Feedback.count_level(Feedback.EV_LEVEL_STARTED, 0)
	Feedback.open_form()
	# the F key exists and is bound
	assert(InputMap.has_action("feedback"))
	var f_bound := false
	for ev in InputMap.action_get_events("feedback"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F:
			f_bound = true
	assert(f_bound)
	# a button that does nothing is worse than no button: with no form configured
	# the feedback buttons must be absent from game-over and victory alike
	for panel_name in ["game_over", "victory"]:
		var fb := 0
		for child in (game.overlays._panels[panel_name] as Control).get_children():
			if child is Button and "FEEDBACK" in (child as Button).text:
				fb += 1
		assert(fb == (1 if Feedback.is_configured() else 0))
	# the configured layout is the one that ships, so assert it rather than the
	# empty one: with a form set, the help screen gains an F row and NOTHING may
	# land on the gamepad row or run off the 200 px panel
	var shipped_form: String = Feedback.FORM_URL   # restore the real value after
	Feedback.FORM_URL = "https://tally.so/r/SMOKE1"
	(game.overlays._panels.help as Control).queue_free()
	game.overlays._build_help()
	await get_tree().process_frame
	var help_p: Control = game.overlays._panels.help
	var pad_y: float = game.overlays._help_pad.position.y
	var rows: Array[float] = []
	for child in help_p.get_children():
		if child is Label or child is Button:
			var c := child as Control
			assert(c.position.y + 20.0 <= 200.0)          # nothing runs off the panel
			if child is Label and (child as Label).text.begins_with("F  send"):
				rows.append(c.position.y)
	assert(rows.size() == 1)                              # the F row exists exactly once
	assert(not is_equal_approx(rows[0], pad_y))           # and never sits on the gamepad row
	var fb_seen := 0
	Feedback.FORM_URL = ""
	help_p.queue_free()               # _build_help() makes a fresh panel each call
	game.overlays._build_help()
	await get_tree().process_frame
	for child in (game.overlays._panels.help as Control).get_children():
		if child is Label and (child as Label).text.begins_with("F  send"):
			fb_seen += 1
	assert(fb_seen == 0)                                  # and vanishes again when unset
	Feedback.FORM_URL = shipped_form
	(game.overlays._panels.help as Control).queue_free()
	game.overlays._build_help()
	await get_tree().process_frame
	print("M3 ok — 5 questions, 4 counters inert unconfigured, F bound, buttons gated")
	# --- M4b: touch layer — zone dispatch, floating stick, boost double-tap ---
	var touch := TouchControls.new()
	add_child(touch)
	touch.enable(game.player)
	await get_tree().process_frame
	# activation lifecycle: enable() turns it on; set_flight_active(false) must
	# release every held action so a pause mid-input can't leave something stuck
	assert(touch.active)
	assert(touch.visible)
	# Regression guard for the Task 3 canvas-unit/screen-pixel bug: every button
	# geometry constant in touch_controls.gd assumes get_visible_rect() is exactly
	# the 320x200 canvas. If project.godot's stretch/aspect ever changes, this
	# catches the whole layout reverting to the original bug, instead of the
	# fire-button-rect assertions below simply reading whatever the new numbers are.
	var vp := get_viewport().get_visible_rect()
	assert(vp.size == Vector2(320, 200))
	for btn in [touch._fire_btn, touch._bomb_btn, touch._weapon_btn]:
		assert(Rect2(Vector2.ZERO, Vector2(320, 200)).encloses(btn.get_global_rect()))
		assert(btn.get_global_rect().position.x > 320.0 * TouchControls.LEFT_ZONE_FRAC)
	var vp_w: float = vp.size.x
	# a touch in the left zone becomes the steer touch and spawns the stick
	var left_pos := Vector2(vp_w * 0.2, 100.0)
	var t_down := InputEventScreenTouch.new()
	t_down.index = 0
	t_down.position = left_pos
	t_down.pressed = true
	touch._input(t_down)
	assert(touch._steer_touch == 0)
	# a second finger landing on FIRE must NOT steal the steering finger's ownership
	var fire_pos: Vector2 = touch._fire_btn.get_global_rect().get_center()
	var f_down := InputEventScreenTouch.new()
	f_down.index = 1
	f_down.position = fire_pos
	f_down.pressed = true
	touch._input(f_down)
	assert(touch._fire_touch == 1)
	assert(touch._steer_touch == 0)   # unchanged — zone ownership held
	# dragging the steering finger right produces a proportional steer_right strength,
	# and leaves steer_left at zero rather than merely "pressed"
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = left_pos + Vector2(TouchControls.STICK_RADIUS, 0.0)   # full deflection
	touch._input(drag)
	assert(is_equal_approx(Input.get_action_strength("steer_right"), 1.0))
	assert(Input.get_action_strength("steer_left") == 0.0)
	# Task 2 integration: a raw action strength is only half the feature — prove
	# player.gd actually consumes it and turns. steer_right decreases yaw (see
	# player.gd's update_flight), so one physics step at full deflection must move
	# yaw down, not just leave the action flagged.
	var yaw_before: float = game.player.yaw
	game.player.update_flight(0.05)
	assert(game.player.yaw < yaw_before)
	# lifting the fire finger releases only fire, not steering
	var f_up := InputEventScreenTouch.new()
	f_up.index = 1
	f_up.position = fire_pos
	f_up.pressed = false
	touch._input(f_up)
	assert(touch._fire_touch == -1)
	assert(touch._steer_touch == 0)
	# lifting the steering finger releases the steer actions
	var t_up := InputEventScreenTouch.new()
	t_up.index = 0
	t_up.position = left_pos
	t_up.pressed = false
	touch._input(t_up)
	assert(touch._steer_touch == -1)
	assert(Input.get_action_strength("steer_right") == 0.0)
	# D10: a double-tap in the left zone toggles boost on, and it runs to depletion
	# on its own rather than needing the finger held
	var tap_pos := Vector2(vp_w * 0.15, 120.0)
	var tap_a := InputEventScreenTouch.new()
	tap_a.index = 2
	tap_a.position = tap_pos
	tap_a.pressed = true
	touch._input(tap_a)
	var tap_a_up := InputEventScreenTouch.new()
	tap_a_up.index = 2
	tap_a_up.position = tap_pos
	tap_a_up.pressed = false
	touch._input(tap_a_up)
	var tap_b := InputEventScreenTouch.new()
	tap_b.index = 3
	tap_b.position = tap_pos + Vector2(5.0, 5.0)   # well inside BOOST_TAP_DIST
	tap_b.pressed = true
	touch._input(tap_b)   # second tap of the pair — toggles boost on
	assert(touch._boost_active)
	assert(Input.is_action_pressed("boost"))
	var energy_before := GameState.energy
	GameState.energy = 0.0
	touch._process(0.016)
	assert(not touch._boost_active)          # depletion auto-cancels it
	assert(not Input.is_action_pressed("boost"))
	GameState.energy = energy_before
	# M4b's other two new signals — weapon_tapped/bomb_tapped — are otherwise only
	# exercised by careful reading (game.gd's touch_ui only builds under a real web
	# JavaScriptBridge check, per Task 4's brief), but TouchControls itself needs no
	# such gate: drive it directly to prove both signals actually fire.
	# One-element arrays, not plain bools: GDScript lambdas capture outer locals by
	# value, so a lambda assigning straight to a captured bool never reaches back to
	# this scope (confirmed empirically here — the signal demonstrably fired,
	# _weapon_touch got set in the very same branch as the emit(), yet a captured
	# bool stayed false). An array is captured by reference, so mutating its
	# contents is visible here.
	var weapon_fired := [false]
	var bomb_fired := [false]
	touch.weapon_tapped.connect(func() -> void: weapon_fired[0] = true)
	touch.bomb_tapped.connect(func() -> void: bomb_fired[0] = true)
	var wpn_pos: Vector2 = touch._weapon_btn.get_global_rect().get_center()
	var wpn_down := InputEventScreenTouch.new()
	wpn_down.index = 4
	wpn_down.position = wpn_pos
	wpn_down.pressed = true
	touch._input(wpn_down)
	assert(weapon_fired[0])
	var wpn_up := InputEventScreenTouch.new()
	wpn_up.index = 4
	wpn_up.position = wpn_pos
	wpn_up.pressed = false
	touch._input(wpn_up)
	var bomb_pos: Vector2 = touch._bomb_btn.get_global_rect().get_center()
	var bomb_down := InputEventScreenTouch.new()
	bomb_down.index = 5
	bomb_down.position = bomb_pos
	bomb_down.pressed = true
	touch._input(bomb_down)
	assert(bomb_fired[0])
	var bomb_up := InputEventScreenTouch.new()
	bomb_up.index = 5
	bomb_up.position = bomb_pos
	bomb_up.pressed = false
	touch._input(bomb_up)
	# M4c: D-pad mode drives the same steer_* actions at full strength, and the
	# stick path above (run entirely with the default touch_dpad_enabled == false)
	# proves the D-pad addition left that default path untouched. tap_b earlier
	# (index 3) claimed _steer_touch and was never released — reset it here the
	# same way the block below resets it for its own purposes, so a fresh D-pad
	# touch can claim the left zone.
	touch._steer_touch = -1
	GameState.touch_dpad_enabled = true
	var dpad_up_pos: Vector2 = touch._dpad_up.get_global_rect().get_center()
	var dpad_right_pos: Vector2 = touch._dpad_right.get_global_rect().get_center()
	var dp_down := InputEventScreenTouch.new()
	dp_down.index = 6
	dp_down.position = dpad_up_pos
	dp_down.pressed = true
	touch._input(dp_down)
	assert(touch._steer_touch == 6)
	assert(touch._dpad_root.visible)
	assert(is_equal_approx(Input.get_action_strength("steer_up"), 1.0))
	# a drag from the "up" cell into the (non-overlapping) "right" cell must release
	# steer_up and press steer_right within the same _update_dpad() call — this is
	# the edge-triggered diff loop actually changing which direction is active,
	# not just a single static press+release on one cell.
	var dp_drag := InputEventScreenDrag.new()
	dp_drag.index = 6
	dp_drag.position = dpad_right_pos
	touch._input(dp_drag)
	assert(is_equal_approx(Input.get_action_strength("steer_up"), 0.0))
	assert(is_equal_approx(Input.get_action_strength("steer_right"), 1.0))
	var dp_up := InputEventScreenTouch.new()
	dp_up.index = 6
	dp_up.position = dpad_right_pos
	dp_up.pressed = false
	touch._input(dp_up)
	assert(is_equal_approx(Input.get_action_strength("steer_right"), 0.0))
	assert(touch._steer_touch == -1)
	assert(not touch._dpad_root.visible)
	print("M4c ok — D-pad drag from \"up\" into \"right\" swaps steer_up/steer_right in one call, "
		+ "releases cleanly, default (stick) path above is unchanged")
	# Important #2 fix: D10's double-tap boost must still work in D-pad mode — boost-tap
	# detection is position-based (BOOST_TAP_DIST from the touch's *start* position),
	# independent of which steering UI owns the zone. Position chosen clear of the
	# D-pad's own bottom-left box so this tap can't also land inside a D-pad cell.
	var dtap_pos := Vector2(vp_w * 0.15, 20.0)
	var dtap_a := InputEventScreenTouch.new()
	dtap_a.index = 8
	dtap_a.position = dtap_pos
	dtap_a.pressed = true
	touch._input(dtap_a)
	var dtap_a_up := InputEventScreenTouch.new()
	dtap_a_up.index = 8
	dtap_a_up.position = dtap_pos
	dtap_a_up.pressed = false
	touch._input(dtap_a_up)
	var dtap_b := InputEventScreenTouch.new()
	dtap_b.index = 9
	dtap_b.position = dtap_pos + Vector2(5.0, 5.0)   # well inside BOOST_TAP_DIST
	dtap_b.pressed = true
	touch._input(dtap_b)   # second tap of the pair — toggles boost on, same as stick mode
	assert(touch._boost_active)
	assert(Input.is_action_pressed("boost"))
	var dtap_energy_before := GameState.energy
	GameState.energy = 0.0
	touch._process(0.016)
	assert(not touch._boost_active)          # depletion auto-cancels it, same as stick mode
	assert(not Input.is_action_pressed("boost"))
	GameState.energy = dtap_energy_before
	var dtap_b_up := InputEventScreenTouch.new()
	dtap_b_up.index = 9
	dtap_b_up.position = dtap_b.position
	dtap_b_up.pressed = false
	touch._input(dtap_b_up)
	assert(touch._steer_touch == -1)
	assert(not touch._dpad_root.visible)
	GameState.touch_dpad_enabled = false
	print("M4c ok — D10 boost double-tap toggles and self-depletes identically in D-pad mode")
	# Important #1 regression: a floating stick ring left visible from before a pause
	# must not survive a stick -> D-pad mode switch made while paused (the setting can
	# only change while touch_ui is inactive, so this reproduces the real
	# steer -> pause -> open settings -> enable D-pad -> resume sequence exactly).
	var ring_pos := Vector2(vp_w * 0.2, 90.0)
	var ring_down := InputEventScreenTouch.new()
	ring_down.index = 10
	ring_down.position = ring_pos
	ring_down.pressed = true
	touch._input(ring_down)
	assert(touch._stick_ring.visible)          # _start_stick() shows it
	# "pause": set_flight_active(false) always runs _release_all() first, while the
	# setting is still false here — this is the call that must clear the ring.
	touch.set_flight_active(false)
	assert(not touch._stick_ring.visible)
	# "open settings, flip the toggle" — only reachable while touch_ui is inactive
	GameState.touch_dpad_enabled = true
	# "resume" — set_flight_active(true) touches no stick/D-pad state itself, so the
	# ring must already have been clear before this, not merely about to become so
	assert(not touch._stick_ring.visible)
	touch.set_flight_active(true)
	assert(not touch._stick_ring.visible)
	touch._process(0.016)                      # a real frame after resuming, D-pad mode active
	assert(not touch._stick_ring.visible)
	GameState.touch_dpad_enabled = false
	print("M4c ok — floating stick ring can't survive a stick->D-pad mode switch made mid-pause")
	# set_flight_active(false) must leave nothing pressed — the whole point of M4b-1's
	# "never disabled" fix
	Input.action_press("steer_left", 1.0)
	touch._steer_touch = 5
	touch.set_flight_active(false)
	assert(not touch.visible)
	assert(Input.get_action_strength("steer_left") == 0.0)
	assert(touch._steer_touch == -1)
	touch.queue_free()
	Input.action_release("steer_right")   # belt-and-suspenders: don't leak into later sections
	Input.action_release("steer_left")
	print("M4b ok — zone ownership holds under a second finger, stick strength is proportional, "
		+ "boost double-tap toggles and self-depletes, weapon/bomb taps fire their signals, "
		+ "button geometry stays inside the 320x200 canvas, deactivation releases everything")
	print("SMOKE TEST COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
