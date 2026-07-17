class_name EnemyManager
extends Node3D
## Sprite-billboard drones (PLAN.md C3/C4 + F3). AI is the v2.2 port: drift toward
## the player inside 120 u, bob, timed fire with target lead — and, critically, the
## ring-clamp every frame that fixed the "unreachable enemy" bug. Locked-arena
## drones never despawn, so kill-locked doors can always be opened.

signal enemy_killed(arena_id: int)
signal enemy_fired(origin: Vector3, velocity: Vector3, dmg: float, shot_size: float,
	seeker: bool)
signal exploded(pos: Vector3, big: bool)
signal turret_destroyed(pos: Vector3)   # V2.0: game chains fuel cells off this
signal boss_killed
signal boss_phase(phase: int)
signal drop_spawned(pos: Vector3, ring: int, kind: String)
signal gibs_requested(pos: Vector3, vel: Vector3, ring: int, count: int, tint: Color)   # V2.2 L1

const CONTACT_DMG := 12.0
const ENEMY_CAP := 42
const FRAME_TIME := 0.25
const SHOT_DMG := 9.0            # standard enemy bolt damage (boss shots override)
const HIT_R2 := 13.0             # standard shot-vs-enemy hit radius² (bosses override)

# Phase J boss tuning
const BOSS_ENGAGE := 200.0       # the 120 u drone gate is too small for the room
const BOSS_FIRE_RANGE := 160.0
const BOSS_SHOT_DMG := 14.0
const BOSS_CONTACT_DMG := 20.0
const MAX_SUMMONS := 4

## Per-type tuning (I3). Stats derive from the level's base numbers × these, so each
## type stays relative as the campaign scales. behavior: "chase" | "weave".
const TYPES := {
	"drone":  {"hp_mul": 1.0, "hp_add": 0,  "speed_mul": 1.0,  "fire_mul": 1.0,  "score": 100, "size": 4.2, "behavior": "chase"},
	"weaver": {"hp_mul": 1.0, "hp_add": -1, "speed_mul": 1.7,  "fire_mul": 0.85, "score": 150, "size": 3.2, "behavior": "weave"},
	"hulk":   {"hp_mul": 2.0, "hp_add": 3,  "speed_mul": 0.55, "fire_mul": 0.7,  "score": 300, "size": 5.6, "behavior": "chase"},
	"turret": {"hp_mul": 1.5, "hp_add": 2,  "speed_mul": 0.0,  "fire_mul": 1.1,  "score": 200, "size": 4.6, "behavior": "turret"},
}

var path: PathGen
var player: PlayerShip
var level: LevelDef

var enemies: Array[Dictionary] = []
## The live boss's dict (also present in `enemies`), or {} — HUD/radar poll this.
var boss := {}
var _type_frames := {}   # type_id -> Array[ImageTexture]
# V2.1: small node cache so arena-discovery and boss-summon spawn bursts (and the
# matching kill bursts) stop churning Sprite3D instantiate/queue_free mid-combat
const NODE_CACHE_CAP := 16
var _node_cache: Array[Sprite3D] = []

# V2.2 L1: debris tint per archetype (boss gibs use its own modulate tint instead).
# Approximations of each sprite's dominant hull color; the dither pass re-quantizes.
const GIB_TINTS := {
	"drone": Color(0.62, 0.64, 0.7),
	"weaver": Color(0.45, 0.72, 0.5),
	"hulk": Color(0.38, 0.44, 0.66),
	"turret": Color(0.55, 0.55, 0.58),
}


func _ready() -> void:
	_type_frames = {
		"drone": SpriteGen.drone_frames(),
		"weaver": SpriteGen.weaver_frames(),
		"hulk": SpriteGen.hulk_frames(),
		"turret": SpriteGen.turret_frames(),
		"boss": SpriteGen.boss_frames(),
	}


func clear_all() -> void:
	for e in enemies:
		_release_node(e.node)   # cache keeps up to NODE_CACHE_CAP across levels
	enemies.clear()
	boss = {}


