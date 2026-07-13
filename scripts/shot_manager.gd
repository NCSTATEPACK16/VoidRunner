class_name ShotManager
extends Node3D
## Player + enemy projectiles and sprite explosions (PLAN.md F2/F4/F5).
## Projectiles are billboarded sprites (bright shapes, not meshes) per the
## authenticity research; MISSILE carries the v2.2 2-second fuse + splash blast.

signal player_hit(damage: float)

const PLAYER_HIT_RANGE_SQ := 5.5  # enemy shot vs player
const ENEMY_SHOT_DMG := 9.0       # fallback; each enemy shot now carries its own dmg
const THREAT_RANGE_SQ := 70.0 * 70.0   # V2.1: threat lamp radius (was Hud's)
# player-shot-vs-enemy hit radius² is per-enemy (e.hit_r2) — a 4 u drone and a
# 20 u boss cannot share one collision sphere (Phase J)

# V2.1 pooling: every billboard this manager draws comes from one flat Sprite3D
# pool — nodes are created once, hidden with visible=false, never freed during
# play. instantiate/queue_free churn during fuel-cell chains, boss deaths and
# plasma bombs was a busy-combat stall on the single-threaded web build.
const POOL_PREWARM := 96
const POOL_HARD_CAP := 192        # > PSHOT+ESHOT+EXPLOSION+SPARK caps combined
const PSHOT_CAP := 48             # overflow: skip (fire rates can't reach this)
const ESHOT_CAP := 64             # overflow: reuse-oldest (oldest bolt vanishes)
const EXPLOSION_CAP := 12         # overflow: reuse-oldest (finishes an old one)
const SPARK_CAP := 60             # overflow: skip (pure garnish)

var player: PlayerShip
var enemy_mgr: EnemyManager
var prop_mgr: PropManager   # K3: fuel cells are shootable + missile splash chains them

var _pshots: Array[Dictionary] = []
var _eshots: Array[Dictionary] = []
var _explosions: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _boom_lights: Array[OmniLight3D] = []
var _boom_cursor := 0
var _explosion_frames: Array[ImageTexture] = []
var _enemy_shot_tex: ImageTexture
var _spark_tex: ImageTexture
var _dodge_spark_tex: ImageTexture   # K4: cool blue, reads as thrusters not damage
var _missile_tex: ImageTexture
var _bolt_cache := {}
var _pool_free: Array[Sprite3D] = []
var _pool_total := 0
# V2.1: filled once per frame inside the eshot loop (it already touches every
# shot) and read by both the HUD threat scan and the radar — replaces the two
# fresh Array[Vector3] allocations enemy_shot_positions() made every frame
var eshot_cache := PackedVector3Array()
var threat_near := false


func _ready() -> void:
	_explosion_frames = SpriteGen.explosion_frames()
	_enemy_shot_tex = SpriteGen.star_texture(Palette.ORANGE_2, Palette.RED_2)
	_spark_tex = SpriteGen.star_texture(Palette.ORANGE_3, Palette.ORANGE_1, 8)
	_dodge_spark_tex = SpriteGen.star_texture(Palette.CYAN_3, Palette.BLUE_2, 8)
	_missile_tex = SpriteGen.missile_texture()
	for i in 3:
		var light := OmniLight3D.new()
		light.light_color = Color("ff7733")
		light.light_energy = 0.0
		light.omni_range = 45.0
		add_child(light)
		_boom_lights.append(light)
	for i in POOL_PREWARM:   # before the briefing warm-up rig ever runs
		var s := SpriteGen.make_sprite(_spark_tex, 1.0)
		s.visible = false
		add_child(s)
		_pool_free.append(s)
		_pool_total += 1


## Pop a pooled Sprite3D (or grow up to the hard cap). Callers enforce their
## per-class caps first, so null only means the belt-and-braces cap tripped.
func _acquire(tex: Texture2D, world_size: float) -> Sprite3D:
	var s: Sprite3D
	if not _pool_free.is_empty():
		s = _pool_free.pop_back()
	elif _pool_total < POOL_HARD_CAP:
		s = SpriteGen.make_sprite(tex, world_size)
		add_child(s)
		_pool_total += 1
		return s
	else:
		return null
	s.texture = tex
	s.pixel_size = world_size / tex.get_width()
	s.visible = true
	return s


func _release(s: Sprite3D) -> void:
	s.visible = false
	_pool_free.append(s)


func clear_all() -> void:
	for arr in [_pshots, _eshots, _explosions, _sparks]:
		for s in arr:
			_release(s.node)   # pooled nodes survive level transitions
		arr.clear()


## Every texture a fight can draw, for the briefing-screen shader warm-up.
## Also pre-populates the per-weapon bolt cache so no texture is built mid-flight.
func warmup_textures(weapon_list: Array[WeaponDef]) -> Array:
	var texes: Array = [_explosion_frames[0], _enemy_shot_tex, _spark_tex,
		_dodge_spark_tex, _missile_tex]
	for w in weapon_list:
		if w.fuse > 0.0:
			continue
		if not _bolt_cache.has(w.display_name):
			_bolt_cache[w.display_name] = SpriteGen.bolt_texture(w.color, w.color.darkened(0.4))
		texes.append(_bolt_cache[w.display_name])
	return texes


