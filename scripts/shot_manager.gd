class_name ShotManager
extends Node3D
## Player + enemy projectiles and sprite explosions (PLAN.md F2/F4/F5).
## Projectiles are billboarded sprites (bright shapes, not meshes) per the
## authenticity research; MISSILE carries the v2.2 2-second fuse + splash blast.

signal player_hit(damage: float, from_pos: Vector3)   # V2.2 L1e: source for HUD arcs

const PLAYER_HIT_RANGE_SQ := 5.5  # enemy shot vs player
const ENEMY_SHOT_DMG := 9.0       # fallback; each enemy shot now carries its own dmg
const THREAT_RANGE_SQ := 70.0 * 70.0   # V2.1: threat lamp radius (was Hud's)
# player-shot-vs-enemy hit radius² is per-enemy (e.hit_r2) — a 4 u drone and a
# 20 u boss cannot share one collision sphere (Phase J)

# V2.1 pooling: every billboard this manager draws comes from one flat Sprite3D
# pool — nodes are created once, hidden with visible=false, never freed during
# play. instantiate/queue_free churn during fuel-cell chains, boss deaths and
# plasma bombs was a busy-combat stall on the single-threaded web build.
const POOL_PREWARM := 128
const POOL_HARD_CAP := 256        # > every per-class cap below combined
const PSHOT_CAP := 48             # overflow: skip (fire rates can't reach this)
const ESHOT_CAP := 64             # overflow: reuse-oldest (oldest bolt vanishes)
const EXPLOSION_CAP := 12         # overflow: reuse-oldest (finishes an old one)
const SPARK_CAP := 60             # overflow: skip (pure garnish)
const SHOCK_CAP := 6              # 3.0 big-blast shock rings; overflow: skip
const PUFF_CAP := 48              # 3.0 missile-trail / aftermath smoke; overflow: skip
## 3.0 FX timing: a 10-frame fireball at this rate lasts ~0.65 s
const BOOM_FRAME_T := 0.065
const SHOCK_FRAME_T := 0.05
const PUFF_LIFE := 0.5
const TRAIL_EVERY := 0.04         # a missile drops a smoke puff this often

var player: PlayerShip
var enemy_mgr: EnemyManager
var prop_mgr: PropManager   # K3: fuel cells are shootable + missile splash chains them

var _pshots: Array[Dictionary] = []
var _eshots: Array[Dictionary] = []
var _explosions: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _shocks: Array[Dictionary] = []   # 3.0
var _puffs: Array[Dictionary] = []    # 3.0
## 3.0: explosion flashes are LightRig feeds, not OmniLight3Ds — a small ring of
## {pos, energy, color} slots that decay each frame (feed_lights pushes them).
var _booms: Array[Dictionary] = []
var _boom_cursor := 0
const BOOM_SLOTS := 3
## Glowing shots light the walls as they fly: this many nearest ones get a light.
const SHOT_LIGHTS := 4
var _explosion_frames: Array[ImageTexture] = []
var _shock_frames: Array[ImageTexture] = []    # 3.0 FxGen sets
var _eshot_frames: Array[ImageTexture] = []
var _smoke_frames: Array[ImageTexture] = []
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
	# 3.0: noise fireballs, spiky plasma, smoke — FxGen, painted once and cached
	_explosion_frames = FxGen.fireball_frames()
	_shock_frames = FxGen.shockwave_frames()
	_eshot_frames = FxGen.plasma_frames()
	_smoke_frames = FxGen.smoke_frames()
	_enemy_shot_tex = _eshot_frames[0]
	_spark_tex = SpriteGen.star_texture(Palette.ORANGE_3, Palette.ORANGE_1, 8)
	_dodge_spark_tex = SpriteGen.star_texture(Palette.CYAN_3, Palette.BLUE_2, 8)
	_missile_tex = SpriteGen.missile_texture()
	for i in BOOM_SLOTS:
		_booms.append({"pos": Vector3.ZERO, "energy": 0.0, "color": Color("ff7733")})
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
	for arr in [_pshots, _eshots, _explosions, _sparks, _shocks, _puffs]:
		for s in arr:
			_release(s.node)   # pooled nodes survive level transitions
		arr.clear()
	for b in _booms:   # no explosion light survives a level transition / warm-up
		b.energy = 0.0


