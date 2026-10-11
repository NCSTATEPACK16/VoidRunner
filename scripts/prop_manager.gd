class_name PropManager
extends Node3D
## K3 destructible props: fuel cells scattered through arenas. Shootable; a
## detonation splashes nearby enemies (and the player, lightly) and chain-fuses
## other cells in range — the 1995 manual's exploding barrels, VOID RUNNER
## flavored. Destroying every cell in a level is the optional secondary
## objective (bonus scored in game._level_complete). Distance checks only,
## no physics bodies, same as every other system in this game.

signal cell_destroyed
## v4c: a generator, reactor or anchor went down (ids are spawn order, stable per seed).
signal objective_destroyed(kind: String, id: int, pos: Vector3)

const HIT_R2 := 5.0            # player-shot-vs-cell collision sphere²
const CHAIN_RADIUS := 13.0
const CHAIN_FUSE := 0.18       # stagger so chains read as pop-pop-pop, not one bang
const SPLASH_RADIUS := 13.0
const ENEMY_SPLASH_DMG := 45
const PLAYER_SPLASH_DMG := 8.0
const SCORE := 75
const DEFAULT_SPLASH_DMG := 6.0   # splash() on an objective when the caller gives no amount
const FLASH_TIME := 0.09
const ANIM_TIME := 0.45           # objective idle-frame swap
## v4c objective kinds. hp is calibrated against NEUTRON (2 bolts x 1 dmg per 0.17 s,
## ~11.8 dmg/s): generator ~2.5 s, reactor ~8 s, anchor ~10 s of steady fire.
## hit_r = world-unit shot radius, splash_taken scales splash damage, boom = blast radius,
## size = sprite width in world units.
const OBJECTIVE := {
	"generator": {"hp": 30.0, "hit_r": 3.2, "splash_taken": 1.0, "score": 400, "boom": 15.0, "size": 6.5},
	"reactor":   {"hp": 95.0, "hit_r": 5.2, "splash_taken": 0.6, "score": 1200, "boom": 22.0, "size": 11.0},
	"anchor":    {"hp": 120.0, "hit_r": 6.0, "splash_taken": 0.5, "score": 1500, "boom": 24.0, "size": 13.0},
}

var player: PlayerShip
var enemy_mgr: EnemyManager
var shot_mgr: ShotManager

## {node, hp, fuse (-1 = idle), id, kind ("cell" or an OBJECTIVE key), hit_r2};
## objectives add {skin, facing, flash_t}
var props: Array[Dictionary] = []
var _tex: ImageTexture
var _anim_t := 0.0
var _anim_frame := 0
var _spawned := 0   # ids are spawn order, stable for a level's seed (checkpoints)


func _ready() -> void:
	_tex = SpriteForge.prop_texture()   # 3.0: baked canister


func clear_all() -> void:
	for p in props:
		p.node.queue_free()
	props.clear()
	_spawned = 0


func warmup_textures() -> Array:
	var out: Array = [_tex]
	var seen := {}
	for p in props:
		if p.kind != "cell" and not seen.has(p.kind):
			seen[p.kind] = true
			out.append(p.skin.tex[0])
	return out


func spawn_prop(pos: Vector3) -> void:
	var sprite := SpriteGen.make_sprite(_tex, 3.0)
	sprite.position = pos
	add_child(sprite)
	props.append({"node": sprite, "hp": 2, "fuse": -1.0, "id": _spawned,
			"kind": "cell", "hit_r2": HIT_R2})
	_spawned += 1


## v4c: a generator, reactor or anchor. Returns its prop id (spawn order, same
## counter as the cells, so ids stay stable per level seed).
func spawn_objective(pos: Vector3, kind: String) -> int:
	assert(OBJECTIVE.has(kind))
	var def: Dictionary = OBJECTIVE[kind]
	var skin: Dictionary = SpriteForge.sprite_set(kind)
	var sprite := SpriteGen.make_sprite(skin.tex[0], float(def.size))
	sprite.position = pos
	add_child(sprite)
	var id := _spawned
	var a := float(id) * 2.399963   # golden-angle yaw so neighbours don't match
	props.append({"node": sprite, "hp": float(def.hp), "fuse": -1.0, "id": id,
			"kind": kind, "hit_r2": float(def.hit_r) * float(def.hit_r),
			"skin": skin, "facing": Vector3(sin(a), 0.0, cos(a)), "flash_t": 0.0})
	_spawned += 1
	_skin(props[props.size() - 1])
	return id


## Number of fuel cells (objectives excluded): the secondary-objective total.
func cell_count() -> int:
	var n := 0
	for p in props:
		if p.kind == "cell":
			n += 1
	return n


## Live objectives of `kind` ("" = every kind).
func objectives_left(kind := "") -> int:
	var n := 0
	for p in props:
		if p.kind != "cell" and (kind == "" or p.kind == kind):
			n += 1
	return n


