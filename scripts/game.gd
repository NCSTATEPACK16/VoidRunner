extends Node3D
## Root orchestrator: owns the level flow (briefing → fly → locked arenas → exit
## portal → next level → victory), the weapon heat economy, and all system wiring.
## Everything under it is built in code from procedural assets.

enum State { MENU, BRIEFING, PLAYING, PAUSED, GAME_OVER, LEVEL_CLEAR, VICTORY }

const HEAT_COOL := 26.0
const OVERHEAT_LOCK := 3.0
const PORTAL_TRIGGER_SQ := 49.0

var state := State.MENU
var weapons: Array[WeaponDef] = []
var levels: Array[LevelDef] = []

var path: PathGen
var world: WorldBuilder
var player: PlayerShip
var enemy_mgr: EnemyManager
var shot_mgr: ShotManager
var pickup_mgr: PickupManager
var prop_mgr: PropManager       # K3 fuel cells
var hazard_mgr: HazardManager   # K3 crushers
var hud: Hud
var overlays: Overlays
var view: SubViewport
var dither_layer: CanvasLayer   # Phase H: toggled by the settings menu
var env: Environment            # K1: per-level fog/ambient moods retune this

var _fire_cd := 0.0
var _lowfire_cd := 0.0   # rate-limits the "LOW ENERGY"/"NO MISSILES" nag (I1/I2)
var _overheat_t := 0.0
var _arena_spawned := {}
var _arena_kills := {}
var _boss_arena_start := -1   # Phase J: first ring of the boss room (-1 = no boss)
var _boss_announced := false
var _low_shield_warned := false
var _built_level := -1        # level index the world is currently built for (-1 = dirty)
var _warmup_rig: Node3D

# K5 Void Gauntlet: endless mode runs on a synthetic LevelDef whose numbers climb
# with distance (one tier per 60 rings ≈ 720 m); the path extends and its arenas
# are discovered while flying.
var _gauntlet := false
var _gauntlet_def: LevelDef
var _gauntlet_tier := 0

## V2.0 phantom-wall secrets: {ring, side, node, found} — a wall panel you can fly
## straight through, hiding a pickup cache (the original's holographic walls).
var _secrets: Array[Dictionary] = []