## Briefly energize one boom light during warm-up so lit shader variants compile
## before the first explosion; off again when the rig is freed.
func warmup_boom_light(pos: Vector3, on: bool) -> void:
	_boom_lights[0].position = pos
	_boom_lights[0].light_energy = 1.0 if on else 0.0


func fire_player(w: WeaponDef) -> void:
	var fwd := player.forward()
	var right := fwd.cross(Vector3.UP).normalized()
	var spawned := 0
	for i in w.count:
		if _pshots.size() >= PSHOT_CAP:
			break
		var lateral: float
		if w.count == 2:
			lateral = -1.25 if i == 0 else 1.25
		else:
			lateral = (i - (w.count - 1) / 2.0) * 0.9
		var ang := 0.0
		if w.count > 2:
			ang = (i - (w.count - 1) / 2.0) * w.spread
		var dir := (fwd + right * sin(ang)).normalized()
		var tex: Texture2D
		if w.fuse > 0.0:
			tex = _missile_tex
		else:
			if not _bolt_cache.has(w.display_name):
				_bolt_cache[w.display_name] = SpriteGen.bolt_texture(w.color, w.color.darkened(0.4))
			tex = _bolt_cache[w.display_name]
		var sprite := _acquire(tex, 1.6 * w.sprite_scale)
		if sprite == null:
			break
		sprite.position = player.position + fwd * 3.0 + right * lateral + Vector3.UP * -0.45
		var shot := {
			"node": sprite, "vel": dir * w.speed, "dmg": w.damage,
			"life": (w.fuse + 0.5) if w.fuse > 0.0 else 1.4,
			"fuse": w.fuse, "splash": w.splash, "splash_dmg": w.splash_damage,
			"homing": w.homing, "homing_turn": w.homing_turn,
		}
		_pshots.append(shot)
		spawned += 1
	GameState.level_shots += spawned   # accuracy is per-projectile (Phase J)
	player.flash_muzzle(w.color)
	AudioSys.play_laser(w.freq)


func fire_enemy(origin: Vector3, velocity: Vector3, dmg := ENEMY_SHOT_DMG,
		shot_size := 1.7, seeker := false) -> void:
	if _eshots.size() >= ESHOT_CAP:
		_release(_eshots[0].node)   # reuse-oldest: the stalest bolt vanishes
		_eshots.remove_at(0)
	var sprite := _acquire(_enemy_shot_tex, shot_size)
	if sprite == null:
		return
	sprite.position = origin
	_eshots.append({"node": sprite, "vel": velocity, "life": 5.0, "dmg": dmg,
		"seeker": seeker})


func detonate(pos: Vector3, radius: float, dmg: int) -> void:
	spawn_explosion(pos, true)
	enemy_mgr.splash_damage(pos, radius, dmg)
	if prop_mgr:
		prop_mgr.splash(pos, radius)
	if pos.distance_squared_to(player.position) < 400.0:
		player.shake = minf(0.6, player.shake + 0.25)


func spawn_explosion(pos: Vector3, big: bool) -> void:
	if _explosions.size() >= EXPLOSION_CAP:
		_release(_explosions[0].node)   # reuse-oldest: it was about to finish anyway
		_explosions.remove_at(0)
	var sprite := _acquire(_explosion_frames[0], 7.0 if big else 4.5)
	if sprite:
		sprite.position = pos
		_explosions.append({"node": sprite, "t": 0.0})
	var n := 6 if big else 4
	for i in n:
		if not _spawn_spark(_spark_tex, pos, 14.0):
			break
	var light := _boom_lights[_boom_cursor]
	_boom_cursor = (_boom_cursor + 1) % _boom_lights.size()
	light.position = pos
	light.light_energy = 3.2 if big else 2.2
	AudioSys.play_boom(big)


## K4: blue spark puff at the dodge origin — same lifecycle as explosion sparks.
func spawn_dodge_burst(pos: Vector3) -> void:
	for i in 5:
		if not _spawn_spark(_dodge_spark_tex, pos, 10.0):
			break


func _spawn_spark(tex: Texture2D, pos: Vector3, spread: float) -> bool:
	if _sparks.size() >= SPARK_CAP:
		return false
	var spark := _acquire(tex, 1.1)
	if spark == null:
		return false
	spark.position = pos
	_sparks.append({
		"node": spark, "t": 0.6,
		"vel": Vector3(randf_range(-spread, spread), randf_range(-spread, spread),
			randf_range(-spread, spread)),
	})
	return true


