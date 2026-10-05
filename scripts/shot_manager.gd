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

# v4 perf groundwork: no node per effect. Every bolt, blast, ring, puff and spark is
# a record in a capped array (the simulation), and sync_batches() draws each layer
# through one FxBatch, one draw call per layer instead of one per effect. V2.1's
# Sprite3D pool had already stopped the instantiate/queue_free churn; this also
# stops a busy fight from costing hundreds of draw calls on single-threaded WebGL.
# Each cap below is also its layer's FxBatch capacity.
const PSHOT_CAP := 48             # overflow: skip (fire rates can't reach this)
const ESHOT_CAP := 64             # overflow: reuse-oldest (oldest bolt vanishes)
## Re-audit Step 6: infighting. A stray enemy bolt that reaches another enemy (never
## its own shooter, never a boss) does this much, in enemy HP — a NEUTRON hit — and
## only after it has cleared its shooter's hull.
const INFIGHT_DMG := 1
const INFIGHT_GRACE := 0.15
# The check runs on packed copies of the enemies' positions and hit radii (built
# once per frame, on demand), and each bolt is tested on alternate frames: a bolt
# moves under 1 u a frame against a ~7 u hit circle, so nothing slips through, and
# the worst case (64 bolts x 42 enemies) stays a fraction of a millisecond.
var _inf_pos := PackedVector3Array()
var _inf_r2 := PackedFloat32Array()
var _inf_nodes: Array[Node3D] = []
var _inf_valid := false
var _inf_parity := 0
const EXPLOSION_CAP := 12         # overflow: reuse-oldest (finishes an old one)
const SPARK_CAP := 60             # overflow: skip (pure garnish)
const SHOCK_CAP := 6              # 3.0 big-blast shock rings; overflow: skip
const PUFF_CAP := 48              # 3.0 missile-trail / aftermath smoke; overflow: skip
## 3.0 FX timing — v4a: a 14-frame fireball at this rate lasts 0.70 s (was 10 at
## 0.065 = 0.65 s), so the blast keeps its length and gains smoothness
const BOOM_FRAME_T := 0.05
const SHOCK_FRAME_T := 0.05
const PUFF_LIFE := 0.5
## v4a: a big blast leaves this many slower, bigger smoke puffs hanging as it ends
const AFTERMATH_PUFFS := 3
const AFTERMATH_LIFE := 1.4
const TRAIL_EVERY := 0.04         # a missile drops a smoke puff this often
const SHOCK_SIZE := 13.0
const SPARK_SIZE := 1.1           # world size at birth; sparks shrink as they die
const SPARK_LIFE := 0.6
## Spark atlas cells: hot orange (blasts, infighting) and, K4, cool blue for the
## dodge burst, so it reads as thrusters, not damage. v4b adds green for a mender's
## repairs.
const SPARK_HOT := 0
const SPARK_DODGE := 1
const SPARK_MEND := 2

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
var _missile_tex: ImageTexture
var _bolt_cache := {}
## v4: the effect layers, one FxBatch (one draw call) each
var _fx_pbolt: FxBatch
var _fx_ebolt: FxBatch
var _fx_boom: FxBatch
var _fx_shock: FxBatch
var _fx_smoke: FxBatch
var _fx_spark: FxBatch
var _bolt_cell := {}   # weapon display_name -> its first cell in the player-bolt atlas
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
	_missile_tex = SpriteGen.missile_texture()
	for i in BOOM_SLOTS:
		_booms.append({"pos": Vector3.ZERO, "energy": 0.0, "color": Color("ff7733")})
	# v4: every layer is built once, before the briefing warm-up rig ever runs
	_fx_pbolt = _layer([_missile_tex], PSHOT_CAP)   # filled per weapon (see `weapons`)
	_fx_ebolt = _layer(_eshot_frames, ESHOT_CAP)
	_fx_boom = _layer(_explosion_frames, EXPLOSION_CAP)
	_fx_shock = _layer(_shock_frames, SHOCK_CAP)
	_fx_smoke = _layer(_smoke_frames, PUFF_CAP)
	_fx_spark = _layer([SpriteGen.star_texture(Palette.ORANGE_3, Palette.ORANGE_1, 8),
		SpriteGen.star_texture(Palette.CYAN_3, Palette.BLUE_2, 8),
		SpriteGen.star_texture(Palette.GREEN_2, Palette.GREEN_1, 8)], SPARK_CAP)
	_build_bolt_layer()


func _layer(frames: Array, cap: int) -> FxBatch:
	var b := FxBatch.new(frames, cap)
	add_child(b)
	return b


## v4: every effect layer (the warm-up shows one of each; tests read their counts).
func layers() -> Array[FxBatch]:
	var out: Array[FxBatch] = [_fx_pbolt, _fx_ebolt, _fx_boom, _fx_shock, _fx_smoke,
		_fx_spark]
	return out