func _ready() -> void:
	GameState.load_settings()   # Phase H: before overlays build so labels show saved values
	GameState.load_records()    # Phase J: high score / best ranks / unlocked sector
	for w in ["neutron", "scatter", "bolt", "missile"]:
		weapons.append(load("res://resources/weapons/%s.tres" % w))
	# Phase J: probe rather than hardcode the count — adding level_N.tres extends
	# the campaign. ResourceLoader.exists also matches the .remap files a web export
	# converts .tres references into.
	var li := 1
	while ResourceLoader.exists("res://resources/levels/level_%d.tres" % li):
		levels.append(load("res://resources/levels/level_%d.tres" % li))
		li += 1
	_gauntlet_def = LevelDef.new()
	_gauntlet_def.display_name = "VOID GAUNTLET"
	_gauntlet_def.kind = "endless"
	_gauntlet_def.objective = "SURVIVE — EVERY METRE SCORES"
	_gauntlet_def.briefing = "No exit gate on this run. The tunnel goes on for as " \
		+ "long as you do, and the void keeps sending more. Fly far, fly sharp — " \
		+ "your distance is the record."
	_gauntlet_def.rings = 200   # initial batch; extend_to() grows it in flight
	_build_game_view()
	_build_environment()
	world = WorldBuilder.new()
	view.add_child(world)
	player = PlayerShip.new()
	view.add_child(player)
	enemy_mgr = EnemyManager.new()
	view.add_child(enemy_mgr)
	shot_mgr = ShotManager.new()
	view.add_child(shot_mgr)
	pickup_mgr = PickupManager.new()
	view.add_child(pickup_mgr)
	prop_mgr = PropManager.new()
	view.add_child(prop_mgr)
	hazard_mgr = HazardManager.new()
	view.add_child(hazard_mgr)
	hud = Hud.new()
	hud.layer = 1
	view.add_child(hud)
	_build_dither_layer()
	overlays = Overlays.new()
	overlays.layer = 10
	add_child(overlays)
	# wiring
	shot_mgr.player = player
	shot_mgr.enemy_mgr = enemy_mgr
	enemy_mgr.player = player
	world.tunnel_spawn_requested.connect(_on_tunnel_spawn)
	enemy_mgr.enemy_fired.connect(shot_mgr.fire_enemy)
	enemy_mgr.exploded.connect(shot_mgr.spawn_explosion)
	enemy_mgr.enemy_killed.connect(_on_enemy_killed)
	enemy_mgr.boss_killed.connect(_on_boss_killed)
	enemy_mgr.boss_phase.connect(_on_boss_phase)
	pickup_mgr.player = player
	enemy_mgr.drop_spawned.connect(pickup_mgr.spawn_drop)
	pickup_mgr.collected.connect(_on_pickup_collected)
	prop_mgr.player = player
	prop_mgr.enemy_mgr = enemy_mgr
	prop_mgr.shot_mgr = shot_mgr
	shot_mgr.prop_mgr = prop_mgr
	prop_mgr.cell_destroyed.connect(_on_cell_destroyed)
	hazard_mgr.player = player
	shot_mgr.player_hit.connect(func(dmg: float) -> void: player.take_damage(dmg, "SHIELD HIT"))
	player.damaged.connect(func(_a: float, msg: String) -> void: hud.show_message(msg))
	player.notified.connect(func(msg: String) -> void: hud.show_message(msg))
	player.dodged.connect(func(dir: Vector3) -> void:
		shot_mgr.spawn_dodge_burst(player.position + dir * 2.0 + Vector3.UP * -0.4)
		AudioSys.play_dodge())
	GameState.player_died.connect(_on_player_died)
	overlays.launch_requested.connect(_on_launch)
	overlays.gauntlet_requested.connect(_on_gauntlet)
	overlays.next_level_requested.connect(_on_next_level)
	overlays.retry_requested.connect(_on_retry)
	overlays.new_campaign_requested.connect(_on_new_campaign)
	var names: Array[String] = []
	for w in weapons:
		names.append(w.display_name)
	hud.setup(player, enemy_mgr, shot_mgr, names)
	var level_names: Array[String] = []
	for l in levels:
		level_names.append(l.display_name)
	overlays.set_campaign(level_names)   # Phase J sector select
	# Phase H: dither layer follows the settings toggle; apply saved settings now
	GameState.dither_toggled.connect(func(on: bool) -> void: dither_layer.visible = on)
	GameState.apply_settings()
	# idle backdrop behind the start screen (v2.2 does the same)
	_load_level_world(0)
	player.reset_to_start()
	player.active = false
	overlays.show_only("start")


## Phase I4: the whole game frame (3D world + in-flight HUD + dither) renders in a
## fixed 320x200 SubViewport scaled up with nearest sampling, so the DOS look is
## locked to that resolution no matter the window size. The menu/briefing overlays
## stay OUTSIDE this viewport and draw at native resolution for crisp text (project
## stretch mode is canvas_items). Do not move overlays inside, and do not let the
## viewport size follow the window — both would undo the effect.
func _build_game_view() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view = SubViewport.new()
	view.size = Vector2i(320, 200)
	view.own_world_3d = true
	view.handle_input_locally = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(view)
	add_child(container)


## K1/G3: light diminishing — surfaces dissolve into PURE black with distance (no
## blue tint anywhere), low ambient so unlit pockets read as real shadow. Per-theme
## fog distance and ambient tint are applied on top in _apply_theme_mood.
func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("16181e")
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color.BLACK
	env.fog_depth_begin = 10.0
	env.fog_depth_end = 100.0
	var we := WorldEnvironment.new()
	we.environment = env
	view.add_child(we)


## K1/V-10: sector lighting mood — each zone theme can tighten the fog and tint
## the ambient floor. Boss rooms are wider than most fog ranges, so boss levels
## get a slack floor to keep the far wall (and the boss) readable.
func _apply_theme_mood(theme: Dictionary, level: LevelDef) -> void:
	var fog_end: float = theme.get("fog_end", 100.0)
	if level.kind == "boss":
		fog_end = maxf(fog_end, 110.0)
	env.fog_depth_end = fog_end
	env.ambient_light_color = theme.get("amb", Color("16181e"))