func _acquire_node(tex: Texture2D, world_size: float) -> Sprite3D:
	if _node_cache.is_empty():
		var s := SpriteGen.make_sprite(tex, world_size)
		add_child(s)
		return s
	var c: Sprite3D = _node_cache.pop_back()
	c.texture = tex
	c.pixel_size = world_size / tex.get_width()
	c.modulate = Color.WHITE   # clears any boss tint from a previous life
	c.visible = true
	return c


func _release_node(s: Sprite3D) -> void:
	if _node_cache.size() >= NODE_CACHE_CAP:
		s.queue_free()
		return
	s.visible = false
	_node_cache.append(s)


## First frame of every enemy type (incl. boss), for the briefing shader warm-up.
func warmup_textures() -> Array:
	var texes: Array = []
	for type_id in _type_frames:
		texes.append(_type_frames[type_id][0])
	return texes


func spawn(ring_idx: int, arena_id: int, type_id := "drone") -> void:
	if enemies.size() >= ENEMY_CAP and arena_id < 0:
		return
	var t: Dictionary = TYPES.get(type_id, TYPES["drone"])
	var frames: Array = _type_frames.get(type_id, _type_frames["drone"])
	var ring: Dictionary = path.rings[ring_idx]
	var sprite := _acquire_node(frames[0], t.size)
	var pos: Vector3 = ring.p \
		+ ring.r * (randf_range(-1.0, 1.0) * ring.hw * 0.5) \
		+ ring.u * (randf_range(-1.0, 1.0) * ring.hh * 0.4)
	sprite.position = path.clamp_to_ring(pos, ring_idx, 2.5)
	if t.behavior == "turret":
		# V2.0 wall turret: anchored flush against one wall, never moves
		var side := 1.0 if randf() < 0.5 else -1.0
		sprite.position = ring.p + ring.r * (side * (ring.hw - 1.6)) \
			+ ring.u * (randf_range(-0.35, 0.25) * (ring.hh - ring.fo - ring.co))
	enemies.append({
		"node": sprite, "hp": maxi(1, int(round(level.enemy_hp * t.hp_mul)) + int(t.hp_add)),
		"fire_t": 1.5 + randf() * 2.0,
		"bob_p": randf() * TAU, "ring": ring_idx, "arena_id": arena_id,
		"anim_t": randf() * FRAME_TIME, "frame": 0, "flash_t": 0.0,
		"frames": frames, "speed": level.enemy_speed * t.speed_mul,
		"fire": level.enemy_fire * t.fire_mul, "score": int(t.score),
		"behavior": t.behavior, "weave_p": randf() * TAU, "hit_r2": HIT_R2,
		"type": type_id,
		# V2.0: late-campaign (and deep-gauntlet) turrets fire seeking shots —
		# the manual's seeking missile-wall variant. Dodge roll i-frames beat them.
		"seeker": t.behavior == "turret" and (GameState.level_index >= 5
			or (GameState.gauntlet_mode and level.enemy_speed >= 9.0)),
	})


## Phase J: the boss rides the same enemies array, so shots, splash, homing
## missiles, and the radar all handle it for free — but it takes absolute HP from
## the level (the mul/add formula tops out single digits), gets a hit radius that
## matches its sprite, and runs its own brain in _update_boss.
func spawn_boss(ring_idx: int, lvl: LevelDef) -> void:
	var ring: Dictionary = path.rings[ring_idx]
	var sprite := _acquire_node(_type_frames["boss"][0], lvl.boss_size)
	sprite.modulate = lvl.boss_tint
	sprite.position = ring.p
	boss = {
		"node": sprite, "hp": lvl.boss_hp, "max_hp": lvl.boss_hp,
		"fire_t": 2.0, "bob_p": 0.0, "ring": ring_idx, "arena_id": -1,
		"anim_t": 0.0, "frame": 0, "flash_t": 0.0,
		"frames": _type_frames["boss"], "speed": lvl.enemy_speed,
		"fire": lvl.enemy_fire, "score": lvl.boss_hp * 10, "behavior": "boss",
		"weave_p": 0.0, "hit_r2": pow(lvl.boss_size * 0.42, 2.0),
		"is_boss": true, "size": lvl.boss_size, "phase": 1,
		"volley_t": 4.0, "summon_t": 6.0, "anchor": ring.p, "home_ring": ring_idx,
	}
	enemies.append(boss)