func clear_all() -> void:
	for arr in [_pshots, _eshots, _explosions, _sparks, _shocks, _puffs]:
		arr.clear()
	for b in _booms:   # no explosion light survives a level transition / warm-up
		b.energy = 0.0
	sync_batches()


## v4: one instance of every layer in view during the briefing, so the batch shader
## variants compile there and not on the first shot; the warm-up's teardown calls
## sync_batches(), which clears them.
func warmup_batches(at: Vector3, step: Vector3) -> void:
	var all := layers()
	for i in all.size():
		all[i].begin()
		all[i].add(at + step * i, 0.7, 0)
		all[i].end()


## 3.0: a weapon's two shimmer frames — a glowing orb drawn in its color ramp.
func _bolt_frames(w: WeaponDef) -> Array:
	if not _bolt_cache.has(w.display_name):
		_bolt_cache[w.display_name] = FxGen.orb_frames(FxGen.ramp_for(w.color))
	return _bolt_cache[w.display_name]


## v4: every weapon's shimmer frames (the missile's single frame) side by side in the
## player-bolt atlas, so all player bolts draw in one call. Built when the weapons
## arrive in game._ready, so no texture is ever made mid-flight.
func _build_bolt_layer() -> void:
	var frames: Array = []
	_bolt_cell.clear()
	for w: WeaponDef in weapons:
		_bolt_cell[w.display_name] = frames.size()
		frames.append_array([_missile_tex] if w.fuse > 0.0 else _bolt_frames(w))
	_fx_pbolt.set_frames(frames if not frames.is_empty() else [_missile_tex])


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
		rig.add(s.pos, s.get("color", Color.WHITE), 0.55, 15.0)
		fed += 1
		i -= 1
	var q := _eshots.size() - 1
	fed = 0
	while q >= 0 and fed < SHOT_LIGHTS:
		var es: Dictionary = _eshots[q]
		if es.pos.distance_squared_to(player.position) < 3600.0:
			rig.add(es.pos, Color(1.0, 0.45, 0.15), 0.5, 13.0)
			fed += 1
		q -= 1


## Energy of every explosion-flash slot (tests: nothing leaks out of a warm-up).
func boom_energies() -> Array[float]:
	var out: Array[float] = []
	for b in _booms:
		out.append(b.energy)
	return out


## V2.2 L3c: testable seam — base pellet count + SCATTER mark bonus. `weapons`
## is wired by game._ready; the count applies inside fire_player. v4: setting it
## also lays every weapon's bolt frames into the player-bolt atlas.
var weapons: Array = []:
	set(value):
		weapons = value
		if is_node_ready():
			_build_bolt_layer()


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
	var cell: int = _bolt_cell.get(w.display_name, 0)
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
		var shot := {
			"pos": player.position + fwd * 3.0 + right * lateral + Vector3.UP * -0.45,
			"size": 1.8 * w.sprite_scale * (1.35 if core else 1.0),
			"cell": cell, "cells": 1 if w.fuse > 0.0 else 2,
			"vel": dir * spd, "dmg": dmg,
			"life": (w.fuse + 0.5) if w.fuse > 0.0 else 1.4,
			"fuse": w.fuse, "splash": spl, "splash_dmg": w.splash_damage * (2 if core else 1),
			"homing": w.homing, "homing_turn": w.homing_turn, "color": w.color,
			"trail": 0.12,   # first puff once clear of the nose
		}
		_pshots.append(shot)
		spawned += 1
	GameState.level_shots += spawned   # accuracy is per-projectile (Phase J)
	player.flash_muzzle(w.color)
	AudioSys.play_laser(w.freq)


func fire_enemy(origin: Vector3, velocity: Vector3, dmg := ENEMY_SHOT_DMG,
		shot_size := 1.7, seeker := false, src: Node3D = null) -> void:
	if _eshots.size() >= ESHOT_CAP:
		_eshots.remove_at(0)   # reuse-oldest: the stalest bolt vanishes
	# Step 3: every enemy and boss bolt passes here, so difficulty scales it once
	_eshots.append({"pos": origin, "size": shot_size * 1.2,
		"vel": velocity * GameState.enemy_shot_speed(),
		"life": 5.0, "dmg": dmg, "src": src, "age": 0.0,
		"seeker": seeker})


## Re-audit Step 6: a stray bolt against every enemy but its shooter and bosses.
## Kills score like the chain kills mines and fuel cells already make.
func _infight(es: Dictionary) -> bool:
	if not _inf_valid:
		_build_infight_cache()
	var pos: Vector3 = es.pos
	for j in range(_inf_pos.size() - 1, -1, -1):
		if pos.distance_squared_to(_inf_pos[j]) < _inf_r2[j] and _inf_nodes[j] != es.src:
			enemy_mgr.hit_enemy(j, INFIGHT_DMG)
			_inf_valid = false   # that hit may have removed an enemy
			for i in 2:
				_spawn_spark(SPARK_HOT, pos, 8.0)
			return true
	return false