## Every texture a fight can draw, for the briefing-screen shader warm-up.
## Also pre-populates the per-weapon bolt cache so no texture is built mid-flight.
func warmup_textures(weapon_list: Array[WeaponDef]) -> Array:
	var texes: Array = [_explosion_frames[0], _enemy_shot_tex, _spark_tex,
		_dodge_spark_tex, _missile_tex, _shock_frames[0], _smoke_frames[0]]
	for w in weapon_list:
		if w.fuse > 0.0:
			continue
		texes.append(_bolt_frames(w)[0])
	return texes


## 3.0: a weapon's two shimmer frames — a glowing orb drawn in its color ramp.
func _bolt_frames(w: WeaponDef) -> Array:
	if not _bolt_cache.has(w.display_name):
		_bolt_cache[w.display_name] = FxGen.orb_frames(FxGen.ramp_for(w.color))
	return _bolt_cache[w.display_name]


## Briefly energize one boom light during warm-up (kept from the OmniLight era —
## harmless now that lights are shader uniforms, and it keeps the flash path hot).
func warmup_boom_light(pos: Vector3, on: bool) -> void:
	_booms[0].pos = pos
	_booms[0].energy = 1.0 if on else 0.0


## 3.0: this frame's explosion flashes + the nearest glowing shots, into LightRig.
func feed_lights(rig: LightRig) -> void:
	for b in _booms:
		if b.energy > 0.02:
			rig.add(b.pos, b.color, b.energy, 38.0)
	var fed := 0
	var i := _pshots.size() - 1
	while i >= 0 and fed < SHOT_LIGHTS:
		var s: Dictionary = _pshots[i]
		rig.add(s.node.position, s.get("color", Color.WHITE), 0.55, 15.0)
		fed += 1
		i -= 1
	var q := _eshots.size() - 1
	fed = 0
	while q >= 0 and fed < SHOT_LIGHTS:
		var es: Dictionary = _eshots[q]
		if es.node.position.distance_squared_to(player.position) < 3600.0:
			rig.add(es.node.position, Color(1.0, 0.45, 0.15), 0.5, 13.0)
			fed += 1
		q -= 1


## Energy of every explosion-flash slot (tests: nothing leaks out of a warm-up).
func boom_energies() -> Array[float]:
	var out: Array[float] = []
	for b in _booms:
		out.append(b.energy)
	return out


## V2.2 L3c: testable seam — base pellet count + SCATTER mark bonus. `weapons`
## is wired by game._ready; the count applies inside fire_player.
var weapons: Array = []


func pellet_count(widx: int) -> int:
	var base: int = weapons[widx].count if widx < weapons.size() else 1
	return base + GameState.weapon_add(widx, "pellets")