func update_enemies(delta: float) -> void:
	for k in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[k]
		var node: Sprite3D = e.node
		# sprite animation: 2-frame leg bob, hit flash overrides briefly
		e.anim_t += delta
		if e.flash_t > 0.0:
			e.flash_t -= delta
			node.texture = e.frames[2]
		else:
			if e.anim_t >= FRAME_TIME:
				e.anim_t = 0.0
				e.frame = (e.frame + 1) % 2
			node.texture = e.frames[e.frame]
		e.bob_p += delta * 2.0
		if e.get("is_boss", false):
			_update_boss(e, delta)
			continue  # never despawns, never dies on contact
		if e.behavior == "turret":
			# V2.0 wall turret: a fixed gun, not a ram — no drift, no clamp, no
			# contact damage. Aimed shots inside 110 u; seekers on late levels.
			var turret_to_player: Vector3 = player.position - node.position
			var turret_dist := turret_to_player.length()
			if turret_dist < 110.0:
				e.fire_t -= delta
				if e.fire_t <= 0.0:
					e.fire_t = e.fire * 0.9 + randf() * e.fire * 0.5
					var taim: Vector3 = player.position \
						+ player.forward() * (player.speed * turret_dist / 24.0 * 0.35) \
						- node.position
					enemy_fired.emit(node.position, taim.normalized() * 24.0,
						SHOT_DMG + 1.0, 2.1 if e.seeker else 1.8, e.seeker)
			if e.arena_id < 0 and player.ring_idx > 20 \
					and node.position.distance_squared_to(player.position) > 90000.0:
				_release_node(node)
				enemies.remove_at(k)
			continue
		var to_player: Vector3 = player.position - node.position
		var dist := to_player.length()
		if dist < 120.0:
			var dir := to_player / maxf(dist, 0.001)
			if dist > 13.0:
				node.position += dir * (e.speed * delta)
			# weavers strafe sideways as they close — harder to draw a bead on
			if e.behavior == "weave":
				e.weave_p += delta * 3.0
				var side := dir.cross(Vector3.UP).normalized()
				node.position += side * (sin(e.weave_p) * e.speed * 0.7 * delta)
			node.position.y += sin(e.bob_p) * delta * 1.5
			e.ring = path.nearest_ring(node.position, e.ring)
			node.position = path.clamp_to_ring(node.position, e.ring, 2.2)
			e.fire_t -= delta
			if e.fire_t <= 0.0 and dist < 95.0:
				e.fire_t = e.fire * 0.8 + randf() * e.fire * 0.6
				# lead the target the way v2.2 does
				var aim: Vector3 = player.position \
					+ player.forward() * (player.speed * dist / 26.0 * 0.4) \
					- node.position
				enemy_fired.emit(node.position, aim.normalized() * 26.0, SHOT_DMG, 1.7, false)
			if dist < 4.5 and player.wall_hurt_t <= 0.0:
				player.wall_hurt_t = 0.45
				player.take_damage(CONTACT_DMG, "COLLISION")
				_kill(k, false)
				continue
		# far-behind despawn — never for locked-arena drones (they gate a door)
		if e.arena_id < 0 and player.ring_idx > 20 \
				and node.position.distance_squared_to(player.position) > 90000.0:
			_release_node(node)
			enemies.remove_at(k)