## Bosses get a negative radius, so they can never be hit by stray fire.
func _build_infight_cache() -> void:
	var n := enemy_mgr.enemies.size()
	_inf_pos.resize(n)
	_inf_r2.resize(n)
	_inf_nodes.resize(n)
	for j in n:
		var ene: Dictionary = enemy_mgr.enemies[j]
		_inf_pos[j] = (ene.node as Node3D).position
		_inf_r2[j] = -1.0 if ene.get("is_boss", false) else float(ene.get("hit_r2", 13.0))
		_inf_nodes[j] = ene.node
	_inf_valid = true


func detonate(pos: Vector3, radius: float, dmg: int) -> void:
	spawn_explosion(pos, true)
	enemy_mgr.splash_damage(pos, radius, dmg)
	if prop_mgr:
		prop_mgr.splash(pos, radius)
	if pos.distance_squared_to(player.position) < 400.0:
		player.shake = minf(0.6, player.shake + 0.25)


func spawn_explosion(pos: Vector3, big: bool) -> void:
	if _explosions.size() >= EXPLOSION_CAP:
		_explosions.remove_at(0)   # reuse-oldest: it was about to finish anyway
	_explosions.append({"pos": pos, "t": 0.0, "big": big, "size": 9.0 if big else 6.0})
	if big and _shocks.size() < SHOCK_CAP:   # 3.0: a shock ring races out of big blasts
		_shocks.append({"pos": pos, "t": 0.0})
	var n := 6 if big else 4
	for i in n:
		if not _spawn_spark(SPARK_HOT, pos, 14.0):
			break
	var boom: Dictionary = _booms[_boom_cursor]
	_boom_cursor = (_boom_cursor + 1) % _booms.size()
	boom.pos = pos
	boom.energy = 2.4 if big else 1.6
	AudioSys.play_boom(big)


## 3.0: one smoke puff (missile trails, v4a blast aftermath).
func _spawn_puff(pos: Vector3, size: float, life := PUFF_LIFE) -> void:
	if _puffs.size() >= PUFF_CAP:
		return
	_puffs.append({"pos": pos, "size": size, "t": life, "life": life})


## K4: blue spark puff at the dodge origin — same lifecycle as explosion sparks.
func spawn_dodge_burst(pos: Vector3) -> void:
	for i in 5:
		if not _spawn_spark(SPARK_DODGE, pos, 10.0):
			break


## v4b: a mender's repair lands — green sparks on the patched hull and a chime.
func spawn_mend_sparks(pos: Vector3) -> void:
	for i in 5:
		if not _spawn_spark(SPARK_MEND, pos + Vector3.UP * 0.6, 6.0):
			break
	AudioSys.play_mend()


func _spawn_spark(cell: int, pos: Vector3, spread: float) -> bool:
	if _sparks.size() >= SPARK_CAP:
		return false
	_sparks.append({
		"pos": pos, "cell": cell, "t": SPARK_LIFE,
		"vel": Vector3(randf_range(-spread, spread), randf_range(-spread, spread),
			randf_range(-spread, spread)),
	})
	return true