## Phase G2: palette-quantize + Bayer-dither the finished frame (3D + HUD, not the
## menu overlays). Sits on CanvasLayer 5, between the HUD (1) and overlays (10).
func _build_dither_layer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/palette_dither.gdshader")
	var colors := PackedVector3Array()
	for c in Palette.ALL:
		colors.append(Vector3(c.r, c.g, c.b))
	while colors.size() < 64:  # pad to the shader's fixed uniform array size
		colors.append(colors[colors.size() - 1])
	mat.set_shader_parameter("palette", colors)
	mat.set_shader_parameter("palette_size", Palette.ALL.size())
	rect.material = mat
	layer.add_child(rect)
	view.add_child(layer)
	dither_layer = layer


# ---------- level lifecycle ----------

func _load_level_world(index: int) -> void:
	GameState.level_index = index
	var level := _current_level()
	if _gauntlet:
		# fresh tier-0 numbers, fresh seed, random zone theme — every run reads different
		_apply_gauntlet_tier(0)
		_gauntlet_def.level_seed = randi()
		var theme_ids: Array = TextureGen.THEMES.keys()
		_gauntlet_def.theme_id = theme_ids[randi() % theme_ids.size()]
	path = PathGen.new()
	path.generate(level.rings, level.level_seed, level.spawn_arena,
		level.kind == "boss", _gauntlet)
	player.path = path
	enemy_mgr.path = path
	enemy_mgr.level = level
	pickup_mgr.path = path
	var theme: Dictionary = TextureGen.THEMES[level.theme_id]
	_apply_theme_mood(theme, level)
	world.rebuild(path, TextureGen.theme_set(level.theme_id, level.level_seed),
		theme.accent, theme.accent2)
	player.world = world
	enemy_mgr.clear_all()
	shot_mgr.clear_all()
	pickup_mgr.clear_all()
	prop_mgr.clear_all()
	hazard_mgr.clear_all()
	hazard_mgr.path = path
	hazard_mgr.setup(world.mats.wall, theme.accent2)
	_place_props(level)
	_place_hazards(level)
	_place_secrets(level)
	_arena_spawned.clear()
	_arena_kills.clear()
	for arena in path.arenas:
		if arena.door_ring < 0:
			continue
		for ring_idx in arena.spawn_rings:
			enemy_mgr.spawn(ring_idx, arena.id, _pick_enemy_type(level))
		_arena_spawned[arena.id] = arena.spawn_rings.size()
		_arena_kills[arena.id] = 0
		if arena.spawn_rings.is_empty():
			world.open_door(arena.id)
	# Phase J: boss levels put a single boss deep in the final room and keep the
	# exit ring dark until it falls (no bulkheads on boss levels — see PathGen).
	_boss_arena_start = -1
	_boss_announced = false
	hud.set_boss_name(level.boss_name if level.kind == "boss" else "")
	if level.kind == "boss":
		var room: Dictionary = path.arenas.back()
		enemy_mgr.spawn_boss(room.end - 8, level)
		world.set_portal_active(false)
		_boss_arena_start = room.start
		_place_boss_stations(room, level)
	if _gauntlet:
		_gauntlet_stream()   # discover + wire the arenas in the initial batch
	_built_level = index


## Resupply stations spread across the boss room's back wall, behind the boss —
## crossing the open chamber to restock is the intended risk/reward. They respawn
## at each boss phase transition (see _on_boss_phase).
func _place_boss_stations(room: Dictionary, level: LevelDef) -> void:
	var kinds: Array[String] = []
	for i in level.boss_shield_cells:
		kinds.append("shield")
	for i in level.boss_missile_cells:
		kinds.append("missile")
	if kinds.is_empty():
		return
	var ring: Dictionary = path.rings[room.end - 2]
	for i in kinds.size():
		var frac := 0.0 if kinds.size() == 1 \
			else lerpf(-0.55, 0.55, float(i) / (kinds.size() - 1))
		pickup_mgr.add_station(ring.p + ring.r * (frac * ring.hw), kinds[i])


## K3: fuel cells sit low in arenas — cover for the player, bait for chain kills.
## Deterministic per level seed; destroying all of them is the secondary objective.
func _place_props(level: LevelDef) -> void:
	GameState.level_props_total = 0
	GameState.level_props = 0
	if level.kind == "boss" or _gauntlet:
		return   # boss rooms stay clean (Phase J); gauntlet arenas stream in later (K5)
	var rng := RandomNumberGenerator.new()
	rng.seed = level.level_seed + 555
	for arena in path.arenas:
		for i in rng.randi_range(2, 4):
			var ri := rng.randi_range(arena.start + 1, arena.end - 1)
			var ring: Dictionary = path.rings[ri]
			var pos: Vector3 = ring.p \
				+ ring.r * (rng.randf_range(-0.7, 0.7) * ring.hw) \
				+ ring.u * (-(ring.hh - ring.fo) + 1.4)
			prop_mgr.spawn_prop(pos)
	GameState.level_props_total = prop_mgr.props.size()