func fire_player(w: WeaponDef) -> void:
	var fwd := player.forward()
	var right := fwd.cross(Vector3.UP).normalized()
	var spawned := 0
	# V2.2 L3c: marks scale the shot at spawn time — the dict carries final stats
	var widx := GameState.weapon_index
	var count: int = w.count + GameState.weapon_add(widx, "pellets")
	# 3.0: POWER CORE doubles every hit and swells the bolts so it shows
	var core := GameState.power_on("powercore")
	var dmg: float = w.damage * GameState.weapon_mult(widx, "damage") * (2.0 if core else 1.0)
	var spd: float = w.speed * GameState.weapon_mult(widx, "speed")
	var spl: float = w.splash * GameState.weapon_mult(widx, "splash")
	for i in count:
		if _pshots.size() >= PSHOT_CAP:
			break
		var lateral: float
		if count == 2:
			lateral = -1.25 if i == 0 else 1.25
		else:
			lateral = (i - (count - 1) / 2.0) * 0.9
		var ang := 0.0
		if count > 2:
			ang = (i - (count - 1) / 2.0) * w.spread
		var dir := (fwd + right * sin(ang)).normalized()
		var frames: Array = [_missile_tex] if w.fuse > 0.0 else _bolt_frames(w)
		var sprite := _acquire(frames[0], 1.8 * w.sprite_scale * (1.35 if core else 1.0))
		if sprite == null:
			break
		sprite.position = player.position + fwd * 3.0 + right * lateral + Vector3.UP * -0.45
		var shot := {
			"node": sprite, "vel": dir * spd, "dmg": dmg,
			"life": (w.fuse + 0.5) if w.fuse > 0.0 else 1.4,
			"fuse": w.fuse, "splash": spl, "splash_dmg": w.splash_damage * (2 if core else 1),
			"homing": w.homing, "homing_turn": w.homing_turn, "color": w.color,
			"frames": frames, "trail": 0.12,   # first puff once clear of the nose
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
	var sprite := _acquire(_enemy_shot_tex, shot_size * 1.2)
	if sprite == null:
		return
	sprite.position = origin
	# Step 3: every enemy and boss bolt passes here, so difficulty scales it once
	_eshots.append({"node": sprite, "vel": velocity * GameState.enemy_shot_speed(),
		"life": 5.0, "dmg": dmg,
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
	var sprite := _acquire(_explosion_frames[0], 9.0 if big else 6.0)
	if sprite:
		sprite.position = pos
		_explosions.append({"node": sprite, "t": 0.0})
	if big and _shocks.size() < SHOCK_CAP:   # 3.0: a shock ring races out of big blasts
		var ring := _acquire(_shock_frames[0], 13.0)
		if ring:
			ring.position = pos
			_shocks.append({"node": ring, "t": 0.0})
	var n := 6 if big else 4
	for i in n:
		if not _spawn_spark(_spark_tex, pos, 14.0):
			break
	var boom: Dictionary = _booms[_boom_cursor]
	_boom_cursor = (_boom_cursor + 1) % _booms.size()
	boom.pos = pos
	boom.energy = 2.4 if big else 1.6
	AudioSys.play_boom(big)


## 3.0: one pooled smoke puff (missile trails).
func _spawn_puff(pos: Vector3, size: float) -> void:
	if _puffs.size() >= PUFF_CAP:
		return
	var p := _acquire(_smoke_frames[0], size)
	if p == null:
		return
	p.position = pos
	_puffs.append({"node": p, "t": PUFF_LIFE})


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
	for b in _booms:
		b.energy *= pow(0.002, delta)
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
		# 3.0: bolts shimmer between their two frames; missiles leave smoke
		var fr: Array = s.frames
		if fr.size() > 1:
			s.node.texture = fr[int(s.life * 16.0) % fr.size()]
		if s.fuse > 0.0:
			s.trail -= delta
			if s.trail <= 0.0:
				s.trail = TRAIL_EVERY
				_spawn_puff(s.node.position, 1.3)
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
		es.node.texture = _eshot_frames[int(es.life * 12.0) % _eshot_frames.size()]   # 3.0 spin
		var kill: bool = es.life <= 0.0
		if not kill and es.node.position.distance_squared_to(player.position) < PLAYER_HIT_RANGE_SQ:
			player_hit.emit(es.get("dmg", ENEMY_SHOT_DMG), es.node.position)
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
		var frame := int(ex.t / BOOM_FRAME_T)
		if frame >= _explosion_frames.size():
			_release(ex.node)
			_explosions.remove_at(x)
		else:
			ex.node.texture = _explosion_frames[frame]
		x -= 1
	# --- 3.0 shock rings ---
	var h := _shocks.size() - 1
	while h >= 0:
		var sh: Dictionary = _shocks[h]
		sh.t += delta
		var sf := int(sh.t / SHOCK_FRAME_T)
		if sf >= _shock_frames.size():
			_release(sh.node)
			_shocks.remove_at(h)
		else:
			sh.node.texture = _shock_frames[sf]
		h -= 1
	# --- 3.0 smoke puffs: drift up, age through their dissolve frames ---
	var u := _puffs.size() - 1
	while u >= 0:
		var pf: Dictionary = _puffs[u]
		pf.t -= delta
		if pf.t <= 0.0:
			_release(pf.node)
			_puffs.remove_at(u)
		else:
			pf.node.position.y += delta * 1.5
			var k := int((1.0 - pf.t / PUFF_LIFE) * _smoke_frames.size())
			pf.node.texture = _smoke_frames[mini(k, _smoke_frames.size() - 1)]
		u -= 1
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
