class_name ShotManager
extends Node3D
## Player + enemy projectiles and sprite explosions (PLAN.md F2/F4/F5).
## Projectiles are billboarded sprites (bright shapes, not meshes) per the
## authenticity research; MISSILE carries the v2.2 2-second fuse + splash blast.

signal player_hit(damage: float)

const PLAYER_HIT_RANGE_SQ := 5.5  # enemy shot vs player
const ENEMY_SHOT_DMG := 9.0       # fallback; each enemy shot now carries its own dmg
# player-shot-vs-enemy hit radius² is per-enemy (e.hit_r2) — a 4 u drone and a
# 20 u boss cannot share one collision sphere (Phase J)

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


func clear_all() -> void:
	for arr in [_pshots, _eshots, _explosions, _sparks]:
		for s in arr:
			s.node.queue_free()
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
	for i in w.count:
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
		var sprite := SpriteGen.make_sprite(tex, 1.6 * w.sprite_scale)
		sprite.position = player.position + fwd * 3.0 + right * lateral + Vector3.UP * -0.45
		add_child(sprite)
		var shot := {
			"node": sprite, "vel": dir * w.speed, "dmg": w.damage,
			"life": (w.fuse + 0.5) if w.fuse > 0.0 else 1.4,
			"fuse": w.fuse, "splash": w.splash, "splash_dmg": w.splash_damage,
			"homing": w.homing, "homing_turn": w.homing_turn,
		}
		_pshots.append(shot)
	GameState.level_shots += w.count   # accuracy is per-projectile (Phase J)
	player.flash_muzzle(w.color)
	AudioSys.play_laser(w.freq)


func fire_enemy(origin: Vector3, velocity: Vector3, dmg := ENEMY_SHOT_DMG,
		shot_size := 1.7) -> void:
	var sprite := SpriteGen.make_sprite(_enemy_shot_tex, shot_size)
	sprite.position = origin
	add_child(sprite)
	_eshots.append({"node": sprite, "vel": velocity, "life": 5.0, "dmg": dmg})


func detonate(pos: Vector3, radius: float, dmg: int) -> void:
	spawn_explosion(pos, true)
	enemy_mgr.splash_damage(pos, radius, dmg)
	if prop_mgr:
		prop_mgr.splash(pos, radius)
	if pos.distance_squared_to(player.position) < 400.0:
		player.shake = minf(0.6, player.shake + 0.25)


func spawn_explosion(pos: Vector3, big: bool) -> void:
	var sprite := SpriteGen.make_sprite(_explosion_frames[0], 7.0 if big else 4.5)
	sprite.position = pos
	add_child(sprite)
	_explosions.append({"node": sprite, "t": 0.0})
	var n := 6 if big else 4
	for i in n:
		var spark := SpriteGen.make_sprite(_spark_tex, 1.1)
		spark.position = pos
		add_child(spark)
		_sparks.append({
			"node": spark, "t": 0.6,
			"vel": Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14)),
		})
	var light := _boom_lights[_boom_cursor]
	_boom_cursor = (_boom_cursor + 1) % _boom_lights.size()
	light.position = pos
	light.light_energy = 3.2 if big else 2.2
	AudioSys.play_boom(big)


## K4: blue spark puff at the dodge origin — same lifecycle as explosion sparks.
func spawn_dodge_burst(pos: Vector3) -> void:
	for i in 5:
		var spark := SpriteGen.make_sprite(_dodge_spark_tex, 1.1)
		spark.position = pos
		add_child(spark)
		_sparks.append({
			"node": spark, "t": 0.6,
			"vel": Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10)),
		})


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
	# --- player shots ---
	for i in range(_pshots.size() - 1, -1, -1):
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
			for j in range(enemy_mgr.enemies.size() - 1, -1, -1):
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
		if not dead and not boom and prop_mgr:
			for k in range(prop_mgr.props.size() - 1, -1, -1):
				if s.node.position.distance_squared_to(prop_mgr.props[k].node.position) \
						< PropManager.HIT_R2:
					prop_mgr.damage_prop(k, s.dmg)
					GameState.level_hits += 1
					if s.splash > 0.0:
						boom = true
					dead = true
					break
		if boom:
			detonate(s.node.position, s.splash, s.splash_dmg)
			dead = true
		if dead:
			s.node.queue_free()
			_pshots.remove_at(i)
	# --- enemy shots ---
	for q in range(_eshots.size() - 1, -1, -1):
		var es: Dictionary = _eshots[q]
		es.node.position += es.vel * delta
		es.life -= delta
		var kill: bool = es.life <= 0.0
		if not kill and es.node.position.distance_squared_to(player.position) < PLAYER_HIT_RANGE_SQ:
			player_hit.emit(es.get("dmg", ENEMY_SHOT_DMG))
			kill = true
		if kill:
			es.node.queue_free()
			_eshots.remove_at(q)
	# --- explosion animations ---
	for x in range(_explosions.size() - 1, -1, -1):
		var ex: Dictionary = _explosions[x]
		ex.t += delta
		var frame := int(ex.t / 0.15)
		if frame >= _explosion_frames.size():
			ex.node.queue_free()
			_explosions.remove_at(x)
		else:
			ex.node.texture = _explosion_frames[frame]
	# --- sparks ---
	for p in range(_sparks.size() - 1, -1, -1):
		var sp: Dictionary = _sparks[p]
		sp.node.position += sp.vel * delta
		sp.t -= delta
		sp.node.pixel_size = maxf(0.01, sp.t / 0.6) * 1.1 / 8.0
		if sp.t <= 0.0:
			sp.node.queue_free()
			_sparks.remove_at(p)


func enemy_shot_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for es in _eshots:
		out.append(es.node.position)
	return out