## K3: crushers go in plain tunnel stretches — never in arenas, never adjacent to
## a door ring or a hard corner, always ≥15 rings apart. L1 stays trap-free.
func _place_hazards(level: LevelDef) -> void:
	if level.kind == "boss" or GameState.level_index == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = level.level_seed + 777
	var want := clampi(level.rings / 55, 1, 5)
	var placed: Array[int] = []
	var side := 1.0
	for attempt in 60:
		if placed.size() >= want:
			break
		var ri := rng.randi_range(26, level.rings - 24)
		var ring: Dictionary = path.rings[ri]
		if ring.arena_id >= 0:
			continue
		if path.rings[ri - 1].d.dot(path.rings[ri + 1].d) < 0.98:
			continue   # mid-corner crushers would be unfair
		var clear := true
		for arena in path.arenas:
			if arena.door_ring >= 0 and absi(ri - arena.door_ring) < 5:
				clear = false
		for other in placed:
			if absi(ri - other) < 15:
				clear = false
		if not clear:
			continue
		hazard_mgr.spawn_trap(ri, side)
		side = -side
		placed.append(ri)


func _on_cell_destroyed() -> void:
	if GameState.level_props >= GameState.level_props_total:
		hud.show_message("SECONDARY COMPLETE — ALL CELLS DESTROYED")


## V2.0 secrets: 1-2 phantom wall panels per tunnel level, on straight plain-tunnel
## stretches clear of doors, corners, crushers, and each other. Deterministic per
## level seed, like props and hazards.
func _place_secrets(level: LevelDef) -> void:
	for s in _secrets:
		if is_instance_valid(s.node):
			s.node.queue_free()
	_secrets.clear()
	GameState.level_secrets = 0
	GameState.level_secrets_total = 0
	if level.kind != "tunnel":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = level.level_seed + 999
	var want := clampi(level.rings / 100, 1, 2)
	var placed: Array[int] = []
	for attempt in 80:
		if placed.size() >= want:
			break
		var ri := rng.randi_range(30, level.rings - 30)
		var ring: Dictionary = path.rings[ri]
		if ring.arena_id >= 0:
			continue
		if path.rings[ri - 2].d.dot(path.rings[ri + 2].d) < 0.985:
			continue   # panels sit flush only on straight wall runs
		var clear := true
		for arena in path.arenas:
			if arena.door_ring >= 0 and absi(ri - arena.door_ring) < 6:
				clear = false
		for other in placed:
			if absi(ri - other) < 25:
				clear = false
		for t in hazard_mgr._traps:
			if absi(ri - t.ring) < 6:
				clear = false
		if not clear:
			continue
		_secrets.append(_build_secret(ri, 1.0 if rng.randf() < 0.5 else -1.0))
		placed.append(ri)
	GameState.level_secrets_total = _secrets.size()


## The panel: a box proud of the wall by ~1 u with a slightly-off wall tint — the
## manual's "suspicious wall" tell. No collision anywhere in this game is physical,
## so flying through it just works; discovery is a lateral-depth check per frame.
func _build_secret(ri: int, side: float) -> Dictionary:
	var ring: Dictionary = path.rings[ri]
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, (ring.hh - ring.fo - ring.co) * 2.0 - 0.6, PathGen.SEG * 1.6)
	mi.mesh = box
	var mat: StandardMaterial3D = world.mats.wall.duplicate()
	mat.albedo_color = Color(0.86, 0.86, 0.97)   # cooler than true wall — the tell
	mi.material_override = mat
	mi.transform = Transform3D(Basis(ring.r, ring.u, -ring.d),
		ring.p + ring.r * (side * (ring.hw - 1.2)) + ring.u * ((ring.fo - ring.co) * 0.5))
	world.add_child(mi)
	return {"ring": ri, "side": side, "node": mi, "found": false}