## Phase J boss brain: three HP-gated phases — aimed heavy shots, then +spread
## volleys below 66%, then frenzy + drone summons below 33%. Hovers around its
## anchor with a widening strafe, keeps a 35-70 u standoff, and rams for heavy
## contact damage without dying (unlike drones).
func _update_boss(e: Dictionary, delta: float) -> void:
	var node: Sprite3D = e.node
	var phase := 1
	var frac: float = e.hp / float(e.max_hp)
	if frac <= 0.33:
		phase = 3
	elif frac <= 0.66:
		phase = 2
	if phase != e.phase:
		e.phase = phase
		boss_phase.emit(phase)
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > BOSS_ENGAGE:
		return  # dormant until the player is in the room
	var speed_mul := 1.0 if phase == 1 else (1.3 if phase == 2 else 1.7)
	# --- movement: strafe around the anchor, close past 70 u, back off inside 35 ---
	e.weave_p += delta * 0.9 * speed_mul
	var ring: Dictionary = path.rings[e.ring]
	var target: Vector3 = e.anchor \
		+ ring.r * (sin(e.weave_p) * 14.0) + ring.u * (sin(e.weave_p * 0.63) * 6.0)
	if dist > 70.0:
		target = player.position
	elif dist < 35.0:
		target = node.position - to_player
	var dir := target - node.position
	if dir.length() > 0.5:
		node.position += dir.normalized() * (e.speed * speed_mul * delta)
	node.position.y += sin(e.bob_p) * delta * 1.2
	e.ring = maxi(path.nearest_ring(node.position, e.ring), e.home_ring - 8)
	node.position = path.clamp_to_ring(node.position, e.ring, e.size * 0.5)
	# --- aimed heavy shots (all phases; slower once volleys start) ---
	e.fire_t -= delta
	if e.fire_t <= 0.0 and dist < BOSS_FIRE_RANGE:
		e.fire_t = e.fire * 0.9 * (1.4 if phase >= 2 else 1.0)
		var aim: Vector3 = player.position \
			+ player.forward() * (player.speed * dist / 32.0 * 0.4) - node.position
		enemy_fired.emit(node.position, aim.normalized() * 32.0, BOSS_SHOT_DMG, 2.4, false)
	# --- spread volleys (phase 2+) ---
	if phase >= 2:
		e.volley_t -= delta
		if e.volley_t <= 0.0 and dist < BOSS_FIRE_RANGE:
			e.volley_t = 3.2 if phase == 2 else 2.2
			_boss_volley(node.position, 5 if phase == 2 else 7)
	# --- drone summons (phase 3) ---
	if phase == 3:
		e.summon_t -= delta
		if e.summon_t <= 0.0:
			e.summon_t = 6.0
			_boss_summon(e)
	# --- ram ---
	if dist < e.size * 0.5 + 2.0 and player.wall_hurt_t <= 0.0:
		player.wall_hurt_t = 0.45
		player.take_damage(BOSS_CONTACT_DMG, "COLLISION")
		player.bounce += to_player.normalized() * 22.0


## Horizontal fan of shots centered on the line to the player (±0.35 rad).
func _boss_volley(origin: Vector3, count: int) -> void:
	var to_player := (player.position - origin).normalized()
	for i in count:
		var ang := -0.35 + i * (0.7 / float(count - 1))
		enemy_fired.emit(origin, to_player.rotated(Vector3.UP, ang) * 30.0, SHOT_DMG, 1.7, false)


## Phase 3: the boss ejects escort drones — capped so the room never floods.
## spawn() may refuse (ENEMY_CAP), so tag only entries that actually appeared.
func _boss_summon(e: Dictionary) -> void:
	var live := 0
	for en in enemies:
		if en.get("summoned", false):
			live += 1
	var wanted := mini(2, MAX_SUMMONS - live)
	if wanted <= 0:
		return
	for i in wanted:
		var before := enemies.size()
		spawn(e.ring, -1, "drone")
		if enemies.size() > before:
			var d: Dictionary = enemies[enemies.size() - 1]
			d["summoned"] = true
			d.node.position = e.node.position + Vector3(
				randf_range(-6.0, 6.0), randf_range(-4.0, 4.0), randf_range(-6.0, 6.0))
	exploded.emit(e.node.position, false)  # ejection puff