## Rotate a heat-seeking shot's velocity toward the nearest enemy by a capped angle,
## preserving speed (I2b). Uses rotated() rather than slerp so a missile that
## overshoots and has to U-turn stays stable near the 180° case. No enemies → flies
## straight; retargets automatically since the nearest is re-queried each frame.
func _steer_homing(s: Dictionary, delta: float) -> void:
	var target := enemy_mgr.nearest_enemy(s.pos)
	if target == null:
		return
	var to_target: Vector3 = target.position - s.pos
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
		s.pos += s.vel * delta
		s.life -= delta
		# 3.0: missiles leave smoke (bolts shimmer in sync_batches)
		if s.fuse > 0.0:
			s.trail -= delta
			if s.trail <= 0.0:
				s.trail = TRAIL_EVERY
				_spawn_puff(s.pos, 1.3)
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
				if s.pos.distance_squared_to(ene.node.position) < ene.get("hit_r2", 13.0):
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
				if s.pos.distance_squared_to(prop_mgr.props[k].node.position) \
						< PropManager.HIT_R2:
					prop_mgr.damage_prop(k, s.dmg)
					GameState.level_hits += 1
					if s.splash > 0.0:
						boom = true
					dead = true
					break
				k -= 1
		if boom:
			detonate(s.pos, s.splash, s.splash_dmg)
			dead = true
		if dead:
			_pshots.remove_at(i)
		i -= 1
	# --- enemy shots ---
	_inf_valid = false   # re-audit Step 6: enemies moved since the last frame
	_inf_parity ^= 1
	eshot_cache.resize(0)
	threat_near = false
	var q := _eshots.size() - 1
	while q >= 0:
		var es: Dictionary = _eshots[q]
		if es.get("seeker", false):
			# V2.0 seeker turret shots: gentle capped turn toward the player —
			# slow enough that a dodge roll (or a hard bank) beats them
			var cur: Vector3 = es.vel.normalized()
			var des: Vector3 = (player.position - es.pos).normalized()
			var ang := cur.angle_to(des)
			if ang > 0.0001:
				var axis := cur.cross(des)
				if axis.length_squared() < 1e-8:
					axis = Vector3.UP
				es.vel = cur.rotated(axis.normalized(), minf(ang, 1.2 * delta)) \
					* es.vel.length()
		es.pos += es.vel * delta
		es.life -= delta
		var kill: bool = es.life <= 0.0
		if not kill and es.pos.distance_squared_to(player.position) < PLAYER_HIT_RANGE_SQ:
			player_hit.emit(es.get("dmg", ENEMY_SHOT_DMG), es.pos)
			kill = true
		if not kill and es.src != null:
			es.age += delta
			if es.age > INFIGHT_GRACE and (q & 1) == _inf_parity and _infight(es):
				kill = true
		if kill:
			_eshots.remove_at(q)
		else:
			eshot_cache.append(es.pos)
			if es.pos.distance_squared_to(player.position) < THREAT_RANGE_SQ:
				threat_near = true
		q -= 1
	# --- explosion animations ---
	var x := _explosions.size() - 1
	while x >= 0:
		var ex: Dictionary = _explosions[x]
		ex.t += delta
		if int(ex.t / BOOM_FRAME_T) >= _explosion_frames.size():
			if ex.get("big", false):   # v4a: aftermath smoke hangs where it burst
				var at: Vector3 = ex.pos
				for k in AFTERMATH_PUFFS:
					_spawn_puff(at + Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 1.0),
						randf_range(-1.5, 1.5)), 4.5, AFTERMATH_LIFE)
			_explosions.remove_at(x)
		x -= 1
	# --- 3.0 shock rings ---
	var h := _shocks.size() - 1
	while h >= 0:
		var sh: Dictionary = _shocks[h]
		sh.t += delta
		if int(sh.t / SHOCK_FRAME_T) >= _shock_frames.size():
			_shocks.remove_at(h)
		h -= 1
	# --- 3.0 smoke puffs: drift up (they age through their frames in sync_batches) ---
	var u := _puffs.size() - 1
	while u >= 0:
		var pf: Dictionary = _puffs[u]
		pf.t -= delta
		if pf.t <= 0.0:
			_puffs.remove_at(u)
		else:
			pf.pos += Vector3(0.0, delta * 1.5, 0.0)
		u -= 1
	# --- sparks ---
	var p := _sparks.size() - 1
	while p >= 0:
		var sp: Dictionary = _sparks[p]
		sp.pos += sp.vel * delta
		sp.t -= delta
		if sp.t <= 0.0:
			_sparks.remove_at(p)
		p -= 1


## v4: draw every live effect, one FxBatch (one draw call) per layer. game.gd calls
## this once a frame after everything that can spawn an effect has run; clear_all
## and the warm-up teardown call it too. Frames are picked here from each record.
func sync_batches() -> void:
	_fx_pbolt.begin()
	for s in _pshots:   # 3.0: bolts shimmer between their two frames
		_fx_pbolt.add(s.pos, s.size, s.cell + int(s.life * 16.0) % int(s.cells))
	_fx_pbolt.end()
	_fx_ebolt.begin()
	for es in _eshots:   # 3.0 spin
		_fx_ebolt.add(es.pos, es.size, int(es.life * 12.0) % _eshot_frames.size())
	_fx_ebolt.end()
	_fx_boom.begin()
	for ex in _explosions:
		_fx_boom.add(ex.pos, ex.size, int(ex.t / BOOM_FRAME_T))
	_fx_boom.end()
	_fx_shock.begin()
	for sh in _shocks:
		_fx_shock.add(sh.pos, SHOCK_SIZE, int(sh.t / SHOCK_FRAME_T))
	_fx_shock.end()
	_fx_smoke.begin()
	for pf in _puffs:   # age through the dissolve frames
		_fx_smoke.add(pf.pos, pf.size,
			int((1.0 - pf.t / float(pf.life)) * _smoke_frames.size()))
	_fx_smoke.end()
	_fx_spark.begin()
	for sp in _sparks:   # shrink as they die
		_fx_spark.add(sp.pos, maxf(0.01, sp.t / SPARK_LIFE) * SPARK_SIZE, sp.cell)
	_fx_spark.end()