## Brushing into a phantom panel reveals it: the panel vanishes, the cache spills
## out, score lands, and the tally remembers. Runs per frame; ≤2 entries, cheap.
func _update_secrets() -> void:
	for s in _secrets:
		if s.found or absi(player.ring_idx - s.ring) > 1:
			continue
		var ring: Dictionary = path.rings[s.ring]
		var lat: float = (player.position - ring.p as Vector3).dot(ring.r) * s.side
		if lat > ring.hw - 2.4:
			s.found = true
			s.node.queue_free()
			GameState.level_secrets += 1
			GameState.score += 250
			hud.show_message("SECRET FOUND +250", 2.0)
			AudioSys.play_portal()
			var kinds: Array[String] = ["shield", "energy", "missile"]
			if randf() < 0.35:
				kinds.append("bomb")
			for kind in kinds:
				pickup_mgr.spawn_drop(
					player.position + ring.d * randf_range(2.0, 6.0), s.ring, kind)


## K5: the active tuning source — campaign levels from resources, gauntlet from
## the synthetic escalating def.
func _current_level() -> LevelDef:
	return _gauntlet_def if _gauntlet else levels[GameState.level_index]


## K5: keep the endless path generated ahead of the player, and wire in any arena
## the scan completes — bulkhead door, exact guard count, kill-counter bookkeeping.
func _gauntlet_stream() -> void:
	path.extend_to(player.ring_idx + WorldBuilder.BUILD_AHEAD + 40)
	for arena in path.discover_arenas(_gauntlet_def.spawn_arena):
		world.build_door(arena)
		for ring_idx in arena.spawn_rings:
			enemy_mgr.spawn(ring_idx, arena.id, _pick_enemy_type(_gauntlet_def))
		_arena_spawned[arena.id] = arena.spawn_rings.size()
		_arena_kills[arena.id] = 0
		if arena.spawn_rings.is_empty():
			world.open_door(arena.id)


## K5: one difficulty tier per 60 rings (~720 m). Newly spawned enemies sample the
## def at spawn time, so raising it escalates the run without touching live ones.
func _apply_gauntlet_tier(tier: int) -> void:
	_gauntlet_tier = tier
	_gauntlet_def.enemy_hp = 2 + tier / 2
	_gauntlet_def.enemy_speed = minf(13.0, 6.0 + tier * 0.7)
	_gauntlet_def.enemy_fire = maxf(1.3, 2.8 - tier * 0.16)
	_gauntlet_def.spawn_tunnel = minf(0.30, 0.08 + tier * 0.025)
	_gauntlet_def.spawn_arena = minf(0.55, 0.30 + tier * 0.03)
	var pool := PackedStringArray(["drone", "drone"])
	if tier >= 1:
		pool.append("weaver")
	if tier >= 2:
		pool.append("hulk")
	if tier >= 3:
		pool.append("weaver")
	if tier >= 5:
		pool.append("hulk")
	_gauntlet_def.enemy_types = pool
	AudioSys.set_music_intensity(tier / 8.0)


func _launch_level() -> void:
	GameState.level_start_score = GameState.score
	GameState.heat = 0.0
	GameState.is_overheated = false
	GameState.weapon_index = 0
	GameState.missiles = GameState.MISSILES_PER_LEVEL   # I2: refill ammo each level start
	_overheat_t = 0.0
	_fire_cd = 0.0
	GameState.reset_level_stats()
	_end_warmup()
	# the briefing screen already built this level's world (and warmed its shaders);
	# only rebuild when launched directly without a briefing (tests, dirty world)
	if _built_level != GameState.level_index:
		_load_level_world(GameState.level_index)
	_built_level = -1   # once play starts the world is dirty (doors, kills)
	player.reset_to_start()
	player.active = true
	GameState.is_dead = false
	state = State.PLAYING
	overlays.hide_all()
	hud.show_message(_current_level().display_name)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _level_complete() -> void:
	world.portal_active = false
	player.active = false
	AudioSys.play_portal()
	AudioSys.stop_engine()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var idx := GameState.level_index
	var bonus := 500 + idx * 250
	# K3: secondary objective — every fuel cell destroyed
	var secondary_done := GameState.level_props_total > 0 \
		and GameState.level_props >= GameState.level_props_total
	if secondary_done:
		bonus += 400
	GameState.score += bonus
	# Phase J: rank the run, remember progress
	var level := levels[idx]
	var acc := 0
	if GameState.level_shots > 0:
		acc = roundi(100.0 * GameState.level_hits / GameState.level_shots)
	var par := level.par_time
	if par <= 0.0:
		# level length at cruise speed, with generous slack for fighting
		par = level.rings * PathGen.SEG / PlayerShip.BASE_SPEED * 1.9
	var rank := _compute_rank(acc, player.elapsed, par)
	GameState.unlocked_level = mini(
		maxi(GameState.unlocked_level, idx + 1), levels.size() - 1)
	var new_record := GameState.record_progress(rank)
	if idx >= levels.size() - 1:
		state = State.VICTORY
		overlays.set_final_score("victory", GameState.score, new_record)
		overlays.show_only("victory")
	else:
		state = State.LEVEL_CLEAR
		overlays.set_level_clear(
			levels[idx].display_name, bonus, GameState.score, levels[idx + 1].display_name,
			GameState.level_kills, acc, player.elapsed, rank, secondary_done,
			GameState.level_secrets, GameState.level_secrets_total)
		overlays.show_only("level_clear")


