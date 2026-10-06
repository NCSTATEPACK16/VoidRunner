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
	for f in ["user://records.cfg", "user://settings.cfg", "user://checkpoint.cfg"]:
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
		# --- 3.0 Phase 2: octagonal sections — every ring is chamfered, and
		# clamp_to_ring never leaves a point outside the cut corners ---
		var crng := RandomNumberGenerator.new()
		crng.seed = 4242 + i
		for probe in 60:
			var ri := crng.randi_range(0, path.rings.size() - 1)
			var ring: Dictionary = path.rings[ri]
			assert(ring.ch > 0.0 and ring.ch < ring.hw)
			var wild: Vector3 = ring.p + ring.r * crng.randf_range(-2.0, 2.0) * ring.hw \
				+ ring.u * crng.randf_range(-2.0, 2.0) * ring.hh
			var m := 1.5
			var q: Vector3 = path.clamp_to_ring(wild, ri, m)
			var lat: float = (q - ring.p).dot(ring.r)
			var vert: float = (q - ring.p).dot(ring.u)
			var edge: float = (ring.hh - ring.co) if vert >= 0.0 else (ring.hh - ring.fo)
			assert(absf(lat) + absf(vert) <= ring.hw + edge - ring.ch - m * 1.41 + 0.01)
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
	# --- 3.0 Phase 1: 256-color ramp palette ---
	assert(Palette.ALL.size() == 256)
	assert(Palette.ramp(Palette.GREY, 0) == Color(0, 0, 0))   # fog black is a real entry
	assert(Palette.ramp(Palette.GREY, 15) == Color(1, 1, 1))
	for r in Palette.RAMP_STOPS.size():   # every ramp brightens monotonically
		for sh in range(1, Palette.RAMP_LEN):
			assert(Palette.ramp(r, sh).get_luminance() >= Palette.ramp(r, sh - 1).get_luminance())
	assert(Palette.ramp_f(Palette.RED, 1.0) == Palette.ramp(Palette.RED, 15))
	print("palette ok — %d colors in %d ramps" % [Palette.ALL.size(), Palette.RAMP_STOPS.size()])
	# --- 3.0 Phase 3: sprite forge (headless = pixel fallback, same set shape) ---
	for id in SpriteModels.ENEMIES + SpriteModels.BOSSES:
		var st: Dictionary = SpriteForge.sprite_set(id)
		assert(st.tex.size() == st.angles * st.anim and st.flash.size() == st.angles)
	for kind in SpriteModels.PICKUPS:
		assert(not SpriteForge.pickup_frames(kind).is_empty())
	assert(SpriteForge.prop_texture() != null)
	for lv in [3, 6, 9]:
		var bl: LevelDef = load("res://resources/levels/level_%d.tres" % lv)
		assert(SpriteModels.BOSSES.has(bl.boss_model))
	# the angle picker: camera dead ahead = front cell, behind = back, and the
	# model-yaw convention (cell a = model turned a * 45 deg) round-trips
	assert(SpriteForge.angle_index(Vector3.FORWARD, Vector3.FORWARD, 8) == 0)
	assert(SpriteForge.angle_index(Vector3.FORWARD, Vector3.BACK, 8) == 4)
	for a in 8:
		var yaw := a * TAU / 8.0
		var facing := Vector3(sin(yaw), 0.0, cos(yaw))   # model front after yaw
		assert(SpriteForge.angle_index(facing, Vector3.BACK, 8) == a)
	assert(FxGen.fireball_frames().size() == FxGen.FIREBALL_FRAMES)   # v4a: 14
	assert(FxGen.orb_frames(Palette.CYAN).size() == 2)
	print("forge ok — %d enemy + %d boss sets, %d pickups, gpu=%s" % [
		SpriteModels.ENEMIES.size(), SpriteModels.BOSSES.size(), SpriteModels.PICKUPS.size(),
		SpriteForge.gpu_baked])
	# --- v4b parts kit: closed flat-shaded meshes facing the right way, mirrored pairs,
	# painted maps on their own materials, and bake sheets inside a WebGL2 texture ---
	var kit_meshes: Array[ArrayMesh] = [SpriteModels.taper(1.2, 0.6, 0.3, 0.2, 1.8, 0.1),
		SpriteModels.fin(0.9, 0.7, 0.25, 0.4, 0.08)]
	kit_meshes.append(SpriteModels._mirror_mesh(kit_meshes[1]))
	for km in kit_meshes:
		var ka := km.surface_get_arrays(0)
		var kv: PackedVector3Array = ka[Mesh.ARRAY_VERTEX]
		var kn: PackedVector3Array = ka[Mesh.ARRAY_NORMAL]
		assert(kv.size() == 36 and (ka[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == 36)
		var kc := Vector3.ZERO
		for v in kv:
			kc += v / kv.size()
		for t in range(0, kv.size(), 3):
			assert(is_equal_approx(kn[t].length(), 1.0))
			assert(kn[t].dot((kv[t] + kv[t + 1] + kv[t + 2]) / 3.0 - kc) > 0.0)   # outward
			# Godot's front faces wind clockwise seen from outside
			assert((kv[t + 1] - kv[t]).cross(kv[t + 2] - kv[t]).dot(kn[t]) < 0.0)
	assert(SpriteModels.taper(1, 1, 1, 1, 1) == SpriteModels.taper(1, 1, 1, 1, 1))   # cached
	var kroot := Node3D.new()
	var kpair := SpriteModels.pair(kroot, kit_meshes[1], SpriteModels.m("e8302a"),
		Vector3(0.2, 0.1, 0.3), Vector3(0, 20, 10))
	assert(kpair[1].position.is_equal_approx(Vector3(-0.2, 0.1, 0.3)))
	assert(kpair[1].rotation_degrees.is_equal_approx(Vector3(0, -20, -10)))
	for v in (kpair[1].mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		assert(v.x <= 0.0001)   # the mirrored fin stands out along -X
	kroot.free()
	var kpaint := SpriteModels.painted("b0b8c8", "panel")
	assert(kpaint.get_shader_parameter("detail") == TextureGen.hull_paint("panel"))
	assert(SpriteModels.painted("ffffff", "hazard").get_shader_parameter("decal") != null)
	assert(SpriteModels.m("b0b8c8").get_shader_parameter("detail") == null)   # stays plain
	for kind in ["panel", "vents", "hazard"]:
		var hp := TextureGen.hull_paint(kind).get_image()
		assert(hp.get_width() == TextureGen.SIZE and not hp.has_mipmaps())
		var px := hp.get_pixel(9, 21)
		assert(kind == "hazard" or (px.r == px.g and px.g == px.b))   # detail maps are grey
	var fake_ids := []
	for k in 18:
		fake_ids.append("e%d" % k)
	var chunks := SpriteForge.sheet_chunks(fake_ids, 64, 2)
	assert(chunks.size() == 2 and chunks[0].size() == 9 and chunks[1].size() == 9)
	for ids in chunks:
		assert(ids.size() * 64 * 2 <= SpriteForge.MAX_SHEET_PX)
	for ids in SpriteForge.sheet_chunks(fake_ids, 128, 2):   # boss-sized cells: 8 per sheet
		assert(ids.size() * 128 * 2 <= SpriteForge.MAX_SHEET_PX)
	assert(SpriteForge.sheet_chunks(SpriteModels.BOSSES, 128, 2).size() == 1)
	assert(SpriteForge.sheet_chunks(fake_ids.slice(0, 16), 64, 2).size() == 1)   # 2048 fits
	print("KIT ok — closed outward clockwise meshes, mirrored pairs, painted maps, %d-id sheets fit %d px" % [
		chunks[0].size(), SpriteForge.MAX_SHEET_PX])
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	print("boot ok — state=%d levels=%d" % [game.state, game.levels.size()])
	assert(game.palette_lut.lut_texture != null)
	assert(game.palette_lut.palette_texture.get_width() == 256)
	# --- 3.0 Phase 2: one shader for the world, no OmniLight3D anywhere ---
	for key in TextureGen.KEYS:
		assert(game.world.mats[key] is ShaderMaterial)
	assert(game.light_rig.material_count() >= TextureGen.KEYS.size())
	assert(game.find_children("*", "OmniLight3D", true, false).is_empty())
	for theme_id in TextureGen.THEMES:
		var texes: Dictionary = TextureGen.theme_textures(theme_id)
		for key in TextureGen.KEYS:
			assert((texes[key] as ImageTexture).get_width() == TextureGen.SIZE)
	print("world ok — %d themes x %d textures, %d sector materials, no OmniLights" % [
		TextureGen.THEMES.size(), TextureGen.KEYS.size(), game.light_rig.material_count()])
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
	# --- V2.1 caps, v4 batching: per-class caps hold under a 50-boom burst, each
	# layer draws exactly what is alive through one FxBatch, and the burst drains.
	# No node exists per effect any more, only the layers under ShotManager ---
	var bsm: ShotManager = game.shot_mgr
	for c in bsm.get_children():
		assert(c is FxBatch)
	for b in 50:
		bsm.spawn_explosion(game.player.position + Vector3(b, 0, 0), b % 2 == 0)
	assert(bsm._explosions.size() <= ShotManager.EXPLOSION_CAP)
	assert(bsm._sparks.size() <= ShotManager.SPARK_CAP)
	assert(bsm._shocks.size() <= ShotManager.SHOCK_CAP)
	assert(bsm._eshots.size() <= ShotManager.ESHOT_CAP)
	bsm.sync_batches()
	assert(bsm._fx_boom.count() == bsm._explosions.size() and bsm._fx_boom.visible)
	assert(bsm._fx_spark.count() == bsm._sparks.size())
	assert(bsm._fx_shock.count() == bsm._shocks.size())
	assert(bsm._fx_ebolt.count() == bsm._eshots.size())
	# shots still in flight from the run above (a bolt that infights, a missile on its
	# fuse) can blow something up mid-drain and start a fresh blast, an intermittent
	# failure here, so the drain runs without them
	bsm._eshots.clear()
	bsm._pshots.clear()
	for f in 90:   # fireballs and sparks live 0.6-0.7 s — let the burst drain away
		bsm.update_shots(dt)
	assert(bsm._explosions.is_empty() and bsm._sparks.is_empty() and bsm._shocks.is_empty())
	bsm.sync_batches()
	assert(bsm._fx_boom.count() == 0 and not bsm._fx_boom.visible)   # empty: no draw call
	assert(bsm._fx_smoke.count() == bsm._puffs.size())   # the blasts' aftermath still hangs
	print("batching ok — 50-boom burst capped and drained, %d layers, one draw call each" % [
		bsm.layers().size()])
	# --- V2.2 L1b: gibs — burst past the cap, ricochet sim, full drain. v4: all of
	# them in one FxBatch, yellow-hot at first and cooling into the hull tint ---
	var gm: GibManager = game.gib_mgr
	gm.burst(game.player.position + game.player.forward() * 10.0, Vector3(4, 2, -6),
		game.player.ring_idx, 60, Color.RED)   # 60 asked > 48 cap
	assert(gm.active_count() <= 48)
	assert(gm.active_count() > 0)
	gm.sync_batch()
	assert(gm._fx.count() == gm.active_count())
	var hot := GibManager.heat_color(Color.RED, 0.0)
	assert(hot.r > 0.95 and hot.g > 0.7 and hot.b < hot.g)   # yellow-hot, not red
	var warm := GibManager.heat_color(Color.RED, GibManager.COOL_T * 0.5)
	assert(warm.r > 0.9 and warm.g > 0.3 and warm.g < hot.g)   # cooling through orange
	assert(GibManager.heat_color(Color.RED, GibManager.COOL_T) == Color.RED)   # the tint
	for f in 400:   # ~4 s of physics — every chunk must expire and free its slot
		gm._sim(0.01)
	assert(gm.active_count() == 0)
	gm.sync_batch()
	assert(gm._fx.count() == 0 and not gm._fx.visible)
	print("gibs ok — cap held, one batch, hot debris cools, pool drained")
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
	# --- 3.0 phase 4: LED gauges track the meters (a partial segment still lights)
	var hud_shields := GameState.shields
	GameState.shields = GameState.max_shields() * 0.5
	assert(game.hud._led.x == Hud.LED_N / 2)
	GameState.shields = 1.0
	assert(game.hud._led.x == 1)
	assert(game.hud._shield_num.text == "1")
	GameState.shields = hud_shields
	assert(game.hud._led.x == ceili(hud_shields / GameState.max_shields() * Hud.LED_N))
	print("hud ok — LED gauges follow shields")
	# --- 3.0 phase 5: timed power-ups ---
	var was_dead := GameState.is_dead   # the flight sim above may have ended in a death
	GameState.is_dead = false
	GameState.clear_powers()
	game.shot_mgr.clear_all()
	GameState.shields = GameState.max_shields()
	game.player.iframes_t = 0.0
	var pw_full := GameState.shields
	game.pickup_mgr._collect("phase")
	assert(GameState.power_on("phase"))
	game.player.take_damage(10.0, "TEST")
	assert(GameState.shields == pw_full)             # PHASE SHIELD: untouchable
	GameState.tick_powers(GameState.POWER_TIME.phase + 0.1)
	assert(not GameState.power_on("phase"))          # the clock ran out...
	game.player.take_damage(10.0, "TEST")
	assert(GameState.shields < pw_full)              # ...and hits land again
	GameState.shields = pw_full
	var w0: WeaponDef = game.weapons[0]
	GameState.weapon_index = 0
	game.shot_mgr.fire_player(w0)
	var base_dmg: float = game.shot_mgr._pshots.back().dmg
	game.pickup_mgr._collect("powercore")
	game.shot_mgr.fire_player(w0)
	assert(is_equal_approx(game.shot_mgr._pshots.back().dmg, base_dmg * 2.0))   # POWER CORE
	GameState.heat = 50.0
	game.pickup_mgr._collect("overdrive")
	assert(GameState.heat == 0.0)                    # grabbing it vents the guns
	game._fire_cd = 0.0
	Input.action_press("fire")
	game._update_firing(0.0)
	Input.action_release("fire")
	assert(GameState.heat == 0.0)                    # OVERDRIVE: the guns stay cold
	assert(is_equal_approx(game._fire_cd,
		w0.cooldown * GameState.weapon_mult(0, "interval") * game.OVERDRIVE_RATE))
	for pw_i in 40:
		assert(EnemyManager.random_power() in GameState.POWER_TIME)
	GameState.clear_powers()
	assert(not GameState.power_on("overdrive") and not GameState.power_on("powercore"))
	print("powerups ok — phase blocks damage then expires, core doubles damage, overdrive vents + halves the interval")
	# --- 3.0 phase 5: new enemy behaviours ---
	var em: EnemyManager = game.enemy_mgr
	em.clear_all()
	game.shot_mgr.clear_all()
	game.player.reset_to_start()   # mid-tunnel on a straight: placements stay inside
	var pring: int = game.player.ring_idx
	var pfwd: Vector3 = game.player.forward()
	# MINE: arms when the ship is close, bursts inside a second, hurts if still near
	em.spawn(pring, -1, "mine")
	var mine: Dictionary = em.enemies.back()
	assert(mine.hp == 1 and mine.mode == "idle")
	mine.node.position = game.player.position + pfwd * 6.0
	em.update_enemies(dt)
	assert(mine.mode == "armed")
	var mine_sh := GameState.shields
	for f in 60:
		em.update_enemies(dt)
	assert(em.enemies.is_empty())                    # burst and gone
	assert(GameState.shields < mine_sh)              # the ship was inside the blast
	GameState.shields = pw_full
	game.player.bounce = Vector3.ZERO
	# a mine shot from range pops harmlessly and chains into its neighbour
	em.spawn(pring, -1, "mine")
	var m2: Dictionary = em.enemies.back()
	m2.node.position = game.player.position + pfwd * 40.0
	em.spawn(pring, -1, "drone")
	var bystander: Dictionary = em.enemies.back()
	bystander.node.position = m2.node.position + Vector3(3, 0, 0)
	bystander.hp = 3
	var chain_score := GameState.score
	em.hit_enemy(em.enemies.find(m2), 5)
	assert(em._pending_blasts.size() == 1)           # the burst waits for next frame
	em.update_enemies(dt)
	assert(not em.enemies.has(bystander))            # ...then takes the drone with it
	assert(GameState.shields == pw_full)             # a mine you shoot can't hurt you
	assert(GameState.score > chain_score)
	em.clear_all()
	# STINGER: winds up only in front of the ship, then dives; sidestep and it misses
	game.player.wall_hurt_t = 0.0
	em.spawn(pring, -1, "stinger")
	var sting: Dictionary = em.enemies.back()
	sting.node.position = game.player.position + pfwd * 40.0
	sting.mode_t = 0.0
	em.update_enemies(dt)
	assert(sting.mode == "wind")                        # the tell
	var sting_flash := false
	for f in 60:
		em.update_enemies(dt)
		sting_flash = sting_flash or sting.flash_t > 0.0
		if sting.mode == "dive":
			break
	assert(sting.mode == "dive" and sting_flash)
	var sting_home: Vector3 = game.player.position
	game.player.position += pfwd.cross(Vector3.UP).normalized() * 12.0   # sidestep
	for f in 120:
		em.update_enemies(dt)
	assert(GameState.shields == pw_full)             # dodged
	assert(em.enemies.has(sting))                       # a miss doesn't spend it
	game.player.position = sting_home
	em.clear_all()
	# ...hold still and the dive connects, spending the stinger
	em.spawn(pring, -1, "stinger")
	var sting2: Dictionary = em.enemies.back()
	sting2.node.position = game.player.position + pfwd * 30.0
	sting2.mode = "dive"
	sting2.mode_t = EnemyManager.STINGER_DIVE_T
	sting2.dive_dir = -pfwd
	for f in 90:
		em.update_enemies(dt)
		if em.enemies.is_empty():
			break
	assert(em.enemies.is_empty() and GameState.shields < pw_full)
	GameState.shields = pw_full
	# SPINNER: one full ring per burst, its hole aimed at the ship
	em.spawn(pring, -1, "spinner")
	var spn: Dictionary = em.enemies.back()
	spn.node.position = game.player.position + pfwd * 45.0
	spn.fire_t = 0.0
	var ring_vels: Array[Vector3] = []
	var grab := func(_o: Vector3, v: Vector3, _d: float, _s: float, _k: bool, _src: Node3D) -> void:
		ring_vels.append(v)
	em.enemy_fired.connect(grab)
	em.update_enemies(dt)
	em.enemy_fired.disconnect(grab)
	assert(ring_vels.size() == EnemyManager.SPINNER_SPOKES)
	var ring_sum := Vector3.ZERO
	for v in ring_vels:
		ring_sum += v
	assert(ring_sum.normalized().dot(
		(game.player.position - spn.node.position).normalized()) > 0.99)
	em.clear_all()
	print("enemies ok — mine arms/bursts/chains, stinger tells + dives + misses, spinner rings")
	# --- 3.0 phase 5: every boss has its own pattern ---
	em.spawn_boss(pring, game.levels[5])              # BROOD MOTHER
	var bb: Dictionary = em.boss
	assert(bb.model == "brood")
	bb.node.position = game.player.position + pfwd * 50.0
	bb.anchor = bb.node.position
	bb.summon_t = 0.0
	em.update_enemies(dt)
	var hatch := 0
	for en in em.enemies:
		if en.get("type", "") == "stinger" and en.get("summoned", false):
			hatch += 1
	assert(hatch == 1)                               # phase 1: a hatchling
	bb.hp = int(bb.max_hp * 0.5)
	bb.lay_t = 0.0
	em.update_enemies(dt)
	var laid := 0
	for en in em.enemies:
		if en.get("laid", false):
			laid += 1
	assert(bb.phase == 2 and laid == 1)              # phase 2: she lays mines
	em.clear_all()
	em.spawn_boss(pring, game.levels[8])              # THE RIFT MAW
	var mb: Dictionary = em.boss
	assert(mb.model == "maw")
	mb.node.position = game.player.position + pfwd * 60.0
	mb.anchor = mb.node.position
	mb.hp = int(mb.max_hp * 0.2)                     # phase 3: the double spiral
	mb.fire_t = 99.0
	mb.volley_t = 99.0
	mb.summon_t = 99.0
	mb.spiral_t = 1.0
	var spiral := [0]
	var tally := func(_o: Vector3, _v: Vector3, _d: float, _s: float, _k: bool, _src: Node3D) -> void:
		spiral[0] += 1
	em.enemy_fired.connect(tally)
	for f in 30:
		em.update_enemies(dt)
	em.enemy_fired.disconnect(tally)
	assert(mb.phase == 3 and spiral[0] >= 8)         # ~5 steps x 2 arms in 0.5 s
	em.clear_all()
	game.shot_mgr.clear_all()
	GameState.shields = pw_full
	GameState.is_dead = was_dead
	print("bosses ok — brood hatches stingers + lays mines, maw hoses a double spiral")
	# --- v4b roster (part 1): LAYER, RAMMER, MENDER, SPLITTER, each with one rule ---
	GameState.is_dead = false
	game.player.reset_to_start()
	game.player.iframes_t = 0.0
	game.player.wall_hurt_t = 0.0
	GameState.shields = pw_full
	em.clear_all()
	game.shot_mgr.clear_all()
	pring = game.player.ring_idx
	pfwd = game.player.forward()
	var pside := pfwd.cross(Vector3.UP).normalized()
	var roster_shots := [0]
	var count_roster_shots := func(_o: Vector3, _v: Vector3, _d: float, _s: float, _k: bool,
			_src: Node3D) -> void:
		roster_shots[0] += 1
	em.enemy_fired.connect(count_roster_shots)
	# SPLITTER: dies into three drones the frame after, fanned out where it burst...
	em.spawn(pring + 3, -1, "splitter")
	var spl: Dictionary = em.enemies.back()
	assert(spl.max_hp == spl.hp)
	var burst_at: Vector3 = spl.node.position   # (its node goes back to the pool)
	em.hit_enemy(em.enemies.find(spl), 99)
	assert(em.enemies.is_empty() and em._pending_splits.size() == 1)   # the brood waits
	assert(em._reserved == 3)
	em.update_enemies(dt)
	assert(em.enemies.size() == 3 and em._reserved == 0)
	for brood in em.enemies:
		assert(brood.type == "drone" and brood.node.position.distance_to(burst_at) < 4.0)
	em.hit_enemy(0, 99)                              # ...and a drone never splits
	assert(em._pending_splits.is_empty())
	em.clear_all()
	# the brood counts toward ENEMY_CAP: only the free slots are reserved, and no other
	# spawn can take them before the hatch
	for n in EnemyManager.ENEMY_CAP - 2:
		em.spawn(pring + 4, -1, "drone")
	em.spawn(pring + 3, -1, "splitter")
	assert(em.enemies.size() == EnemyManager.ENEMY_CAP - 1)
	em.hit_enemy(em.enemies.size() - 1, 99)
	assert(em._reserved == 2)
	em.spawn(pring + 4, -1, "drone")                 # refused: the brood's slots are held
	assert(em.enemies.size() == EnemyManager.ENEMY_CAP - 2)
	em.update_enemies(dt)
	assert(em.enemies.size() == EnemyManager.ENEMY_CAP and em._reserved == 0)
	em.clear_all()
	# inside a locked arena the brood joins the room's tally, so the door waits for it
	var lock: Dictionary = {}
	for a in game.path.arenas:
		if a.door_ring >= 0 and not game.world.is_door_open(a.id):
			lock = a
	assert(not lock.is_empty())
	game._arena_spawned[lock.id] = 1
	game._arena_kills[lock.id] = 0
	em.spawn(lock.start + 2, lock.id, "splitter")
	em.hit_enemy(em.enemies.size() - 1, 99)
	assert(game._arena_spawned[lock.id] == 4 and game._arena_kills[lock.id] == 1)
	assert(not game.world.is_door_open(lock.id))
	em.update_enemies(dt)
	for k in range(em.enemies.size() - 1, -1, -1):
		em.hit_enemy(k, 99)
	assert(game.world.is_door_open(lock.id))         # the brood is down: it opens
	em.clear_all()
	# MENDER: never fires; patches the most damaged ally in reach, +1 a tick, never past
	# full, never a boss; each repair throws green sparks
	em.spawn(pring + 6, -1, "mender")
	var mnd: Dictionary = em.enemies.back()
	em.spawn(pring + 6, -1, "hulk")
	var patient: Dictionary = em.enemies.back()
	patient.node.position = mnd.node.position + Vector3(6, 0, 0)
	patient.hp = patient.max_hp - 2
	patient.fire_t = 99.0
	var mends := [0]
	var count_mends := func(_p: Vector3) -> void:
		mends[0] += 1
	em.mended.connect(count_mends)
	game.shot_mgr.clear_all()
	roster_shots[0] = 0
	mnd.fire_t = 0.0
	em.update_enemies(dt)
	assert(patient.hp == patient.max_hp - 1 and mends[0] == 1)
	var mend_spark := false
	for sp in game.shot_mgr._sparks:
		mend_spark = mend_spark or sp.cell == ShotManager.SPARK_MEND
	assert(mend_spark)
	for tick in 3:
		mnd.fire_t = 0.0
		em.update_enemies(dt)
	assert(patient.hp == patient.max_hp and mends[0] == 2)   # topped up, never past full
	for f in 180:
		em.update_enemies(dt)
	assert(roster_shots[0] == 0)                     # three seconds and not one shot
	em.clear_all()
	em.spawn_boss(pring + 8, game.levels[2])
	em.boss.node.position = game.player.position + pfwd * 250.0   # dormant, out of reach
	em.boss.hp = em.boss.max_hp - 5
	em.spawn(pring + 6, -1, "mender")
	mnd = em.enemies.back()
	mnd.node.position = em.boss.node.position + Vector3(4, 0, 0)
	mnd.fire_t = 0.0
	em.update_enemies(dt)
	assert(em.boss.hp == em.boss.max_hp - 5 and mends[0] == 2)   # bosses are never patched
	em.mended.disconnect(count_mends)
	em.clear_all()
	game.shot_mgr.clear_all()
	# LAYER: holds 40-60 u ahead of a cruising ship down the tunnel, and on a straight
	# lays mines behind itself, never more than LAY_CAP of its own
	em.spawn(pring + 3, -1, "layer")
	var lay: Dictionary = em.enemies.back()
	var lay_from: Vector3 = game.player.position
	for f in 180:                                    # 3 s of cruise down the tunnel
		var at_ring: Dictionary = game.path.rings[game.player.ring_idx + 1]
		game.player.position += (at_ring.p - game.player.position).normalized() \
			* PlayerShip.BASE_SPEED * dt
		game.player.ring_idx = game.path.nearest_ring(game.player.position,
			game.player.ring_idx)
		lay.fire_t = 99.0                            # no mines yet: just the chase
		em.update_enemies(dt)
	var lay_gap: float = lay.node.position.distance_to(game.player.position)
	assert(lay_gap > 40.0 and lay_gap < 60.0)
	assert(game.player.position.distance_to(lay_from) > 40.0)   # the ship really moved
	for drop in 5:
		lay.fire_t = 0.0
		em.update_enemies(dt)
	var lay_mines := 0
	for en in em.enemies:
		if en.get("laid_by") == lay.node:
			lay_mines += 1
			assert(en.type == "mine")
			assert(en.node.position.distance_to(game.player.position) < lay_gap)   # behind it
	assert(lay_mines == EnemyManager.LAY_CAP)
	em.clear_all()
	game.player.reset_to_start()
	# RAMMER: a warning, then a straight charge at where the ship was; met mid-roll it
	# shatters (scored)...
	em.spawn(pring + 6, -1, "rammer")
	var ram: Dictionary = em.enemies.back()
	ram.node.position = game.player.position + pfwd * 60.0
	ram.mode_t = 0.0
	em.update_enemies(dt)
	assert(ram.mode == "rev")
	for f in 90:
		em.update_enemies(dt)
		if ram.mode == "charge":
			break
	assert(ram.mode == "charge")
	var ram_line: Vector3 = ram.dive_dir
	game.player.position += pside * 2.0              # the ship slips aside: no tracking
	em.update_enemies(dt)
	assert((ram.dive_dir as Vector3).is_equal_approx(ram_line))
	game.player.position -= pside * 2.0
	game.player.iframes_t = 1.0
	var ram_score := GameState.score
	var ram_sh := GameState.shields
	for f in 90:
		em.update_enemies(dt)
		if em.enemies.is_empty():
			break
	assert(em.enemies.is_empty() and GameState.shields == ram_sh and GameState.score > ram_score)
	game.player.iframes_t = 0.0
	# ...a miss can't stop before the wall (scored too)...
	em.spawn(pring + 6, -1, "rammer")
	var ram_miss: Dictionary = em.enemies.back()
	ram_miss.node.position = game.player.position + pfwd * 4.0 + pside * 6.0
	ram_miss.mode = "charge"
	ram_miss.mode_t = EnemyManager.RAMMER_CHARGE_T
	ram_miss.dive_dir = (-pfwd + pside * 0.4).normalized()
	ram_score = GameState.score
	for f in 60:
		em.update_enemies(dt)
		if em.enemies.is_empty():
			break
	assert(em.enemies.is_empty() and GameState.shields == ram_sh and GameState.score > ram_score)
	# ...and taken head-on it hurts badly, and it's spent
	em.spawn(pring + 6, -1, "rammer")
	var ram_hit: Dictionary = em.enemies.back()
	ram_hit.node.position = game.player.position + pfwd * 30.0
	ram_hit.mode = "charge"
	ram_hit.mode_t = EnemyManager.RAMMER_CHARGE_T
	ram_hit.dive_dir = -pfwd
	for f in 90:
		em.update_enemies(dt)
		if em.enemies.is_empty():
			break
	assert(em.enemies.is_empty())
	assert(is_equal_approx(GameState.shields,
		ram_sh - EnemyManager.RAMMER_DMG * GameState.damage_taken_mult()))
	GameState.shields = pw_full
	em.clear_all()
	game.shot_mgr.clear_all()
	em.enemy_fired.disconnect(count_roster_shots)
	GameState.is_dead = was_dead
	# every pool id is a real type with a baked model, and every type has its tables
	for lv: LevelDef in game.levels:
		for id in lv.enemy_types:
			assert(EnemyManager.TYPES.has(id))
		assert(lv.intro_types.size() <= 2)
		for id in lv.intro_types:
			assert(id in lv.enemy_types)
	for id in EnemyManager.TYPES:
		var model_id := EnemyManager.base_type(id)   # (a heavy wears its base's set)
		assert(SpriteModels.ENEMIES.has(model_id) and EnemyManager.GIB_TINTS.has(model_id))
	for id in ["layer", "rammer", "mender", "splitter"]:
		var tdef: Dictionary = EnemyManager.TYPES[id]
		assert(tdef.has("salvage") or tdef.has("split"))
		assert(EnemyManager.POWER_DROP.has(id))
	# the gauntlet's deepest tiers field the whole roster, newcomers from tier 2 up
	game._apply_gauntlet_tier(6)
	for id in EnemyManager.TYPES:
		assert(id in game._gauntlet_def.enemy_types)
	game._apply_gauntlet_tier(1)
	for id in ["layer", "rammer", "mender", "splitter"]:
		assert(not id in game._gauntlet_def.enemy_types)
	game._apply_gauntlet_tier(0)
	# L5's newcomers: met in plain tunnel, in order, never rolled before their ring
	var l5: LevelDef = game.levels[4]
	var l5_path := PathGen.new()
	l5_path.generate(l5.rings, l5.level_seed, l5.spawn_arena, false)
	var held_path: PathGen = game.path
	game.path = l5_path
	var plan: Dictionary = game._plan_intros(l5)
	assert(plan.size() == 2 and plan.mender < plan.splitter and plan.mender >= 21)
	for id in plan:
		var at: int = plan[id]
		for r in range(at - 4, at + 5):
			assert(not l5_path.rings[r].arena)
		for a in l5_path.arenas:
			assert(a.door_ring < 0 or absi(at - a.door_ring) >= 6)
	game._intro_rings = plan
	for roll in 200:
		assert(game._pick_enemy_type(l5, plan.mender - 1) != "mender")
		assert(game._pick_enemy_type(l5, plan.splitter - 1) != "splitter")
	var seen := {}
	for roll in 400:
		seen[game._pick_enemy_type(l5, plan.splitter)] = true
	assert(seen.has("mender") and seen.has("splitter"))
	# L3's newcomer waits in the boss sector's entry tunnel, short of the room
	var l3: LevelDef = game.levels[2]
	var l3_path := PathGen.new()
	l3_path.generate(l3.rings, l3.level_seed, l3.spawn_arena, true)
	game.path = l3_path
	var l3_plan: Dictionary = game._plan_intros(l3)
	assert(l3_plan.size() == 1 and l3_plan.layer >= 21)
	assert(l3_plan.layer < (l3_path.arenas[0].start as int))
	game.path = held_path
	# on a fresh start the newcomer spawns at its ring, alone: random rolls around it
	# are held off. On a resume it doesn't come at all
	var l1_tunnel: float = game.levels[0].spawn_tunnel
	game.levels[0].spawn_tunnel = 1.0
	game._intro_rings = {"rammer": 24}
	game._intros_live = true
	game._on_tunnel_spawn(24)
	assert(em.enemies.size() == 1 and em.enemies[0].type == "rammer")
	game._on_tunnel_spawn(24 + 6)
	game._on_tunnel_spawn(24 - game.INTRO_CLEAR)
	assert(em.enemies.size() == 1)
	game._on_tunnel_spawn(24 + game.INTRO_CLEAR + 1)
	assert(em.enemies.size() == 2)
	em.clear_all()
	game._intros_live = false
	game._on_tunnel_spawn(24)
	assert(em.enemies.size() == 1 and em.enemies[0].type != "rammer")
	game.levels[0].spawn_tunnel = l1_tunnel
	game._intro_rings = {}
	em.clear_all()
	# every sector's tactical briefing fits its three-line band
	var brief_body: Label = game.overlays._panels.briefing.get_node("Body")
	for lv: LevelDef in game.levels:
		game.overlays.set_briefing(lv)
		assert(brief_body.get_line_count() <= 3)
	game.overlays.set_briefing(game._current_level())
	print("ROSTER ok — splitter brood (under the cap, holds the door), mender to full (never a boss), layer 40-60 u ahead + mine cap, rammer straight charge + roll/miss/hit; pools, intros, briefings")
	# --- v4b roster (part 2): WRAITH, CRAWLER, WARDEN, CARRIER and the heavies ---
	GameState.is_dead = false
	game.player.reset_to_start()
	game.player.iframes_t = 0.0
	game.player.wall_hurt_t = 0.0
	GameState.shields = pw_full
	em.clear_all()
	game.shot_mgr.clear_all()
	pring = game.player.ring_idx
	pfwd = game.player.forward()
	pside = pfwd.cross(Vector3.UP).normalized()
	em.enemy_fired.connect(count_roster_shots)
	# WRAITH: cloaked it can't be seen, locked or shot (a blast still finds it)...
	em.spawn(pring + 4, -1, "wraith")
	var wr: Dictionary = em.enemies.back()
	assert(wr.cloaked and not wr.node.visible and wr.hit_r2 < 0.0)
	assert(em.nearest_enemy(game.player.position) == null)
	var wr_hp: int = wr.hp
	wr.node.position = game.player.position + pfwd * 8.0
	wr.mode_t = 99.0
	GameState.weapon_index = 0
	game.shot_mgr.fire_player(game.weapons[0])
	for f in 20:
		game.shot_mgr.update_shots(dt)
	assert(wr.hp == wr_hp)                           # straight through
	em.splash_damage(wr.node.position, 10.0, 1)
	assert(wr.hp == wr_hp - 1)
	wr.hp = wr_hp
	# ...it shimmers in before it fires, hittable from the first shimmer, fires a fan
	# of three, and vanishes again WRAITH_SHOW later
	wr.node.position = game.player.position + pfwd * 40.0
	wr.mode_t = 0.0
	roster_shots[0] = 0
	em.update_enemies(dt)
	assert(wr.mode == "shimmer" and not wr.cloaked and wr.hit_r2 > 0.0)
	assert(em.nearest_enemy(game.player.position) == wr.node)
	for f in 60:
		em.update_enemies(dt)
		if wr.mode == "strike":
			break
	assert(wr.mode == "strike" and wr.node.visible and roster_shots[0] == 3)
	var wr_shown := 0
	while wr.mode == "strike" and wr_shown < 120:
		em.update_enemies(dt)
		wr_shown += 1
	assert(wr.cloaked and not wr.node.visible)
	assert(absf(wr_shown * dt - EnemyManager.WRAITH_SHOW) < 0.05)
	em.clear_all()
	# under REDUCE FLASH the shimmer is a steady fade up out of the dark: no flicker
	GameState.reduce_flashing = true
	em.spawn(pring + 4, -1, "wraith")
	var wr2: Dictionary = em.enemies.back()
	wr2.node.position = game.player.position + pfwd * 40.0
	wr2.mode_t = 0.0
	em.update_enemies(dt)
	assert(wr2.mode == "shimmer")
	var wr_glow: Array[float] = []
	while wr2.mode == "shimmer" and wr_glow.size() < 120:
		em.update_enemies(dt)
		assert(wr2.node.visible)
		wr_glow.append(wr2.node.modulate.r + wr2.node.modulate.g + wr2.node.modulate.b)
	for g in range(1, wr_glow.size()):
		assert(wr_glow[g] >= wr_glow[g - 1] - 0.001)   # it only ever brightens
	assert(wr_glow.size() > 10 and wr_glow[0] < wr_glow.back() * 0.3)
	assert(wr2.node.modulate.is_equal_approx(em._lit(wr2)))   # full light as it fires
	GameState.reduce_flashing = false
	em.clear_all()
	game.shot_mgr.clear_all()
	# CRAWLER: pinned to its wall, it creeps toward the ship and fires one burst
	em.spawn(pring + 6, -1, "crawler")
	var cw: Dictionary = em.enemies.back()
	var cw_from: float = cw.ring_f
	cw.fire_t = 0.0
	roster_shots[0] = 0
	for f in 60:
		em.update_enemies(dt)
	var cw_ring: Dictionary = game.path.rings[cw.ring]
	assert(absf(absf((cw.node.position - cw_ring.p).dot(cw_ring.r)) - (cw_ring.hw - 1.6)) < 0.5)
	assert(cw.ring_f < cw_from and roster_shots[0] == 3)
	em.clear_all()
	game.shot_mgr.clear_all()
	# WARDEN: its front shield turns a light hit (NEUTRON, SCATTER, a stray bolt);
	# BOLT, the flank, the rear and any blast land
	em.spawn(pring + 4, -1, "warden")
	var wd: Dictionary = em.enemies.back()
	var wd_i := em.enemies.size() - 1
	assert(wd.shielded)
	wd.facing = -pfwd
	wd.hp = 40
	var wd_hp := 40
	var wd_turned := [0]
	var count_turned := func(_p: Vector3) -> void:
		wd_turned[0] += 1
	em.deflected.connect(count_turned)
	em.hit_enemy(wd_i, 1, pfwd)                      # head-on and light: turned
	em.hit_enemy(wd_i, 2, pfwd * 3.0 + pside)        # a POWER CORE pellet, a little off
	assert(wd.hp == wd_hp and wd_turned[0] == 2)
	em.hit_enemy(wd_i, 3, pfwd)                      # BOLT's 3 punches through
	assert(wd.hp == wd_hp - 3)
	em.hit_enemy(wd_i, 1, pside)                     # from the flank...
	em.hit_enemy(wd_i, 1, -pfwd)                     # ...from behind...
	em.hit_enemy(wd_i, 1)                            # ...a blast...
	em.splash_damage(wd.node.position, 10.0, 1)      # ...and missile splash all land
	assert(wd.hp == wd_hp - 7 and wd_turned[0] == 2)
	wd_hp = wd.hp
	wd.node.position = game.player.position + pfwd * 8.0
	game.shot_mgr.fire_player(game.weapons[0])       # a NEUTRON pair, head-on
	for f in 20:
		game.shot_mgr.update_shots(dt)
	assert(wd.hp == wd_hp and game.shot_mgr._pshots.is_empty())   # both stopped
	var wd_blue := 0
	for sp in game.shot_mgr._sparks:
		if sp.cell == ShotManager.SPARK_DODGE:
			wd_blue += 1
	assert(wd_blue >= 3)                             # blue sparks, and one ping
	GameState.weapon_index = 2
	game.shot_mgr.fire_player(game.weapons[2])       # BOLT
	for f in 20:
		game.shot_mgr.update_shots(dt)
	assert(wd.hp == wd_hp - 3)
	GameState.weapon_index = 0
	wd_hp = wd.hp
	var wd_stray := {"pos": wd.node.position, "vel": pfwd * 20.0, "src": null}
	assert(game.shot_mgr._infight(wd_stray) and wd.hp == wd_hp)   # infighting: turned too
	em.deflected.disconnect(count_turned)
	em.clear_all()
	game.shot_mgr.clear_all()
	# CARRIER: launches its own drones (CARRIER_LIVE at most) until its first BAY_HP of
	# damage blows the bays: a big blast and a line on the HUD
	em.spawn(pring + 6, -1, "carrier")
	var cr: Dictionary = em.enemies.back()
	cr.node.position = game.player.position + pfwd * 60.0
	assert(cr.bays)
	for tick in 5:
		cr.launch_t = 0.0
		em.update_enemies(dt)
	assert(em._count_tagged("parent", cr.node) == EnemyManager.CARRIER_LIVE)
	var cr_said: Array[String] = []
	var hear := func(text: String) -> void:
		cr_said.append(text)
	em.announced.connect(hear)
	em.hit_enemy(em.enemies.find(cr), EnemyManager.BAY_HP - 1)
	assert(cr.bays and cr_said.is_empty())
	em.hit_enemy(em.enemies.find(cr), 1)
	assert(not cr.bays and cr_said.size() == 1 and cr_said[0] == "CARRIER BAYS DOWN")
	assert(game.hud._msg.text == "CARRIER BAYS DOWN")
	em.announced.disconnect(hear)
	em.remove_where(func(en: Dictionary) -> bool: return en.get("parent") == cr.node)
	for tick in 3:
		cr.launch_t = 0.0
		em.update_enemies(dt)
	assert(em._count_tagged("parent", cr.node) == 0)   # the bays are gone: no launches
	em.clear_all()
	em.spawn(pring + 6, -1, "carrier")               # its drones are its own until it dies
	cr = em.enemies.back()
	cr.node.position = game.player.position + pfwd * 60.0
	cr.launch_t = 0.0
	em.update_enemies(dt)
	var cr_node: Node3D = cr.node
	assert(em._count_tagged("parent", cr_node) == 1)
	em.hit_enemy(em.enemies.find(cr), 999)
	assert(em._count_tagged("parent", cr_node) == 0)
	em.clear_all()
	game.shot_mgr.clear_all()
	# Heavies: the base type's sprite set (no bake rows of their own) with a tint folded
	# into the sector light, more hull, the same rule
	for hv_id in ["rammer_hv", "splitter_hv", "warden_hv"]:
		var hv_def: Dictionary = EnemyManager.TYPES[hv_id]
		var hv_base := EnemyManager.base_type(hv_id)
		assert(hv_base == hv_def.model and not SpriteModels.ENEMIES.has(hv_id))
		assert(EnemyManager.TYPES[hv_base].behavior == hv_def.behavior)
		em.spawn(pring + 5, -1, hv_base)
		var hv_b: Dictionary = em.enemies.back()
		em.spawn(pring + 5, -1, hv_id)
		var hv: Dictionary = em.enemies.back()
		assert(is_same(hv.skin, hv_b.skin) and hv.max_hp > hv_b.max_hp)
		assert(hv.tint == hv_def.tint and hv.node.modulate.is_equal_approx(em._lit(hv)))
		assert(not hv.node.modulate.is_equal_approx(em._light_for(hv.ring)))
		hv.lit_ring = -1                                 # the ring re-light keeps it
		em.update_enemies(dt)
		assert(hv.node.modulate.is_equal_approx(em._lit(hv)))
		assert(hv.shielded == (hv_base == "warden"))
		em.clear_all()
	em.spawn(pring + 3, -1, "splitter_hv")           # a heavy splitter: still 3 drones
	em.hit_enemy(em.enemies.size() - 1, 999)
	em.update_enemies(dt)
	assert(em.enemies.size() == 3)
	for hv_brood in em.enemies:
		assert(hv_brood.type == "drone")
	em.clear_all()
	em.spawn(pring + 6, -1, "rammer_hv")             # its flare clears back to its tint
	var hv_ram: Dictionary = em.enemies.back()
	hv_ram.node.position = game.player.position + pfwd * 60.0
	hv_ram.mode_t = 0.0
	for f in 90:
		em.update_enemies(dt)
		if hv_ram.mode == "charge":
			break
	assert(hv_ram.mode == "charge" and hv_ram.node.modulate.is_equal_approx(em._lit(hv_ram)))
	em.clear_all()
	game.shot_mgr.clear_all()
	em.enemy_fired.disconnect(count_roster_shots)
	GameState.shields = pw_full
	GameState.is_dead = was_dead
	for id in ["wraith", "crawler", "warden", "carrier", "rammer_hv", "splitter_hv", "warden_hv"]:
		assert(EnemyManager.POWER_DROP.has(id) and EnemyManager.TYPES[id].has("salvage"))
	# the gauntlet: wraith and crawler from tier 5, the rest of part 2 from tier 6
	game._apply_gauntlet_tier(4)
	assert(not "wraith" in game._gauntlet_def.enemy_types)
	assert(not "crawler" in game._gauntlet_def.enemy_types)
	game._apply_gauntlet_tier(5)
	assert("wraith" in game._gauntlet_def.enemy_types and "crawler" in game._gauntlet_def.enemy_types)
	for id in ["warden", "carrier", "rammer_hv", "splitter_hv", "warden_hv"]:
		assert(not id in game._gauntlet_def.enemy_types)
	game._apply_gauntlet_tier(0)
	# L7's and L8's newcomers: met alone in plain tunnel, in order, and never rolled
	# before their ring; a heavy waits for its base type's (L8's heavy warden), and the
	# other heavies don't wait at all
	for lvi in [6, 7]:
		var lvd: LevelDef = game.levels[lvi]
		var lv_path := PathGen.new()
		lv_path.generate(lvd.rings, lvd.level_seed, lvd.spawn_arena, false)
		game.path = lv_path
		var lv_plan: Dictionary = game._plan_intros(lvd)
		game.path = held_path
		var lv_first: String = lvd.intro_types[0]
		var lv_second: String = lvd.intro_types[1]
		assert(lv_plan.size() == 2 and lv_plan[lv_first] < lv_plan[lv_second])
		assert(lv_plan[lv_first] >= 21)
		for id in lv_plan:
			for r in range(lv_plan[id] - 4, lv_plan[id] + 5):
				assert(not lv_path.rings[r].arena)
		game._intro_rings = lv_plan
		var lv_early := {}
		for roll in 400:
			var early: String = game._pick_enemy_type(lvd, lv_plan[lv_first] - 1)
			lv_early[early] = true
			assert(EnemyManager.base_type(early) != lv_first)
			assert(EnemyManager.base_type(early) != lv_second)
		assert(lv_early.has("rammer_hv") and lv_early.has("splitter_hv"))
		var lv_seen := {}
		for roll in 800:
			lv_seen[game._pick_enemy_type(lvd, lv_plan[lv_second])] = true
		for id in lvd.enemy_types:
			assert(lv_seen.has(id))
		game._intro_rings = {}
	assert("warden_hv" in game.levels[7].enemy_types and "warden" in game.levels[7].intro_types)
	print("ROSTER2 ok — wraith cloak + shimmer (a steady fade under REDUCE FLASH), crawler on its wall, warden shield (light front hits turned; BOLT, flank, blasts land), carrier bays at BAY_HP + HUD line, heavies tinted on their base sets; L7/L8 intros + hold-back")
	# --- v4b SOAK: every type runs 10 s beside a fixed, immortal ship ---
	GameState.is_dead = false
	game.player.reset_to_start()
	var soak_at: Vector3 = game.player.position + game.player.forward() * 25.0
	for soak_id in EnemyManager.TYPES:
		em.clear_all()
		game.shot_mgr.clear_all()
		em.spawn(game.player.ring_idx + 2, -1, soak_id)
		var soak_e: Dictionary = em.enemies.back()
		soak_e.node.position = soak_at
		var soak_alive := 0
		for f in 600:
			GameState.shields = GameState.max_shields()
			em.update_enemies(dt)
			game.shot_mgr.update_shots(dt)
			game.shot_mgr.sync_batches()
			for en in em.enemies:
				if is_same(en, soak_e):
					soak_alive += 1
		assert(soak_alive > 0)
	em.clear_all()
	game.shot_mgr.clear_all()
	game.shot_mgr.sync_batches()
	GameState.shields = pw_full
	GameState.is_dead = was_dead
	print("SOAK ok — %d types ran 10 s beside the ship" % EnemyManager.TYPES.size())
	# --- V2.2 L2a: three phase-aligned music mixes on synced players ---
	var mix_a: AudioStream = MusicGen.render_loop(0)
	var mix_b: AudioStream = MusicGen.render_loop(2)
	assert(is_equal_approx(mix_a.get_length(), mix_b.get_length()))   # phase-aligned
	assert(AudioSys._music.size() == 3)   # three synced players
	# 3.0: the soundtrack renders a slice per frame — drive the job to the end and
	# every player must hold a stem of the same length (phase lock needs it)
	var music_slices := 0
	while AudioSys._music_job != null and music_slices < 2000:
		AudioSys._process(1.0 / 60.0)
		music_slices += 1
	assert(AudioSys._music_job == null)
	for mp in AudioSys._music:
		assert(mp.stream != null)
		assert(is_equal_approx(mp.stream.get_length(), mix_a.get_length()))
	assert(mix_a.get_length() > 20.0)   # eight phrases, not the old 7 s riff
	# stems reproduce the old full-mix crossfade: calm = base, combat = base +
	# combat layer, frenzy = everything, halfway blends in half a layer
	assert(AudioSys._stem_gains(AudioSys._mix_weights(0.0)) == Vector3(1, 0, 0))
	assert(AudioSys._stem_gains(AudioSys._mix_weights(1.0)) == Vector3(1, 1, 0))
	assert(AudioSys._stem_gains(AudioSys._mix_weights(2.0)) == Vector3(1, 1, 1))
	assert(AudioSys._stem_gains(AudioSys._mix_weights(1.5)).is_equal_approx(Vector3(1, 1, 0.5)))
	print("mixes ok — 3 phase-aligned music stems, %.1f s song, rendered in %d frame slices" % [
		mix_a.get_length(), music_slices])
	# --- V2.2 L2b: combat-intensity engine — boss forces frenzy, calm decays ---
	GameState.boss_active = true
	AudioSys._update_intensity(0.1, game.player.position)
	assert(AudioSys._intensity >= 2.0)   # boss forces FRENZY
	GameState.boss_active = false
	GameState.arena_locked = false
	GameState.combo = 0   # (the kill streak the roster and soak sections built up)
	game.shot_mgr.clear_all()
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
	# --- v4b: mini-bosses hold the kill-locked room nearest mid-sector (L2, L5, L8) ---
	var mb_em: EnemyManager = game.enemy_mgr
	for mb_li in [1, 4, 7]:
		GameState.reset_run()
		GameState.level_index = mb_li
		game._launch_level()
		await get_tree().process_frame
		var mb_lv: LevelDef = game.levels[mb_li]
		var mb_b: Dictionary = mb_em.boss
		assert(not mb_b.is_empty() and mb_b.miniboss and mb_b.model == mb_lv.miniboss_model)
		assert(mb_b.max_hp == mb_lv.miniboss_hp and not mb_b.engaged and mb_b.phase == 1)
		assert(not mb_em.boss_visible())                 # a surprise until it wakes
		assert(game.hud._boss_name.text == mb_lv.miniboss_name)
		var mb_mid: int = game.path.mid_arena()
		assert(mb_mid >= 0 and mb_mid == game._miniboss_arena and int(mb_b.arena_id) == mb_mid)
		var mb_room: Dictionary = game.path.arenas[mb_mid]
		var mb_half: int = game.path.main_ring_count / 2
		for a in game.path.arenas:
			if a.door_ring >= 0:
				assert(absi((a.start + a.end) / 2 - mb_half)
					>= absi((mb_room.start + mb_room.end) / 2 - mb_half))
		assert(int(mb_b.ring) >= int(mb_room.start) and int(mb_b.ring) <= int(mb_room.end))
		var mb_guards := 0                               # its guards trimmed to three...
		for en in mb_em.enemies:
			if not en.get("is_boss", false) and int(en.arena_id) == mb_mid:
				mb_guards += 1
		assert(mb_guards == mini(game.MINIBOSS_GUARDS, mb_room.spawn_rings.size()))
		assert(game._arena_spawned[mb_mid] == mb_guards + 1)   # ...and it counts for the door
	# L8's GATE WARDEN fights behind the WARDEN shield in phase 1
	assert(mb_em.boss.shielded and mb_em.boss.turn < 1.0)
	# L2's HAULER, start to finish: asleep until the ship is in its room...
	GameState.reset_run()
	GameState.level_index = 1
	game._launch_level()
	await get_tree().process_frame
	var hl: Dictionary = mb_em.boss
	var hl_room: Dictionary = game.path.arenas[game._miniboss_arena]
	var hl_woke: Array[String] = []
	var hear_wake := func(n: String) -> void:
		hl_woke.append(n)
	mb_em.miniboss_engaged.connect(hear_wake)
	var mb_shots := [0]
	var count_mb_shots := func(_o: Vector3, _v: Vector3, _d: float, _s: float, _k: bool,
			_src: Node3D) -> void:
		mb_shots[0] += 1
	mb_em.enemy_fired.connect(count_mb_shots)
	game.player.place_at_ring(int(hl_room.start) - 3)
	mb_em.update_enemies(dt)
	assert(not hl.engaged and hl_woke.is_empty())
	game.player.place_at_ring(int(hl_room.start) + 1)
	GameState.shields = pw_full
	mb_em.update_enemies(dt)
	assert(hl.engaged and hl_woke.size() == 1 and hl_woke[0] == "HAULER")
	assert(mb_em.boss_visible() and GameState.boss_active)
	assert(game.hud._msg.text == "WARNING · HAULER")
	assert(game.hud.boss_gates(hl) == [0.5])         # one phase tick, at 50%
	# ...it sows mines from the rack at its tail...
	var hl_mines := func() -> int:
		var n := 0
		for en in mb_em.enemies:
			if en.get("laid", false):
				n += 1
		return n
	hl.lay_t = 0.0
	mb_em.update_enemies(dt)
	assert(hl_mines.call() == 1)
	for en in mb_em.enemies:
		if en.get("laid", false):
			assert((en.node.position - hl.node.position).dot(hl.facing) < 0.0)   # behind it
	# ...and at 50% it turns (one phase change, its line) and calls escort drones
	var mb_phases: Array[int] = []
	var hear_phase := func(p: int) -> void:
		mb_phases.append(p)
	mb_em.boss_phase.connect(hear_phase)
	hl.hp = int(hl.max_hp * 0.6)
	mb_em.update_enemies(dt)
	assert(mb_phases.is_empty())
	hl.hp = int(hl.max_hp * 0.5)
	hl.summon_t = 0.0
	mb_em.update_enemies(dt)
	assert(mb_phases.size() == 1 and mb_phases[0] == 2 and hl.phase == 2)
	assert(game.hud._msg.text == "ESCORTS INBOUND — STAY MOBILE")
	var hl_escorts := 0
	for en in mb_em.enemies:
		if en.get("summoned", false):
			hl_escorts += 1
	assert(hl_escorts == 2)
	# it never leaves its room, and it falls like a boss but opens only its bulkhead:
	# miniboss_killed, never boss_killed (the exit is none of its business)
	for f in 120:
		GameState.shields = pw_full
		mb_em.update_enemies(dt)
		assert(int(hl.ring) > int(hl_room.start) and int(hl.ring) < int(hl_room.end))
	var hl_boss_deaths := [0]
	var hear_boss := func() -> void:
		hl_boss_deaths[0] += 1
	mb_em.boss_killed.connect(hear_boss)
	for k in range(mb_em.enemies.size() - 1, -1, -1):   # its guards first...
		var en: Dictionary = mb_em.enemies[k]
		if not en.get("is_boss", false) and int(en.arena_id) == int(hl_room.id):
			mb_em.hit_enemy(k, 999)
	assert(not game.world.is_door_open(hl_room.id))   # ...the door still waits for it
	var hl_score := GameState.score
	GameState.difficulty = 1
	GameState.clear_checkpoint()
	mb_em.hit_enemy(mb_em.enemies.find(hl), 9999)
	assert(mb_em.boss.is_empty() and game._miniboss_down and not GameState.boss_active)
	assert(game.world.is_door_open(hl_room.id) and hl_boss_deaths[0] == 0)
	assert(GameState.score > hl_score)
	assert(game.hud._msg.text == "HAULER DESTROYED · BULKHEAD OPEN")
	mb_em.boss_killed.disconnect(hear_boss)
	mb_em.boss_phase.disconnect(hear_phase)
	# the bulkhead's checkpoint knows it fell, so a resume past it doesn't bring it back
	var hl_cp := GameState.load_checkpoint(game.levels.size())
	assert(int(hl_cp.ring) == int(hl_room.door_ring) + 2 and bool(hl_cp.miniboss_down))
	game._begin_resume(hl_cp)
	game._on_launch()
	await get_tree().process_frame
	assert(game.state == game.State.PLAYING and game._miniboss_down)
	assert(mb_em.boss.is_empty() and game.world.is_door_open(hl_room.id))
	for en in mb_em.enemies:
		assert(not en.get("is_boss", false))
	# a checkpoint from before it fell brings it back, asleep
	var hl_early := GameState.save_checkpoint(game._checkpoint_data(int(hl_room.start) - 6, []))
	hl_early.miniboss_down = false
	GameState.save_checkpoint(hl_early)
	game._begin_resume(GameState.load_checkpoint(game.levels.size()))
	game._on_launch()
	await get_tree().process_frame
	assert(not mb_em.boss.is_empty() and mb_em.boss.miniboss and not mb_em.boss.engaged)
	assert(not game._miniboss_down)
	mb_em.miniboss_engaged.disconnect(hear_wake)
	# SPORE TENDER: rings of spores, a repair pulse on its escorts (green sparks), and
	# SPLITTER hatchlings from 50%
	mb_em.clear_all()
	game.shot_mgr.clear_all()
	game.player.place_at_ring(int(hl_room.start) + 1)
	mb_em.spawn_miniboss(hl_room, game.levels[4])
	var tn: Dictionary = mb_em.boss
	tn.engaged = true
	mb_em.spawn(int(hl_room.start) + 4, int(hl_room.id), "drone")
	var tn_esc: Dictionary = mb_em.enemies.back()
	tn_esc.node.position = tn.node.position + Vector3(10, 0, 0)
	tn_esc.max_hp = 5
	tn_esc.hp = 3
	tn_esc.fire_t = 99.0
	var tn_mends := [0]
	var count_tn := func(_p: Vector3) -> void:
		tn_mends[0] += 1
	mb_em.mended.connect(count_tn)
	tn.pulse_t = 0.0
	tn.volley_t = 0.0
	tn.fire_t = 99.0
	mb_shots[0] = 0
	mb_em.update_enemies(dt)
	assert(tn_esc.hp == 4 and tn_mends[0] == 1 and mb_shots[0] == 6)   # +1, and a six-spore ring
	tn.hp = tn.max_hp / 2
	tn.summon_t = 0.0
	mb_em.update_enemies(dt)
	var tn_hatch := 0
	for en in mb_em.enemies:
		if en.get("summoned", false) and en.type == "splitter":
			tn_hatch += 1
	assert(tn.phase == 2 and tn_hatch == 1)
	mb_em.mended.disconnect(count_tn)
	# GATE WARDEN: phase 1 turns light front hits (BOLT lands) and launches drones; at
	# 50% the shield fails, its hull runs hot, and the spiral hose starts
	mb_em.clear_all()
	game.shot_mgr.clear_all()
	mb_em.spawn_miniboss(hl_room, game.levels[7])
	var gw: Dictionary = mb_em.boss
	gw.engaged = true
	gw.fire_t = 99.0
	var gw_fwd: Vector3 = game.player.forward()
	gw.facing = -gw_fwd
	var gw_hp: int = gw.hp
	mb_em.hit_enemy(mb_em.enemies.find(gw), 1, gw_fwd)
	assert(gw.hp == gw_hp)
	mb_em.hit_enemy(mb_em.enemies.find(gw), 3, gw_fwd)
	assert(gw.hp == gw_hp - 3)
	gw.summon_t = 0.0
	mb_em.update_enemies(dt)
	var gw_bay := 0
	for en in mb_em.enemies:
		if en.get("summoned", false):
			gw_bay += 1
	assert(gw_bay == 2)
	gw.hp = gw.max_hp / 2
	mb_em.update_enemies(dt)
	assert(gw.phase == 2 and not gw.shielded and gw.tint == EnemyManager.GATEWARDEN_BARE_TINT)
	assert(game.hud._msg.text == "SHIELD DOWN — OPEN FIRE")
	gw_hp = gw.hp
	gw.facing = -gw_fwd
	mb_em.hit_enemy(mb_em.enemies.find(gw), 1, gw_fwd)
	assert(gw.hp == gw_hp - 1)                       # nothing turns it now
	gw.spiral_t = 1.0
	gw.spiral_cd = 0.0
	gw.summon_t = 99.0
	mb_shots[0] = 0
	for f in 30:
		mb_em.update_enemies(dt)
	assert(mb_shots[0] >= 4)                         # ~0.5 s of the hose at 0.13 s a step
	mb_em.enemy_fired.disconnect(count_mb_shots)
	mb_em.clear_all()
	game.shot_mgr.clear_all()
	GameState.shields = pw_full
	GameState.boss_active = false
	print("MINIBOSS ok — L2/L5/L8 mid rooms (3 guards + it), asleep till entered, 2 phases, hauler mines/escorts, tender spores/repairs/splitters, gate warden shield/bays/spiral, bulkhead not portal, checkpoint keeps it down")
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
	# 3.0: the enemy tips grew some briefings — every level's body must still fit
	for bidx in game.levels.size():
		game.overlays.set_briefing(game.levels[bidx])
		await get_tree().process_frame
		assert(lore_b.get_line_count() <= 3)
	game.overlays.set_briefing(game.levels[4])
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
			"reduce_flash", "reduce_roll", "invert_y", "dpad"]:
		assert(game.overlays._settings_labels.has(k))
	# and none of its controls escapes the 320x200 design box.
	# M4c final review: this used to be a top-left-only `position.y <= 190` check,
	# which is what let the BACK button ship visibly clipped — a plain (non-_compact)
	# Button is ~20 units tall, so a y of 188 passed the old assert while painting
	# 8 units past the canvas floor. Check the FULL rect against the FULL canvas,
	# the same way the touch-controls geometry guard further down already does.
	# get_rect() ignores Control.scale, and overlays.gd's _line() helper paints at
	# 2x size scaled 0.5 — no such label is on this panel today, but measuring the
	# painted rect (size * scale) keeps this honest if one is ever added.
	var design_box := Rect2(Vector2.ZERO, Vector2(320, 200))
	for child in set_p.get_children():
		if child is Button or child is Label:
			var c := child as Control
			assert(design_box.encloses(Rect2(c.position, c.size * c.scale)))
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
	# ...and holds animated arena lights steady instead of strobing them (3.0: the
	# arena mood lamps are LightRig statics, animated in commit())
	game.light_rig.add_static(Vector3.ZERO, Color.WHITE, 0.9, 60.0, "strobe", 0.3)
	game.light_rig.add_static(Vector3.ZERO, Color.WHITE, 0.9, 60.0, "flicker", 1.7)
	for _k in 6:
		game.light_rig.begin(game.player.position)
		game.light_rig.commit(0.13)
		for lamp in game.light_rig.statics():
			assert(is_equal_approx(lamp.live, lamp.energy))
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
	# M4c final review: the GYRO AIM settings row was REMOVED. Godot 4.7's web
	# export ships no device-orientation/-motion listener, so Input.get_gyroscope()
	# is permanently ZERO in a browser and web is this game's only mobile delivery —
	# the control persisted a setting, fired an iOS permission prompt, and then did
	# nothing. Assert it stays gone rather than leaving a hole where it was.
	assert(not game.overlays._settings_labels.has("gyro"))
	for child in set_p.get_children():
		if child is Label:
			assert((child as Label).text != "GYRO AIM")
	# The FIELD and its persistence stay as dormant scaffolding for a future session
	# that writes a real JS orientation bridge, so keep covering them: it defaults
	# off, round-trips through settings.cfg, and — critically — nothing in the
	# shipped UI can ever set it true now.
	assert(GameState.gyro_aim_enabled == false)   # default off
	GameState.gyro_aim_enabled = true
	GameState.apply_settings()
	GameState.gyro_aim_enabled = false
	GameState.load_settings()
	assert(GameState.gyro_aim_enabled == true)    # persisted round-trip
	GameState.gyro_aim_enabled = false
	GameState.apply_settings()                    # restore the shipped default
	# Headless has no real gyroscope (Input.get_gyroscope() is always ZERO here) —
	# and neither does the web build, which is the whole reason the UI is gone. What
	# IS verifiable here: player.gd's dormant gyro block runs without error both off
	# and on, and is a harmless no-op given a zero sensor reading. delta=0.0 isolates
	# the gyro term from every other per-frame effect (movement, energy, collision),
	# so yaw/pitch must come back exactly as they went in either way.
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
	print("gyro ok — settings row removed (inert on web); field still round-trips and "
		+ "update_flight()'s dormant path is a no-op with no real sensor")
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
	# M1.5: the sector arrows sit clear of the longest sector label. The label is
	# centred across the 320 px canvas, so its painted span is measured from the
	# text width (times the label's scale), not the node's box.
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
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * game.overlays._sector_label.scale.x
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
	# re-audit Step 5: the key rows live on the manual's keys page
	for child in help_p.get_children() + game.overlays._help_keys.get_children():
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
	for child in (game.overlays._panels.help as Control).get_children() \
			+ game.overlays._help_keys.get_children():
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
	# M4c final review: _dpad_root joins this check — it is this branch's new
	# geometry and was never covered by it.
	for c in [touch._fire_btn, touch._bomb_btn, touch._weapon_btn, touch._dpad_root]:
		assert(Rect2(Vector2.ZERO, Vector2(320, 200)).encloses(c.get_global_rect()))
	for btn in [touch._fire_btn, touch._bomb_btn, touch._weapon_btn]:
		assert(btn.get_global_rect().position.x > 320.0 * TouchControls.LEFT_ZONE_FRAC)
	# ...and the D-pad's rect must sit wholly INSIDE the left steering zone, since
	# _on_touch() now narrows D-pad steering ownership from the zone to this rect:
	# a pad overlapping the button side would make that narrowing unsound.
	assert(touch._dpad_root.get_global_rect().end.x <= 320.0 * TouchControls.LEFT_ZONE_FRAC)
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
	# M4c final review #1: a FIXED pad has to be visible before anyone touches it.
	# It used to be shown from the press handler, so it was invisible until the
	# player had already guessed where it was. Visibility is now derived in
	# _process() from the setting alone — prove it with no touch at all, and prove
	# the two steering UIs stay mutually exclusive.
	assert(not touch._dpad_root.visible)   # setting was off until the line above
	touch._process(0.016)
	assert(touch._dpad_root.visible)
	assert(not touch._stick_ring.visible)
	var dpad_up_pos: Vector2 = touch._dpad_up.get_global_rect().get_center()
	var dpad_right_pos: Vector2 = touch._dpad_right.get_global_rect().get_center()
	# M4c final review #2: a left-zone touch OUTSIDE the pad's own rect must not
	# claim steering. It used to, and then blocked every real D-pad press until
	# that finger lifted. Uses a y well above the bottom-left pad box.
	var off_pad := Vector2(vp_w * 0.35, 30.0)
	assert(not touch._dpad_root.get_global_rect().has_point(off_pad))
	var off_down := InputEventScreenTouch.new()
	off_down.index = 11
	off_down.position = off_pad
	off_down.pressed = true
	touch._input(off_down)
	assert(touch._steer_touch == -1)       # not claimed — the pad is still free
	var off_up := InputEventScreenTouch.new()
	off_up.index = 11
	off_up.position = off_pad
	off_up.pressed = false
	touch._input(off_up)
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
	# M4c final review #3: the D-pad must be able to produce a TRUE DIAGONAL. It
	# could not — the four cells were hit-tested as rects laid out in a strict cross
	# that share only corner points, so the directions were geometrically mutually
	# exclusive and yaw+pitch together was unreachable. Every other steering input in
	# this game (keyboard, stick, gamepad) combines both axes, and this is a winding-
	# corridor flight game. Hit-testing is now axis thresholds from the pad's centre.
	# Drag into the up-left quadrant of the pad's rect and demand BOTH actions.
	var dpad_rect := touch._dpad_root.get_global_rect()
	var diag_pos := dpad_rect.position + dpad_rect.size * 0.25   # up-left quadrant
	var dp_diag := InputEventScreenDrag.new()
	dp_diag.index = 6
	dp_diag.position = diag_pos
	touch._input(dp_diag)
	assert(is_equal_approx(Input.get_action_strength("steer_up"), 1.0))
	assert(is_equal_approx(Input.get_action_strength("steer_left"), 1.0))
	assert(Input.get_action_strength("steer_down") == 0.0)
	assert(Input.get_action_strength("steer_right") == 0.0)
	# ...and the pad's centre is still a neutral dead zone, so a diagonal is a
	# deliberate reach rather than the whole pad reading as "some direction".
	var dp_centre := InputEventScreenDrag.new()
	dp_centre.index = 6
	dp_centre.position = dpad_rect.get_center()
	touch._input(dp_centre)
	for act in ["steer_up", "steer_down", "steer_left", "steer_right"]:
		assert(Input.get_action_strength(act) == 0.0)
	# back onto a diagonal so the release below has something to clear
	touch._input(dp_diag)
	var dp_up := InputEventScreenTouch.new()
	dp_up.index = 6
	dp_up.position = diag_pos
	dp_up.pressed = false
	touch._input(dp_up)
	for act in ["steer_up", "steer_down", "steer_left", "steer_right"]:
		assert(Input.get_action_strength(act) == 0.0)
	assert(touch._steer_touch == -1)
	# the fixed pad stays on screen after the finger lifts — hiding it here used to
	# blink it out for a frame on every release
	assert(touch._dpad_root.visible)
	print("M4c ok — D-pad drag from \"up\" into \"right\" swaps steer_up/steer_right in one call, "
		+ "up-left quadrant holds steer_up AND steer_left together, centre is a dead zone, "
		+ "releases cleanly, pad stays visible, default (stick) path above is unchanged")
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
	assert(touch._steer_touch == -1)   # a boost tap outside the pad never owns steering
	assert(touch._dpad_root.visible)   # ...and never hides the fixed pad either
	# turning the setting off is the ONE thing that takes the pad off screen
	GameState.touch_dpad_enabled = false
	touch._process(0.016)
	assert(not touch._dpad_root.visible)
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
	# --- Task 4 (M4c/M4d plan): end-of-session install nudge (D11) ---
	# _install_button() guards on OS.has_feature("web"), which is always false here
	# (headless and every desktop editor run), so the button node is never even
	# constructed and JavaScriptBridge — which doesn't exist off the web export — is
	# never touched. The three panels that call it (_build_start/_build_game_over/
	# _build_victory) already built successfully as part of booting `game` above; a
	# headless run reaching this line with no SCRIPT ERROR *is* the test for that
	# guard. There's nothing to assert against a feature that is correctly,
	# unconditionally absent here — so instead assert the button genuinely rendered
	# nowhere, since a stray one slipping past the guard would be an actual bug.
	# review fix: availability used to be decided once at panel-construction time,
	# which could permanently miss a beforeinstallprompt that fires after Overlays
	# boots. show_only() now re-checks live via _refresh_install_buttons() every time
	# the start/game_over/victory panel is shown — but that path is *also* gated on
	# OS.has_feature("web") (_install_buttons stays empty off the web, so the
	# refresh early-returns without ever calling JavaScriptBridge), so it remains
	# exactly as untestable headless as the original check was, for the same reason.
	assert(game.overlays._install_buttons.is_empty())   # never constructed off the web
	game.overlays._refresh_install_buttons()   # must be a safe no-op (early-returns on the empty array, before touching JavaScriptBridge)
	for panel_name in ["start", "game_over", "victory"]:
		var install_seen := 0
		for child in (game.overlays._panels[panel_name] as Control).get_children():
			if child is Button and (child as Button).text == "INSTALL APP":
				install_seen += 1
		assert(install_seen == 0)
	# show_only() now calls _refresh_install_buttons() too (review fix) — exercise that
	# real call path, not just the standalone function, and confirm it's still a no-op
	game.overlays.show_only("start")
	assert(game.overlays._install_buttons.is_empty())
	print("D11 ok — install nudge is a no-op off the web build (OS.has_feature(\"web\") == false)")
	# --- re-audit Step 2: a real pause menu, a touch pause tab, pause on focus loss,
	# and QUIT TO TITLE back to a title screen as clean as a fresh boot
	GameState.reset_run()
	GameState.level_index = 0
	game._launch_level()
	await get_tree().process_frame
	assert(game.state == game.State.PLAYING)
	var pause_panel := game.overlays._panels["pause"] as Control
	var pause_rows := {}
	for child in pause_panel.get_children():
		if child is Button:
			pause_rows[(child as Button).text] = child
	for want in ["> RESUME", "FLIGHT MANUAL", "SETTINGS", "QUIT TO TITLE"]:
		assert(pause_rows.has(want))
	assert(pause_panel.mouse_filter == Control.MOUSE_FILTER_STOP)   # swallows stray clicks
	# losing focus pauses; more focus events (or coming back) never resume by themselves
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(game.state == game.State.PAUSED and pause_panel.visible)
	game.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(game.state == game.State.PAUSED)
	# a click that reaches the game no longer resumes either
	var stray := InputEventMouseButton.new()
	stray.button_index = MOUSE_BUTTON_LEFT
	stray.pressed = true
	game._unhandled_input(stray)
	assert(game.state == game.State.PAUSED)
	# the manual opened from pause offers no START, and BACK returns to pause
	(pause_rows["FLIGHT MANUAL"] as Button).pressed.emit()
	assert((game.overlays._panels["help"] as Control).visible)
	assert(not game.overlays._help_start.visible)
	game.overlays._help_back.pressed.emit()
	assert(pause_panel.visible)
	# ...and so does SETTINGS
	(pause_rows["SETTINGS"] as Button).pressed.emit()
	assert((game.overlays._panels["settings"] as Control).visible)
	(game.overlays._focus["settings"] as Button).pressed.emit()
	assert(pause_panel.visible)
	(pause_rows["> RESUME"] as Button).pressed.emit()
	assert(game.state == game.State.PLAYING)
	# touch: the II tab sits inside the canvas, clear of every other control, and a
	# tap on it pauses without claiming the steering or fire finger
	var ptouch := TouchControls.new()
	add_child(ptouch)
	ptouch.enable(game.player)
	await get_tree().process_frame
	var tab: Rect2 = ptouch._pause_btn.get_global_rect()
	assert(Rect2(Vector2.ZERO, Vector2(320, 200)).encloses(tab))
	assert(tab.position.x > 320.0 * TouchControls.LEFT_ZONE_FRAC)
	for c in [ptouch._fire_btn, ptouch._bomb_btn, ptouch._weapon_btn]:
		assert(not tab.intersects(c.get_global_rect()))
	var tab_paused := [false]
	ptouch.pause_tapped.connect(func() -> void: tab_paused[0] = true)
	var tab_tap := InputEventScreenTouch.new()
	tab_tap.index = 0
	tab_tap.position = tab.get_center()
	tab_tap.pressed = true
	ptouch._input(tab_tap)
	assert(tab_paused[0])
	assert(ptouch._steer_touch < 0 and ptouch._fire_touch < 0)
	ptouch.set_flight_active(false)
	ptouch.queue_free()
	# QUIT TO TITLE: the first press only arms it, the second quits the run
	GameState.weapon_marks = [2, 1, 0, 0]
	GameState.shields = 20.0
	game._toggle_pause()
	assert(game.state == game.State.PAUSED)
	game.overlays._quit_btn.pressed.emit()
	assert(game.state == game.State.PAUSED)
	assert(game.overlays._quit_btn.text != "QUIT TO TITLE")   # asking again
	game._toggle_pause()   # resume and re-pause: the arming doesn't survive
	game._toggle_pause()
	assert(game.overlays._quit_btn.text == "QUIT TO TITLE")
	game.overlays._quit_btn.pressed.emit()
	game.overlays._quit_btn.pressed.emit()
	assert(game.state == game.State.MENU)
	assert((game.overlays._panels["start"] as Control).visible)
	assert(GameState.weapon_marks == [0, 0, 0, 0])            # a new run starts clean
	assert(GameState.shields == GameState.max_shields())
	assert(GameState.level_index == 0 and game._built_level == 0)
	assert(not game.player.active)
	# ...and the title still launches a campaign from there
	game.overlays._sector = 0
	game._on_launch()   # MENU -> BRIEFING
	assert(game.state == game.State.BRIEFING)
	for f in 20:
		game._process(1.0 / 60.0)
	game._on_launch()   # BRIEFING -> PLAYING
	await get_tree().process_frame
	assert(game.state == game.State.PLAYING)
	print("PAUSE ok — menu rows, focus-loss pause, touch II tab, armed quit to a clean title")
	# --- re-audit Step 3 (M5b): difficulty presets + assists reach their sinks ---
	GameState.difficulty = 1
	GameState.assist_damage = 0
	GameState.assist_speed = 0
	for v in [GameState.enemy_tempo(), GameState.enemy_shot_speed(), GameState.warn_mult(),
			GameState.pickup_mult(), GameState.damage_taken_mult(), GameState.flight_time_scale()]:
		assert(is_equal_approx(v, 1.0))
	GameState.clear_powers()
	for d in GameState.DIFFICULTY_NAMES.size():
		GameState.difficulty = d
		# damage taken: every hit funnels through take_damage
		game.player.iframes_t = 0.0
		GameState.shields = GameState.max_shields()
		game.player.take_damage(10.0, "TEST")
		assert(is_equal_approx(GameState.shields,
			GameState.max_shields() - 10.0 * GameState.DIFF_DAMAGE[d]))
		# enemy shot speed: every enemy/boss bolt funnels through fire_enemy
		game.shot_mgr.clear_all()
		game.shot_mgr.fire_enemy(game.player.position + Vector3(0, 0, -30), Vector3(0, 0, 10))
		var bolt: Dictionary = game.shot_mgr._eshots.back()
		assert(is_equal_approx((bolt.vel as Vector3).length(), 10.0 * GameState.DIFF_SHOT_SPEED[d]))
		game.shot_mgr.clear_all()
		# pickup value: shield cells restore more on RECRUIT, less on VOIDBORNE
		GameState.shields = 40.0
		game.pickup_mgr._collect("shield")
		assert(is_equal_approx(GameState.shields, 40.0 + 20.0 * GameState.DIFF_PICKUP[d]))
	# warning time: a mine's fuse on VOIDBORNE is shorter than on RUNNER
	GameState.difficulty = 2
	var mine_ring := mini(game.player.ring_idx + 3, game.path.rings.size() - 1)
	var before_mines: int = game.enemy_mgr.enemies.size()
	game.enemy_mgr.spawn(mine_ring, -1, "mine")
	assert(game.enemy_mgr.enemies.size() == before_mines + 1)
	var dmine: Dictionary = game.enemy_mgr.enemies.back()
	(dmine.node as Node3D).position = game.player.position + game.player.forward() * 4.0
	game.enemy_mgr.update_enemies(0.0)
	assert(dmine.mode == "armed")
	assert(is_equal_approx(dmine.mode_t, EnemyManager.MINE_FUSE * 0.8))
	game.enemy_mgr.clear_all()
	# the damage assist stacks with the preset
	GameState.difficulty = 0
	GameState.assist_damage = 2
	assert(is_equal_approx(GameState.damage_taken_mult(), 0.6 * 0.5))
	# game speed: a base time scale in flight that hit-stop and pause respect
	GameState.assist_damage = 0
	GameState.assist_speed = 1
	game._set_flight_time(true)
	assert(is_equal_approx(Engine.time_scale, 0.85))
	game.gib_mgr.hit_stop(1, 0.1, true)
	assert(is_equal_approx(Engine.time_scale, 0.1))
	game.gib_mgr._stop_restore_ms = 1   # due now
	game.gib_mgr._process(0.0)
	assert(is_equal_approx(Engine.time_scale, 0.85))   # back to the assist, not 1.0
	game._toggle_pause()
	assert(is_equal_approx(Engine.time_scale, 1.0))    # menus at real speed
	game._toggle_pause()
	assert(is_equal_approx(Engine.time_scale, 0.85))
	# settings round trip + clamping
	GameState.difficulty = 2
	GameState.assist_damage = 1
	GameState.assist_speed = 2
	GameState._save_settings()
	GameState.difficulty = 1
	GameState.assist_damage = 0
	GameState.assist_speed = 0
	GameState.load_settings()
	assert(GameState.difficulty == 2 and GameState.assist_damage == 1 and GameState.assist_speed == 2)
	var bad := ConfigFile.new()
	bad.load("user://settings.cfg")
	bad.set_value("settings", "difficulty", 9)
	bad.set_value("settings", "assist_dmg", -4)
	bad.save("user://settings.cfg")
	GameState.load_settings()
	assert(GameState.difficulty == 2 and GameState.assist_damage == 0)
	# UI: the panel opens from pause, steps presets, and BACK returns to pause
	game._toggle_pause()
	var prow := {}
	for child in (game.overlays._panels["pause"] as Control).get_children():
		if child is Button:
			prow[(child as Button).text] = child
	assert(prow.has("DIFFICULTY"))
	(prow["DIFFICULTY"] as Button).pressed.emit()
	assert((game.overlays._panels["difficulty"] as Control).visible)
	game.overlays._adjust_setting("difficulty", -1)
	assert((game.overlays._settings_labels["difficulty"] as Label).text == "RUNNER")
	game.overlays._adjust_setting("difficulty", -5)
	assert(GameState.difficulty == 0)
	assert((game.overlays._settings_labels["difficulty"] as Label).text == "RECRUIT")
	(game.overlays._focus["difficulty"] as Button).pressed.emit()
	assert((game.overlays._panels["pause"] as Control).visible)
	var go_rows := []
	for child in (game.overlays._panels["game_over"] as Control).get_children():
		if child is Button:
			go_rows.append((child as Button).text)
	assert("DIFFICULTY" in go_rows)
	game.overlays._refresh_start()
	assert(game.overlays._difficulty_btn.text == "DIFFICULTY: RECRUIT")
	game.overlays.set_final_score("game_over", 1234)
	assert(((game.overlays._panels["game_over"] as Control).get_node("Score") as Label).text \
		== "SCORE 1234 · RECRUIT")
	# back to the defaults for everything after this
	GameState.difficulty = 1
	GameState.assist_damage = 0
	GameState.assist_speed = 0
	GameState.apply_settings()
	game._toggle_pause()
	assert(game.state == game.State.PLAYING and is_equal_approx(Engine.time_scale, 1.0))
	print("DIFFICULTY ok — presets + assists reach damage/shots/pickups/fuse/time scale, saved, UI rows")
	# --- re-audit Step 4 (M5c): checkpoints — storage, save points, resume, UI ---
	var lc: int = game.levels.size()
	GameState.clear_checkpoint()
	assert(GameState.load_checkpoint(lc).is_empty())
	var stamped := GameState.save_checkpoint(game._checkpoint_data(5, [0]))
	var cp_back := GameState.load_checkpoint(lc)
	assert(not cp_back.is_empty() and int(cp_back.ring) == 5 and cp_back.cleared_arenas == [0])
	assert(int(cp_back.level_index) == GameState.level_index)
	assert(int(cp_back.score) == GameState.score)
	# a corrupt file and an out-of-range sector are ignored, never fatal
	var corrupt := FileAccess.open(GameState.CHECKPOINT_PATH, FileAccess.WRITE)
	corrupt.store_string("this is [not a config")
	corrupt.close()
	assert(GameState.load_checkpoint(lc).is_empty())
	var oor: Dictionary = stamped.duplicate(true)
	oor.level_index = 99
	assert(GameState.normalize_checkpoint(oor, lc).is_empty())
	# the newer of the two copies wins; the localStorage copy round-trips JSON floats
	var older := GameState.normalize_checkpoint(stamped, lc)
	var newer: Dictionary = older.duplicate(true)
	newer.saved_at = float(older.saved_at) + 10.0
	newer.ring = 9
	assert(int(GameState.pick_checkpoint(older, newer).ring) == 9)
	assert(int(GameState.pick_checkpoint(newer, older).ring) == 9)
	assert(int(GameState.pick_checkpoint({}, older).ring) == 5)
	var via_json: Dictionary = JSON.parse_string(JSON.stringify(stamped))
	var nj := GameState.normalize_checkpoint(via_json, lc)
	assert(typeof(nj.level_index) == TYPE_INT and int(nj.ring) == 5)
	# save points: a cleared bulkhead saves on RUNNER, not on VOIDBORNE
	GameState.clear_checkpoint()
	game._checkpoint = {}
	var doors: Array = []
	for a in game.path.arenas:
		if a.door_ring >= 0 and not game.world.is_door_open(a.id) \
				and int(game._arena_spawned.get(a.id, 0)) > 0:
			doors.append(a)
	assert(doors.size() >= 2)
	GameState.difficulty = 1
	var arena0: Dictionary = doors[0]
	for k in int(game._arena_spawned[arena0.id]) - int(game._arena_kills.get(arena0.id, 0)):
		game._on_enemy_killed(arena0.id)
	assert(game.world.is_door_open(arena0.id))
	var mid := GameState.load_checkpoint(lc)
	assert(int(mid.ring) == int(arena0.door_ring) + 2 and int(arena0.id) in mid.cleared_arenas)
	assert(game._has_mid_checkpoint())
	GameState.difficulty = 2
	var arena1: Dictionary = doors[1]
	for k in int(game._arena_spawned[arena1.id]) - int(game._arena_kills.get(arena1.id, 0)):
		game._on_enemy_killed(arena1.id)
	assert(game.world.is_door_open(arena1.id))
	assert(int(GameState.load_checkpoint(lc).ring) == int(arena0.door_ring) + 2)   # untouched
	GameState.difficulty = 1
	# resume: the ship on the checkpoint ring, cleared doors open and their guards gone,
	# nothing spawned behind, the run's numbers back
	GameState.score = 4321
	GameState.level_kills = 17
	var saved_cp := GameState.save_checkpoint(game._checkpoint_data(int(mid.ring), [arena0.id]))
	GameState.score = 0
	GameState.level_kills = 0
	game._begin_resume(GameState.load_checkpoint(lc))
	assert(game.state == game.State.BRIEFING)
	assert(game.overlays._briefing_launch.text == "> RESUME")
	game._on_launch()
	await get_tree().process_frame
	assert(game.state == game.State.PLAYING)
	var rr: int = int(saved_cp.ring)
	assert(game.player.ring_idx == rr)
	assert(not game._intros_live)   # v4b: no solo first contacts on a resume
	var rring: Dictionary = game.path.rings[rr]
	assert(game.player.position.distance_to(rring.p) < 1.5)   # one frame of flight since the launch
	assert(game.player.forward().dot(rring.d) > 0.97)
	assert(game.world.is_door_open(arena0.id))
	for e in game.enemy_mgr.enemies:
		assert(int(e.arena_id) != int(arena0.id))
		assert(not (int(e.arena_id) == -1 and int(e.ring) < rr))
	assert(GameState.score == 4321 and GameState.level_kills == 17)
	assert(int(GameState.load_checkpoint(lc).ring) == rr)   # a resume doesn't re-save ring 1
	assert(game.overlays._briefing_launch.text == "> LAUNCH")
	# game over offers the checkpoint first, then a full restart
	game.overlays.set_retry_options(true)
	assert(game.overlays._go_retry.text == "@ RETRY FROM CHECKPOINT" and game.overlays._go_restart.visible)
	game.overlays.set_retry_options(false)
	assert(game.overlays._go_retry.text == "@ RETRY LEVEL" and not game.overlays._go_restart.visible)
	# the title's CONTINUE row follows the save
	game._refresh_continue()
	assert(not game.overlays._continue_btn.disabled)
	assert(game.overlays._continue_btn.text.begins_with("CONTINUE · L1"))
	# a sector clear saves the next sector's start; the campaign's end clears it
	game._level_complete()
	var next_cp := GameState.load_checkpoint(lc)
	assert(int(next_cp.level_index) == 1 and int(next_cp.ring) == 1)
	assert(int(next_cp.level_start_score) == GameState.score)
	GameState.level_index = lc - 1
	game._level_complete()
	assert(GameState.load_checkpoint(lc).is_empty())
	assert(game.overlays._continue_btn.disabled)
	print("CHECKPOINT ok — round trip, corrupt/oor ignored, newer wins, bulkhead saves, resume, UI")
	# --- re-audit Step 5 (M5d): the first 90 seconds — callouts, first contact, manual ---
	GameState.seen_flight_tips = false
	GameState.reset_run()
	game._gauntlet = false
	GameState.gauntlet_mode = false
	game._resume = {}
	game._built_level = -1
	game._launch_level()   # sector 1 straight from code: builds the world, starts the tips
	assert(game.state == game.State.PLAYING)
	assert(game._intros_live)   # v4b: a fresh start meets its newcomers alone
	var first_contact := false
	for e in game.enemy_mgr.enemies:
		if int(e.arena_id) == -1 and e.type == "drone" and int(e.ring) == 12:
			first_contact = true
	assert(first_contact)   # the guaranteed sector-1 drone
	assert(game._tips_on and game._tip_stage == game.TIP_STEER)
	game._update_tips(1.6)
	assert(game.hud._msg.text == game.tip_text(game.TIP_STEER))
	game.player.yaw += 0.3                     # steering answers STEER
	game._update_tips(0.1)
	assert(game._tip_stage == game.TIP_FIRE)
	game._update_tips(0.1)
	assert(game.hud._msg.text == game.tip_text(game.TIP_FIRE))
	GameState.level_shots += 1                 # a shot answers FIRE
	game._update_tips(0.1)
	assert(game._tip_stage == game.TIP_BOOST)
	GameState.level_kills += 1                 # BOOST waits for a kill (or 8 s)
	Input.action_press("boost")
	game._update_tips(0.1)
	Input.action_release("boost")
	assert(game._tip_stage == game.TIP_EVADE)
	game._update_tips(0.1)
	assert(game.hud._msg.text != game.tip_text(game.TIP_EVADE))   # waits for a bolt
	game.shot_mgr.threat_near = true
	game._update_tips(4.0)
	assert(game.hud._msg.text == game.tip_text(game.TIP_EVADE))
	game.player.dodged.emit(Vector3.RIGHT)     # a roll answers EVADE
	game._update_tips(0.1)
	assert(not game._tips_on and GameState.seen_flight_tips)
	GameState.seen_flight_tips = false
	GameState.load_settings()
	assert(GameState.seen_flight_tips)         # saved for good
	game._start_tips(true)
	assert(not game._tips_on)                  # never repeats
	# a line nobody answers moves on instead of nagging
	GameState.seen_flight_tips = false
	game._start_tips(true)
	game._update_tips(game.TIP_GIVE_UP + 0.1)
	assert(game._tip_stage == game.TIP_FIRE)
	game._tips_on = false
	GameState.mark_flight_tips_seen()
	# touch wording, and the stick's double flick reaches the double-tap roll
	game._touch_mode = true
	assert(game.tip_text(game.TIP_STEER) == "DRAG LEFT THUMB TO STEER")
	game._touch_mode = false
	GameState.energy = GameState.max_energy()
	game.player.dodge_cd = 0.0
	Input.action_press("steer_left", 0.8)
	game.player.update_flight(1.0 / 60.0)
	Input.action_release("steer_left")
	game.player.update_flight(1.0 / 60.0)
	Input.action_press("steer_left", 0.8)
	game.player.update_flight(1.0 / 60.0)
	Input.action_release("steer_left")
	assert(game.player.dodge_cd > 0.0)
	# the FLIGHT MANUAL shows the touch page in touch mode
	game.overlays.touch_mode = true
	game.overlays.show_only("help")
	assert(game.overlays._help_touch.visible and not game.overlays._help_keys.visible)
	game.overlays.touch_mode = false
	game.overlays.show_only("help")
	assert(game.overlays._help_keys.visible and not game.overlays._help_touch.visible)
	game.overlays.hide_all()
	print("FIRST-RUN ok — sector-1 drone, STEER/FIRE/BOOST/EVADE callouts, saved, give-up, touch manual + roll")
	# --- re-audit Step 6 (M6): feel — infighting, the boost pulse, steady warnings ---
	var fem: EnemyManager = game.enemy_mgr
	var fsm: ShotManager = game.shot_mgr
	fem.clear_all()
	fsm.clear_all()
	var fring := mini(game.player.ring_idx + 6, game.path.main_ring_count - 2)
	fem.spawn(fring, -1, "drone")
	fem.spawn(fring, -1, "hulk")
	assert(fem.enemies.size() == 2)
	var shooter: Dictionary = fem.enemies[0]
	var victim: Dictionary = fem.enemies[1]
	(victim.node as Node3D).position = (shooter.node as Node3D).position + Vector3(0, 0, -6)
	var vhp: int = victim.hp
	var shp: int = shooter.hp
	# each bolt is tested on alternate frames, so every check below steps two
	var two_frames := func(dt: float) -> void:
		fsm.update_shots(dt)
		fsm.update_shots(dt)
	# a stray bolt resting on a neighbour hurts it by INFIGHT_DMG and is spent
	fsm.fire_enemy(victim.node.position, Vector3.ZERO, 9.0, 1.7, false, shooter.node)
	fsm._eshots.back().age = 1.0
	two_frames.call(1.0 / 60.0)
	assert(int(victim.hp) == vhp - ShotManager.INFIGHT_DMG)
	assert(fsm._eshots.is_empty())
	# ...never its own shooter, never inside the grace time, never a boss, and boss
	# patterns (no source) never infight at all
	fsm.fire_enemy(shooter.node.position, Vector3.ZERO, 9.0, 1.7, false, shooter.node)
	fsm._eshots.back().age = 1.0
	two_frames.call(1.0 / 60.0)
	assert(int(shooter.hp) == shp)
	fsm.clear_all()
	fsm.fire_enemy(victim.node.position, Vector3.ZERO, 9.0, 1.7, false, shooter.node)
	two_frames.call(1.0 / 60.0)   # age 2/60 < INFIGHT_GRACE
	assert(int(victim.hp) == vhp - ShotManager.INFIGHT_DMG)
	fsm.clear_all()
	fsm.fire_enemy(victim.node.position, Vector3.ZERO, 9.0, 1.7, false, null)
	two_frames.call(1.0)
	assert(int(victim.hp) == vhp - ShotManager.INFIGHT_DMG)
	fsm.clear_all()
	victim.is_boss = true
	fsm.fire_enemy(victim.node.position, Vector3.ZERO, 9.0, 1.7, false, shooter.node)
	fsm._eshots.back().age = 1.0
	two_frames.call(1.0 / 60.0)
	assert(int(victim.hp) == vhp - ShotManager.INFIGHT_DMG)
	victim.erase("is_boss")
	fsm.clear_all()
	# a kill made by infighting scores like a chain kill
	victim.hp = 1
	var fscore := GameState.score
	fsm.fire_enemy(victim.node.position, Vector3.ZERO, 9.0, 1.7, false, shooter.node)
	fsm._eshots.back().age = 1.0
	two_frames.call(1.0 / 60.0)
	assert(fem.enemies.size() == 1 and GameState.score > fscore)
	fem.clear_all()
	fsm.clear_all()
	# boost: the press (not the hold) pulses the FOV up and back; SCREEN SHAKE gates it
	GameState.screen_shake = true
	GameState.energy = GameState.max_energy()
	game.player._boost_pulse_t = -1.0
	Input.action_press("boost")
	game.player.update_flight(1.0 / 60.0)
	assert(game.player._boost_pulse_t >= 0.0)
	await get_tree().process_frame   # next frame: still held, no longer "just pressed"
	var pulse_t: float = game.player._boost_pulse_t
	game.player.update_flight(0.05)
	assert(game.player._boost_pulse_t > pulse_t)   # the same pulse, not a restart
	assert(game.player.camera.fov > GameState.view_fov + 1.0)
	Input.action_release("boost")
	for f in 45:
		game.player.update_flight(1.0 / 60.0)
	assert(game.player._boost_pulse_t < 0.0)
	assert(is_equal_approx(game.player.camera.fov, GameState.view_fov))
	GameState.screen_shake = false
	await get_tree().process_frame
	Input.action_press("boost")
	game.player.update_flight(1.0 / 60.0)
	Input.action_release("boost")
	assert(game.player._boost_pulse_t < 0.0)
	GameState.screen_shake = true
	# REDUCE FLASH: the THREAT lamp and the low-shield LED hold steady
	GameState.reduce_flashing = true
	game.shot_mgr.threat_near = true
	GameState.shields = GameState.max_shields() * 0.1
	game.hud._process(1.0 / 60.0)
	var steady_threat: int = game.hud._c_blink
	var steady_led: int = game.hud._led_blink
	OS.delay_msec(230)   # past both blink half-periods
	game.shot_mgr.threat_near = true
	game.hud._process(1.0 / 60.0)
	assert(game.hud._c_blink == steady_threat and game.hud._led_blink == steady_led)
	assert(steady_led == 0)   # 0 = the segment lit
	GameState.reduce_flashing = false
	GameState.shields = GameState.max_shields()
	print("FEEL ok — infighting (not self/grace/boss/sourceless, scores), boost FOV pulse + gate, steady warnings")
	# --- v4a: palette tricks — banded distance darkness, colour cycling, capped
	# flashes, richer blasts ---
	var vrig: LightRig = game.light_rig
	var vdist: Vector2 = vrig.distance_range()
	assert(is_equal_approx(vdist.x, game.env.fog_depth_begin))
	assert(is_equal_approx(vdist.y, game.env.fog_depth_end))   # the sprites' fog matches
	for m in vrig._materials:
		assert(is_equal_approx(float(m.get_shader_parameter("dist_end")), vdist.y))
	var late := ShaderMaterial.new()
	late.shader = load("res://shaders/sector.gdshader")
	vrig.register(late)   # registered after the mood was set: still gets the range
	assert(is_equal_approx(float(late.get_shader_parameter("dist_begin")), vdist.x))
	vrig._materials.erase(late)
	var vtheme: String = game._current_level().theme_id
	var vcyc := TextureGen.cycle_keys(vtheme)
	assert(not vcyc.is_empty())
	for key in vcyc:
		assert(is_equal_approx(float((game.world.mats[key] as ShaderMaterial)
			.get_shader_parameter("cycle_speed")), float(vcyc[key])))
	assert(is_equal_approx(float(game.world._door_mat.get_shader_parameter("cycle_speed")),
		TextureGen.DOOR_CYCLE))
	var still: Variant = (game.world.mats["ceil"] as ShaderMaterial).get_shader_parameter("cycle_speed")
	assert(still == null or float(still) == 0.0)   # lamps and plain ceilings stay steady
	# capped flashes: one per FLASH_GAP_MS, REDUCE FLASH scales them, they fade out
	var vhud: Hud = game.hud
	vhud._tint_last_ms = -100000
	assert(vhud.flash_tint(Color.RED, 0.3))
	assert(is_equal_approx(vhud._tint_flash.color.a, 0.3))
	assert(not vhud.flash_tint(Color.RED, 0.3))   # inside the gap: refused
	vhud._process(Hud.FLASH_FADE + 0.01)
	assert(vhud._tint_flash.color.a == 0.0)
	GameState.reduce_flashing = true
	vhud._tint_last_ms = -100000
	assert(vhud.flash_tint(Color.GOLD, 0.3))
	assert(is_equal_approx(vhud._tint_flash.color.a, 0.3 * Hud.FLASH_REDUCED))
	GameState.reduce_flashing = false
	# a hit pops red; a shield pickup's message names the scaled amount
	vhud._tint_last_ms = -100000
	vhud._tint_flash.color.a = 0.0
	game.player.iframes_t = 0.0
	GameState.shields = GameState.max_shields()
	game.player.take_damage(10.0, "TEST")
	assert(vhud._tint_flash.color.a > 0.0 and vhud._tint_flash.color.r > 0.9)
	GameState.difficulty = 0
	game._on_pickup_collected("shield")
	assert(vhud._msg.text == "SHIELD CELL +%d" % roundi(PickupManager.EFFECT.shield * 1.5))
	GameState.difficulty = 1
	# richer blasts: more frames, and a big one leaves lingering smoke
	assert(FxGen.fireball_frames().size() == FxGen.FIREBALL_FRAMES)
	assert(FxGen.smoke_frames().size() == FxGen.SMOKE_FRAMES)
	var vsm: ShotManager = game.shot_mgr
	vsm.clear_all()
	vsm.spawn_explosion(game.player.position + game.player.forward() * 30.0, true)
	for f in 48:   # past the 0.70 s fireball
		vsm.update_shots(1.0 / 60.0)
	assert(vsm._explosions.is_empty())
	assert(vsm._puffs.size() == ShotManager.AFTERMATH_PUFFS)
	assert(is_equal_approx(float(vsm._puffs[0].life), ShotManager.AFTERMATH_LIFE))
	vsm.clear_all()
	print("V4A ok — distance bands match the fog, cycling on themed surfaces, capped flashes, 14/6-frame blasts + aftermath smoke")
	# --- v4 perf groundwork: FxBatch, one draw call per effect layer. A layer's frames
	# sit in one atlas strip, add() refuses past capacity, an empty layer hides, and
	# the material is the Sprite3D look in particle-billboard form ---
	var fxb := FxBatch.new(FxGen.fireball_frames(), 3)
	add_child(fxb)
	var fmat: StandardMaterial3D = fxb.material_override
	var strip: Image = fmat.albedo_texture.get_image()
	assert(strip.get_width() == 48 * FxGen.FIREBALL_FRAMES and strip.get_height() == 48)
	var f5: Image = FxGen.fireball_frames()[5].get_image()
	for px in [Vector2i(24, 24), Vector2i(10, 30), Vector2i(40, 12)]:
		assert(strip.get_pixelv(px + Vector2i(5 * 48, 0)) == f5.get_pixelv(px))
	assert(fmat.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES)
	assert(fmat.particles_anim_h_frames == FxGen.FIREBALL_FRAMES)
	assert(fmat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	assert(fmat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	assert(fmat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert(fmat.cull_mode == BaseMaterial3D.CULL_DISABLED)
	assert(not fxb.visible and fxb.count() == 0)
	fxb.begin()
	for slot in 5:
		fxb.add(Vector3(slot, 0, 0), 2.0, slot)
	fxb.end()
	assert(fxb.count() == 3 and fxb.visible)   # capacity 3: the other two refused
	fxb.begin()
	fxb.end()
	assert(fxb.count() == 0 and not fxb.visible)   # empty: hidden, so no draw call
	# the particle billboard floors .z x cells, so each cell's data lands mid-cell
	for c in FxGen.FIREBALL_FRAMES:
		assert(int(FxBatch.cell_data(c, FxGen.FIREBALL_FRAMES).b * FxGen.FIREBALL_FRAMES) == c)
	assert(int(FxBatch.cell_data(99, 4).b * 4) == 3)   # out of range: the last cell
	fxb.queue_free()
	# the player-bolt atlas holds every weapon: two shimmer frames each, one missile
	var want := 0
	for w: WeaponDef in game.weapons:
		assert(int(vsm._bolt_cell[w.display_name]) == want)
		want += 1 if w.fuse > 0.0 else 2
	assert(vsm._fx_pbolt.cells == want)
	print("FXBATCH ok — %d-cell fireball strip, capacity and empty-layer rules, %d-cell bolt atlas" % [
		FxGen.FIREBALL_FRAMES, want])
	# --- re-audit Step 1: the app icons and link-preview card are painted by code
	# (hard rule 1). Sizes are what the web export and the PWA manifest expect, and
	# every pixel is a palette entry, read back through the same 8-bit Image path.
	var pal_img := Image.create(Palette.ALL.size(), 1, false, Image.FORMAT_RGBA8)
	for pi in Palette.ALL.size():
		pal_img.set_pixel(pi, 0, Palette.ALL[pi])
	var pal := {}
	for pi in Palette.ALL.size():
		pal[pal_img.get_pixel(pi, 0)] = true
	for size in [144, 180, 512]:
		var ic := IconGen.icon(size)
		assert(ic.get_width() == size and ic.get_height() == size)
		assert(pal.has(ic.get_pixel(0, 0)))
	var card := IconGen.card()
	assert(card.get_width() == 1200 and card.get_height() == 630)
	for art: Image in [IconGen.icon_art(), IconGen.card_art()]:
		var inks := {}
		for y in art.get_height():
			for x in art.get_width():
				var px: Color = art.get_pixel(x, y)
				assert(pal.has(px))
				inks[px] = true
		assert(inks.size() >= 8)   # actually painted, not a blank fill
	print("ICONS ok — 144/180/512 icons + 1200x630 card, code-painted, palette-only")
	print("SMOKE TEST COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