## Damage every enemy within radius of pos (MISSILE splash). Returns kills.
func splash_damage(pos: Vector3, radius: float, dmg: int) -> int:
	var kills := 0
	var r2 := radius * radius
	for k in range(enemies.size() - 1, -1, -1):
		if enemies[k].node.position.distance_squared_to(pos) <= r2:
			if _hurt(k, dmg):
				kills += 1
	return kills


## Direct hit. Returns true if the enemy died.
func hit_enemy(index: int, dmg: int) -> bool:
	return _hurt(index, dmg)


## Closest living enemy's sprite node to `from`, or null if none — the lock target
## for heat-seeking missiles (I2b). Re-queried each frame so a missile retargets if
## its locked enemy dies.
func nearest_enemy(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in enemies:
		var d: float = e.node.position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = e.node
	return best


## V2.2 L2b: live-enemy census around a point — the music intensity feed.
func near_count(from: Vector3, r: float) -> int:
	var r2 := r * r
	var n := 0
	for e in enemies:
		if e.node.position.distance_squared_to(from) < r2:
			n += 1
	return n


func _hurt(index: int, dmg: int) -> bool:
	var e: Dictionary = enemies[index]
	e.hp -= dmg
	e.flash_t = 0.09
	if e.hp <= 0:
		_kill(index, true)
		return true
	return false


func _kill(index: int, scored: bool) -> void:
	var e: Dictionary = enemies[index]
	if e.get("is_boss", false):
		# triple offset blast around the big boom; game.gd wakes the exit ring
		exploded.emit(e.node.position, true)
		for i in 3:
			exploded.emit(e.node.position + Vector3(
				randf_range(-8.0, 8.0), randf_range(-5.0, 5.0), randf_range(-8.0, 8.0)), false)
		boss = {}
	else:
		exploded.emit(e.node.position, false)
	if e.get("type", "") == "turret":
		turret_destroyed.emit(e.node.position)   # V2.0: chains nearby fuel cells
	# V2.2 L1: debris burst — chunk count scales with the kill's heft
	var gcount := 6
	if e.get("is_boss", false):
		gcount = 20
	elif e.get("type", "") == "hulk":
		gcount = 12
	var gtint: Color = e.node.modulate if e.get("is_boss", false) \
		else GIB_TINTS.get(e.get("type", ""), Color(0.6, 0.6, 0.65))
	gibs_requested.emit(e.node.position,
		(e.node.position - player.position).normalized() * 4.0, e.ring, gcount, gtint)
	# Phase J feedback: nearby kills thump the camera a little
	if e.node.position.distance_squared_to(player.position) < 2500.0:
		player.shake = minf(0.6, player.shake + 0.12)
	if scored:
		GameState.register_kill(int(e.score))   # streak-multiplied (Phase J)
		# Phase J drop roll — one chance per scored kill (never the boss itself;
		# its reward is the exit ring). Hulks are tanky, so they drop more often.
		if not e.get("is_boss", false):
			var mult: float = 1.6 if e.get("type", "") == "hulk" else 1.0
			var roll := randf()
			if roll < 0.12 * mult:
				drop_spawned.emit(e.node.position, e.ring, "shield")
			elif roll < 0.22 * mult:
				drop_spawned.emit(e.node.position, e.ring, "energy")
			elif roll < 0.30 * mult:
				drop_spawned.emit(e.node.position, e.ring, "missile")
			elif roll < 0.34 * mult:
				drop_spawned.emit(e.node.position, e.ring, "bomb")   # V2.0: rare
	enemy_killed.emit(e.arena_id)
	_release_node(e.node)
	enemies.remove_at(index)
	if e.get("is_boss", false):
		boss_killed.emit()