## 5-point rank: accuracy 30/50/70% and finishing under par / well under par.
func _compute_rank(acc: int, time: float, par: float) -> String:
	var pts := 0
	for gate in [30, 50, 70]:
		if acc >= gate:
			pts += 1
	if time <= par:
		pts += 1
	if time <= par * 0.7:
		pts += 1
	if pts >= 5:
		return "S"
	if pts >= 4:
		return "A"
	if pts >= 2:
		return "B"
	return "C"


func _on_player_died() -> void:
	state = State.GAME_OVER
	player.active = false
	shot_mgr.spawn_explosion(player.position, true)
	AudioSys.stop_engine()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _gauntlet:
		# K5: a gauntlet run scores by distance; records stay campaign-separate
		var dist := int(player.ring_idx * PathGen.SEG)
		var new_best := GameState.record_gauntlet(dist)
		overlays.set_final_score("game_over", GameState.score, new_best, dist)
	else:
		var new_record := GameState.record_progress()
		overlays.set_final_score("game_over", GameState.score, new_record)
	overlays.show_only("game_over")


# ---------- overlay flow ----------

func _on_launch() -> void:
	if state == State.MENU:
		# Phase J sector select: campaigns can start at any unlocked level
		_gauntlet = false
		GameState.gauntlet_mode = false
		GameState.level_index = overlays.selected_sector()
		GameState.level_start_score = 0
		GameState.score = 0
		_show_briefing()
	else:
		_launch_level()


## K5: Void Gauntlet entry from the start screen.
func _on_gauntlet() -> void:
	_gauntlet = true
	GameState.gauntlet_mode = true
	_built_level = -1
	GameState.level_index = 0
	GameState.level_start_score = 0
	GameState.score = 0
	_show_briefing()


func _show_briefing() -> void:
	state = State.BRIEFING
	overlays.set_briefing(_current_level())
	overlays.show_only("briefing")
	# Build the level world NOW, behind the briefing overlay, and park a warm-up rig
	# in front of the camera so every shader variant compiles while the player reads.
	# First-use shader compilation is the level-1 stutter cause — it is synchronous
	# and very slow on the WebGL export (profiled 100-130ms even on desktop GL).
	_load_level_world(GameState.level_index)
	player.reset_to_start()
	player.active = false
	_start_warmup()


## One small instance of every material the level can draw — enemy/boss sprites,
## shots, explosions, sparks, pickups, door + portal meshes — plus energized
## muzzle/boom lights, visible to the camera for a few frames during the briefing.
func _start_warmup() -> void:
	_end_warmup()
	_warmup_rig = Node3D.new()
	view.add_child(_warmup_rig)
	var fwd := player.forward()
	var right := fwd.cross(Vector3.UP).normalized()
	var base: Vector3 = player.position + fwd * 9.0
	var texes: Array = []
	texes.append_array(enemy_mgr.warmup_textures())
	texes.append_array(shot_mgr.warmup_textures(weapons))
	texes.append_array(pickup_mgr.warmup_textures())
	texes.append_array(prop_mgr.warmup_textures())
	for i in texes.size():
		var s := SpriteGen.make_sprite(texes[i], 0.7)
		s.position = base + right * ((i % 6) - 2.5) * 1.1 \
			+ Vector3.UP * (float(i / 6) - 1.0) * 1.1
		_warmup_rig.add_child(s)
	world.warmup_meshes(_warmup_rig, base + Vector3.UP * 2.4)
	player.muzzle_light.light_energy = 0.6
	shot_mgr.warmup_boom_light(base, true)
	get_tree().create_timer(0.5).timeout.connect(_end_warmup)