## Rotate a heat-seeking shot's velocity toward the nearest enemy by a capped angle,
## preserving speed (I2b). Uses rotated() rather than slerp so a missile that
## overshoots and has to U-turn stays stable near the 180° case. No enemies → flies
## straight; retargets automatically since the nearest is re-queried each frame.
func _steer_homing(s: Dictionary, delta: float) -> void:
	var target := enemy_mgr.nearest_enemy(s.node.position)
	if target == null:
		return
	var to_target: Vector3 = target.position - s.node.position
	if to_target.length_squared() < 0.0001:
		return
	var cur: Vector3 = s.vel.normalized()
	var des := to_target.normalized()
	var ang := cur.angle_to(des)
	if ang < 0.0001:
		return
	var axis := cur.cross(des)
	if axis.length_squared() < 1e-8:
		axis = Vector3.UP   # near-opposite target: any perpendicular starts the turn
	s.vel = cur.rotated(axis.normalized(), minf(ang, s.homing_turn * delta)) * s.vel.length()


func update_shots(delta: float) -> void:
	for light in _boom_lights:
		light.light_energy *= pow(0.002, delta)
	# hot loops are index-walked `while`s: range() allocates an Array per call,
	# and these run every frame (nested per shot × enemy in the worst case)
	# --- player shots ---
	var i := _pshots.size() - 1
	while i >= 0:
		var s: Dictionary = _pshots[i]
		if s.homing:
			_steer_homing(s, delta)
		s.node.position += s.vel * delta
		s.life -= delta
		var boom := false
		if s.fuse > 0.0:
			s.fuse -= delta
			if s.fuse <= 0.0:
				boom = true
		var dead: bool = s.life <= 0.0
		if not dead and not boom:
			var j := enemy_mgr.enemies.size() - 1
			while j >= 0:
				var ene: Dictionary = enemy_mgr.enemies[j]
				if s.node.position.distance_squared_to(ene.node.position) \
						< ene.get("hit_r2", 13.0):
					# a contact hit always lands its direct damage; splash shots
					# then detonate on top (Phase J — makes MISSILE matter vs bosses)
					enemy_mgr.hit_enemy(j, s.dmg)
					GameState.level_hits += 1
					if s.splash > 0.0:
						boom = true
					dead = true
					break
				j -= 1
		if not dead and not boom and prop_mgr:
			var k := prop_mgr.props.size() - 1
			while k >= 0:
				if s.node.position.distance_squared_to(prop_mgr.props[k].node.position) \
						< PropManager.HIT_R2:
					prop_mgr.damage_prop(k, s.dmg)
					GameState.level_hits += 1
					if s.splash > 0.0:
						boom = true
					dead = true
					break
				k -= 1
		if boom:
			detonate(s.node.position, s.splash, s.splash_dmg)
			dead = true
		if dead:
			_release(s.node)
			_pshots.remove_at(i)
		i -= 1
	# --- enemy shots ---
	eshot_cache.resize(0)
	threat_near = false
	var q := _eshots.size() - 1
	while q >= 0:
		var es: Dictionary = _eshots[q]
		if es.get("seeker", false):
			# V2.0 seeker turret shots: gentle capped turn toward the player —
			# slow enough that a dodge roll (or a hard bank) beats them
			var cur: Vector3 = es.vel.normalized()
			var des: Vector3 = (player.position - es.node.position).normalized()
			var ang := cur.angle_to(des)
			if ang > 0.0001:
				var axis := cur.cross(des)
				if axis.length_squared() < 1e-8:
					axis = Vector3.UP
				es.vel = cur.rotated(axis.normalized(), minf(ang, 1.2 * delta)) \
					* es.vel.length()
		es.node.position += es.vel * delta
		es.life -= delta
		var kill: bool = es.life <= 0.0
		if not kill and es.node.position.distance_squared_to(player.position) < PLAYER_HIT_RANGE_SQ:
			player_hit.emit(es.get("dmg", ENEMY_SHOT_DMG))
			kill = true
		if kill:
			_release(es.node)
			_eshots.remove_at(q)
		else:
			eshot_cache.append(es.node.position)
			if es.node.position.distance_squared_to(player.position) < THREAT_RANGE_SQ:
				threat_near = true
		q -= 1
	# --- explosion animations ---
	var x := _explosions.size() - 1
	while x >= 0:
		var ex: Dictionary = _explosions[x]
		ex.t += delta
		var frame := int(ex.t / 0.15)
		if frame >= _explosion_frames.size():
			_release(ex.node)
			_explosions.remove_at(x)
		else:
			ex.node.texture = _explosion_frames[frame]
		x -= 1
	# --- sparks ---
	var p := _sparks.size() - 1
	while p >= 0:
		var sp: Dictionary = _sparks[p]
		sp.node.position += sp.vel * delta
		sp.t -= delta
		sp.node.pixel_size = maxf(0.01, sp.t / 0.6) * 1.1 / 8.0
		if sp.t <= 0.0:
			_release(sp.node)
			_sparks.remove_at(p)
		p -= 1
