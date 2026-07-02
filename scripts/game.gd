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
var hud: Hud
var overlays: Overlays

var _fire_cd := 0.0
var _overheat_t := 0.0
var _arena_spawned := {}
var _arena_kills := {}


func _ready() -> void:
	for w in ["neutron", "scatter", "bolt", "missile"]:
		weapons.append(load("res://resources/weapons/%s.tres" % w))
	for i in 5:
		levels.append(load("res://resources/levels/level_%d.tres" % (i + 1)))
	_build_environment()
	world = WorldBuilder.new()
	add_child(world)
	player = PlayerShip.new()
	add_child(player)
	enemy_mgr = EnemyManager.new()
	add_child(enemy_mgr)
	shot_mgr = ShotManager.new()
	add_child(shot_mgr)
	hud = Hud.new()
	hud.layer = 1
	add_child(hud)
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
	shot_mgr.player_hit.connect(func(dmg: float) -> void: player.take_damage(dmg, "SHIELD HIT"))
	player.damaged.connect(func(_a: float, msg: String) -> void: hud.show_message(msg))
	GameState.player_died.connect(_on_player_died)
	overlays.launch_requested.connect(_on_launch)
	overlays.next_level_requested.connect(_on_next_level)
	overlays.retry_requested.connect(_on_retry)
	overlays.new_campaign_requested.connect(_on_new_campaign)
	var names: Array[String] = []
	for w in weapons:
		names.append(w.display_name)
	hud.setup(player, enemy_mgr, shot_mgr, names)
	# idle backdrop behind the start screen (v2.2 does the same)
	_load_level_world(0)
	player.reset_to_start()
	player.active = false
	overlays.show_only("start")


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("02030a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2a3140")
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("02030a")
	env.fog_depth_begin = 12.0
	env.fog_depth_end = 150.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


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
	add_child(layer)


# ---------- level lifecycle ----------

func _load_level_world(index: int) -> void:
	GameState.level_index = index
	var level := levels[index]
	path = PathGen.new()
	path.generate(level.rings, level.level_seed, level.spawn_arena)
	player.path = path
	enemy_mgr.path = path
	enemy_mgr.level = level
	var theme: Dictionary = TextureGen.THEMES[level.theme_id]
	world.rebuild(path, TextureGen.theme_set(level.theme_id, level.level_seed), theme.accent)
	player.world = world
	enemy_mgr.clear_all()
	shot_mgr.clear_all()
	_arena_spawned.clear()
	_arena_kills.clear()
	for arena in path.arenas:
		if arena.door_ring < 0:
			continue
		for ring_idx in arena.spawn_rings:
			enemy_mgr.spawn(ring_idx, arena.id)
		_arena_spawned[arena.id] = arena.spawn_rings.size()
		_arena_kills[arena.id] = 0
		if arena.spawn_rings.is_empty():
			world.open_door(arena.id)


func _launch_level() -> void:
	GameState.level_start_score = GameState.score
	GameState.heat = 0.0
	GameState.is_overheated = false
	GameState.weapon_index = 0
	_overheat_t = 0.0
	_fire_cd = 0.0
	_load_level_world(GameState.level_index)
	player.reset_to_start()
	player.active = true
	GameState.is_dead = false
	state = State.PLAYING
	overlays.hide_all()
	hud.show_message(levels[GameState.level_index].display_name)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _level_complete() -> void:
	world.portal_active = false
	player.active = false
	AudioSys.play_portal()
	AudioSys.stop_engine()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var idx := GameState.level_index
	var bonus := 500 + idx * 250
	GameState.score += bonus
	if idx >= levels.size() - 1:
		state = State.VICTORY
		overlays.set_final_score("victory", GameState.score)
		overlays.show_only("victory")
	else:
		state = State.LEVEL_CLEAR
		overlays.set_level_clear(
			levels[idx].display_name, bonus, GameState.score, levels[idx + 1].display_name)
		overlays.show_only("level_clear")


func _on_player_died() -> void:
	state = State.GAME_OVER
	player.active = false
	shot_mgr.spawn_explosion(player.position, true)
	AudioSys.stop_engine()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlays.set_final_score("game_over", GameState.score)
	overlays.show_only("game_over")


# ---------- overlay flow ----------

func _on_launch() -> void:
	if state == State.MENU:
		_show_briefing()
	else:
		_launch_level()


func _show_briefing() -> void:
	state = State.BRIEFING
	overlays.set_briefing(levels[GameState.level_index])
	overlays.show_only("briefing")


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
	world.ensure_world(player.ring_idx)
	_update_heat(delta)
	_update_firing(delta)
	enemy_mgr.update_enemies(delta)
	shot_mgr.update_shots(delta)
	_update_arena_lock()
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
	if not Input.is_action_pressed("fire") or _fire_cd > 0.0 or GameState.is_overheated:
		return
	var w := weapons[GameState.weapon_index]
	_fire_cd = w.cooldown
	shot_mgr.fire_player(w)
	GameState.heat += w.heat
	if GameState.heat >= 100.0:
		GameState.is_overheated = true
		_overheat_t = OVERHEAT_LOCK
		hud.show_message("WEAPONS OVERHEAT")
		AudioSys.play_overheat()


func _update_arena_lock() -> void:
	for arena in path.arenas:
		if arena.door_ring < 0 or world.is_door_open(arena.id):
			continue
		if player.ring_idx >= arena.start - 2 and player.ring_idx <= arena.door_ring:
			hud.set_kill_counter(_arena_kills.get(arena.id, 0), _arena_spawned.get(arena.id, 0))
			return
	hud.set_kill_counter(0, 0)


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
	if randf() < levels[GameState.level_index].spawn_tunnel:
		enemy_mgr.spawn(ring_idx, -1)


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
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