func _end_warmup() -> void:
	if _warmup_rig and is_instance_valid(_warmup_rig):
		_warmup_rig.queue_free()
		player.muzzle_light.light_energy = 0.0
		shot_mgr.warmup_boom_light(Vector3.ZERO, false)
	_warmup_rig = null


func _on_next_level() -> void:
	GameState.level_index += 1
	_show_briefing()


func _on_retry() -> void:
	GameState.reset_level()
	_show_briefing()


func _on_new_campaign() -> void:
	GameState.reset_run()
	_show_briefing()


# ---------- per-frame ----------

func _process(delta: float) -> void:
	world.animate(delta)
	if state != State.PLAYING:
		return
	player.update_flight(delta)
	if _gauntlet:
		_gauntlet_stream()
		var tier := player.ring_idx / 60
		if tier != _gauntlet_tier:
			_apply_gauntlet_tier(tier)
			hud.show_message("VOID PRESSURE RISING", 1.6)
			AudioSys.play_select()
	world.ensure_world(player.ring_idx)
	GameState.tick_combo(delta)
	_update_heat(delta)
	_update_firing(delta)
	enemy_mgr.update_enemies(delta)
	shot_mgr.update_shots(delta)
	pickup_mgr.update_pickups(delta)
	prop_mgr.update_props(delta)
	hazard_mgr.update_traps(delta)
	_update_secrets()
	_update_arena_lock()
	if _boss_arena_start >= 0 and not _boss_announced \
			and player.ring_idx >= _boss_arena_start - 4:
		_boss_announced = true
		hud.show_message("WARNING · CLASS-X SIGNATURE", 3.0)
		AudioSys.play_overheat()
	# Phase J: one-shot shields-critical callout with hysteresis
	if GameState.shields < 25.0 and not _low_shield_warned:
		_low_shield_warned = true
		hud.show_message("SHIELDS CRITICAL", 2.0)
		AudioSys.play_hit()
	elif GameState.shields > 30.0:
		_low_shield_warned = false
	if world.portal_active \
			and player.position.distance_squared_to(world.portal_position) < PORTAL_TRIGGER_SQ:
		_level_complete()


func _update_heat(delta: float) -> void:
	if _overheat_t > 0.0:
		_overheat_t -= delta
		GameState.heat = maxf(0.0, 100.0 * (_overheat_t / OVERHEAT_LOCK))
		if _overheat_t <= 0.0:
			_overheat_t = 0.0
			GameState.heat = 0.0
			GameState.is_overheated = false
			hud.show_message("WEAPONS ONLINE")
	else:
		GameState.heat = maxf(0.0, GameState.heat - HEAT_COOL * delta)


func _update_firing(delta: float) -> void:
	_fire_cd -= delta
	_lowfire_cd -= delta
	if not Input.is_action_pressed("fire") or _fire_cd > 0.0 or GameState.is_overheated:
		return
	var w := weapons[GameState.weapon_index]
	# --- ammo / energy gates (I2 / I1) — checked before the shot so a blocked
	# trigger can fire the instant reserves return, without eating the cooldown ---
	if w.uses_ammo and GameState.missiles <= 0:
		_notify_cant_fire("NO MISSILES")
		return
	if w.energy_cost > 0.0 and GameState.energy < w.energy_cost:
		_notify_cant_fire("LOW ENERGY")
		return
	_fire_cd = w.cooldown
	shot_mgr.fire_player(w)
	if w.uses_ammo:
		GameState.missiles -= 1
	if w.energy_cost > 0.0:
		GameState.energy -= w.energy_cost   # shared afterburner pool; regens in player.gd
	GameState.heat += w.heat
	if GameState.heat >= 100.0:
		GameState.is_overheated = true
		_overheat_t = OVERHEAT_LOCK
		hud.show_message("WEAPONS OVERHEAT")
		AudioSys.play_overheat()


func _notify_cant_fire(msg: String) -> void:
	if _lowfire_cd > 0.0:
		return
	_lowfire_cd = 1.0
	hud.show_message(msg)