## Live objectives as {kind, id, pos}, for the HUD counter and automap.
func objective_positions() -> Array:
	var out := []
	for p in props:
		if p.kind != "cell":
			out.append({"kind": p.kind, "id": p.id, "pos": p.node.position})
	return out


## Pick the baked angle for where the camera sits, and the hit flash while it's fresh.
func _skin(p: Dictionary) -> void:
	var st: Dictionary = p.skin
	var node: Sprite3D = p.node
	var cam: Vector3 = (player.position if player else Vector3.ZERO) - node.position
	var a := SpriteForge.angle_index(p.facing, cam, st.angles)
	if p.flash_t > 0.0:
		node.texture = st.flash[a]
	else:
		node.texture = st.tex[a * st.anim + (_anim_frame % st.anim)]


## Checkpoints: the ids of cells already blown (or fused) this level.
func gone_ids() -> Array:
	var live := {}
	for p in props:
		if p.fuse < 0.0:
			live[p.id] = true
	var out := []
	for i in _spawned:
		if not live.has(i):
			out.append(i)
	return out


## A resume removes the cells the checkpoint had already blown, without a blast.
func remove_ids(ids: Array) -> void:
	for i in range(props.size() - 1, -1, -1):
		if int(props[i].id) in ids:
			props[i].node.queue_free()
			props.remove_at(i)


## Direct hit from a player shot (wired into shot_manager's collision loop).
func damage_prop(index: int, dmg: float) -> void:
	var p: Dictionary = props[index]
	if p.fuse >= 0.0:
		return
	p.hp -= dmg
	if p.kind != "cell":
		p.flash_t = FLASH_TIME
	if p.hp <= 0:
		p.fuse = 0.0   # detonates on the next update tick


## Fuse every idle cell within radius — chains and MISSILE splash both land here.
## Objectives never fuse: they take `dmg` (falling off linearly with distance, scaled
## by their splash_taken) and blow only when it kills them.
func splash(pos: Vector3, radius: float, dmg := DEFAULT_SPLASH_DMG) -> void:
	var r2 := radius * radius
	for p in props:
		if p.fuse >= 0.0:
			continue
		var d2: float = p.node.position.distance_squared_to(pos)
		if d2 >= r2:
			continue
		if p.kind == "cell":
			p.fuse = CHAIN_FUSE
		else:
			p.hp -= dmg * (1.0 - sqrt(d2) / radius) * float(OBJECTIVE[p.kind].splash_taken)
			p.flash_t = FLASH_TIME
			if p.hp <= 0.0:
				p.fuse = 0.0


func update_props(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= ANIM_TIME:
		_anim_t = 0.0
		_anim_frame ^= 1
	for i in range(props.size() - 1, -1, -1):
		var p: Dictionary = props[i]
		if p.kind != "cell":
			p.flash_t = maxf(0.0, p.flash_t - delta)
			_skin(p)
		if p.fuse < 0.0:
			continue
		p.fuse -= delta
		if p.fuse <= 0.0:
			var pos: Vector3 = p.node.position
			var kind: String = p.kind
			var id: int = p.id
			p.node.queue_free()
			props.remove_at(i)
			if kind == "cell":
				_explode(pos)
			else:
				_explode_objective(kind, id, pos)


func _explode_objective(kind: String, id: int, pos: Vector3) -> void:
	var def: Dictionary = OBJECTIVE[kind]
	var boom: float = def.boom
	GameState.score += int(def.score)
	shot_mgr.spawn_explosion(pos, true)
	for k in 3:   # a few more bangs around the core so a centrepiece goes out big
		var a := TAU * (k + float(id % 5) * 0.2) / 3.0
		shot_mgr.spawn_explosion(pos + Vector3(cos(a), (k - 1) * 0.5, sin(a)) * boom * 0.25, true)
	enemy_mgr.splash_damage(pos, boom, ENEMY_SPLASH_DMG)
	var d2 := pos.distance_squared_to(player.position)
	if d2 < boom * boom:
		player.take_damage(PLAYER_SPLASH_DMG, "BLAST PROXIMITY")
	if d2 < 900.0:
		player.shake = minf(0.9, player.shake + 0.6)
	splash(pos, CHAIN_RADIUS)   # still lights nearby cells, and chips neighbouring objectives
	objective_destroyed.emit(kind, id, pos)


func _explode(pos: Vector3) -> void:
	GameState.score += SCORE
	GameState.level_props += 1
	shot_mgr.spawn_explosion(pos, true)
	enemy_mgr.splash_damage(pos, SPLASH_RADIUS, ENEMY_SPLASH_DMG)
	if pos.distance_squared_to(player.position) < SPLASH_RADIUS * SPLASH_RADIUS:
		player.take_damage(PLAYER_SPLASH_DMG, "BLAST PROXIMITY")
	elif pos.distance_squared_to(player.position) < 400.0:
		player.shake = minf(0.6, player.shake + 0.25)
	splash(pos, CHAIN_RADIUS)
	cell_destroyed.emit()