## V2.0 plasma bomb (the original's spacebar screen-clear, on P here): heavy
## damage to every enemy in visual range, reduced against bosses, and nearby
## fuel cells cook off. Rare pickup, PLASMA_MAX carried.
func _fire_plasma_bomb() -> void:
	if GameState.plasma_bombs <= 0:
		_notify_cant_fire("NO PLASMA BOMBS")
		return
	GameState.plasma_bombs -= 1
	for k in range(enemy_mgr.enemies.size() - 1, -1, -1):
		var e: Dictionary = enemy_mgr.enemies[k]
		if e.node.position.distance_squared_to(player.position) > 120.0 * 120.0:
			continue
		enemy_mgr.hit_enemy(k, 25 if e.get("is_boss", false) else 60)
	prop_mgr.splash(player.position, 60.0)
	hud.flash_white()
	player.shake = 0.6
	AudioSys.play_bomb()
	hud.show_message("PLASMA BOMB — %d LEFT" % GameState.plasma_bombs, 1.6)


func _update_arena_lock() -> void:
	for arena in path.arenas:
		if arena.door_ring < 0 or world.is_door_open(arena.id):
			continue
		if player.ring_idx >= arena.start - 2 and player.ring_idx <= arena.door_ring:
			hud.set_kill_counter(_arena_kills.get(arena.id, 0), _arena_spawned.get(arena.id, 0))
			return
	hud.set_kill_counter(0, 0)


func _on_pickup_collected(kind: String) -> void:
	match kind:
		"shield":
			hud.show_message("SHIELD CELL +20")
		"energy":
			hud.show_message("ENERGY CORE +30")
		"missile":
			hud.show_message("MISSILE PACK +3")
		"bomb":
			hud.show_message("PLASMA BOMB +1")
	AudioSys.play_select()


func _on_boss_killed() -> void:
	world.set_portal_active(true)
	hud.show_message("SIGNATURE ELIMINATED — GATE OPEN", 3.0)
	AudioSys.play_portal()
	player.shake = 0.6


func _on_boss_phase(phase: int) -> void:
	if phase == 2:
		hud.show_message("SIGNATURE SHIFTING — VOLLEY PATTERN", 2.5)
	elif phase == 3:
		hud.show_message("SIGNATURE CRITICAL — STAY MOBILE", 2.5)
	AudioSys.play_overheat()
	pickup_mgr.replenish_stations()   # back-wall resupply respawns each phase


func _on_enemy_killed(arena_id: int) -> void:
	if arena_id < 0:
		return
	_arena_kills[arena_id] = _arena_kills.get(arena_id, 0) + 1
	if _arena_kills[arena_id] >= _arena_spawned.get(arena_id, 0) \
			and not world.is_door_open(arena_id):
		world.open_door(arena_id)
		hud.show_message("BULKHEAD OPEN")
		AudioSys.play_select()


func _on_tunnel_spawn(ring_idx: int) -> void:
	# fires during initial chunk builds (BRIEFING state) and while streaming (PLAYING);
	# only the menu's idle backdrop stays empty
	if state == State.MENU:
		return
	var level := _current_level()
	if randf() < level.spawn_tunnel:
		enemy_mgr.spawn(ring_idx, -1, _pick_enemy_type(level))


## I3: weighted pick from a level's enemy_types pool (repeated ids act as weights).
func _pick_enemy_type(level: LevelDef) -> String:
	if level.enemy_types.is_empty():
		return "drone"
	return level.enemy_types[randi() % level.enemy_types.size()]


# ---------- input ----------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		_toggle_pause()
		return
	if state == State.PAUSED and event is InputEventMouseButton and event.pressed:
		_toggle_pause()
		return
	if state != State.PLAYING:
		return
	# I4: the player lives inside the SubViewport, which doesn't receive unhandled
	# input — mouse look is forwarded from here (root viewport) instead.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.apply_mouse_look(event.relative)
		return
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("plasma_bomb"):
		_fire_plasma_bomb()
		return
	for i in 4:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			_select_weapon(i)
			return
	if event.is_action_pressed("weapon_cycle"):
		_select_weapon((GameState.weapon_index + 1) % weapons.size())


func _select_weapon(i: int) -> void:
	if i == GameState.weapon_index:
		return
	GameState.weapon_index = i
	AudioSys.play_select()
	hud.show_message(weapons[i].display_name + " SELECTED")


func _toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		player.active = false
		AudioSys.stop_engine()
		overlays.show_only("pause")
	elif state == State.PAUSED:
		state = State.PLAYING
		player.active = true
		overlays.hide_all()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
