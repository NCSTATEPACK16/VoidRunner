class_name EnemyManager
extends Node3D
## Sprite-billboard drones (PLAN.md C3/C4 + F3). AI is the v2.2 port: drift toward
## the player inside 120 u, bob, timed fire with target lead — and, critically, the
## ring-clamp every frame that fixed the "unreachable enemy" bug. Locked-arena
## drones never despawn, so kill-locked doors can always be opened.

signal enemy_killed(arena_id: int)
signal enemy_fired(origin: Vector3, velocity: Vector3)
signal exploded(pos: Vector3, big: bool)

const CONTACT_DMG := 12.0
const ENEMY_CAP := 42
const FRAME_TIME := 0.25

## Per-type tuning (I3). Stats derive from the level's base numbers × these, so each
## type stays relative as the campaign scales. behavior: "chase" | "weave".
const TYPES := {
	"drone":  {"hp_mul": 1.0, "hp_add": 0,  "speed_mul": 1.0,  "fire_mul": 1.0,  "score": 100, "size": 4.2, "behavior": "chase"},
	"weaver": {"hp_mul": 1.0, "hp_add": -1, "speed_mul": 1.7,  "fire_mul": 0.85, "score": 150, "size": 3.2, "behavior": "weave"},
	"hulk":   {"hp_mul": 2.0, "hp_add": 3,  "speed_mul": 0.55, "fire_mul": 0.7,  "score": 300, "size": 5.6, "behavior": "chase"},
}

var path: PathGen
var player: PlayerShip
var level: LevelDef

var enemies: Array[Dictionary] = []
var _type_frames := {}   # type_id -> Array[ImageTexture]


func _ready() -> void:
	_type_frames = {
		"drone": SpriteGen.drone_frames(),
		"weaver": SpriteGen.weaver_frames(),
		"hulk": SpriteGen.hulk_frames(),
	}


func clear_all() -> void:
	for e in enemies:
		e.node.queue_free()
	enemies.clear()


func spawn(ring_idx: int, arena_id: int, type_id := "drone") -> void:
	if enemies.size() >= ENEMY_CAP and arena_id < 0:
		return
	var t: Dictionary = TYPES.get(type_id, TYPES["drone"])
	var frames: Array = _type_frames.get(type_id, _type_frames["drone"])
	var ring: Dictionary = path.rings[ring_idx]
	var sprite := SpriteGen.make_sprite(frames[0], t.size)
	var pos: Vector3 = ring.p \
		+ ring.r * (randf_range(-1.0, 1.0) * ring.hw * 0.5) \
		+ ring.u * (randf_range(-1.0, 1.0) * ring.hh * 0.4)
	sprite.position = path.clamp_to_ring(pos, ring_idx, 2.5)
	add_child(sprite)
	enemies.append({
		"node": sprite, "hp": maxi(1, int(round(level.enemy_hp * t.hp_mul)) + int(t.hp_add)),
		"fire_t": 1.5 + randf() * 2.0,
		"bob_p": randf() * TAU, "ring": ring_idx, "arena_id": arena_id,
		"anim_t": randf() * FRAME_TIME, "frame": 0, "flash_t": 0.0,
		"frames": frames, "speed": level.enemy_speed * t.speed_mul,
		"fire": level.enemy_fire * t.fire_mul, "score": int(t.score),
		"behavior": t.behavior, "weave_p": randf() * TAU,
	})


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
				enemy_fired.emit(node.position, aim.normalized() * 26.0)
			if dist < 4.5 and player.wall_hurt_t <= 0.0:
				player.wall_hurt_t = 0.45
				player.take_damage(CONTACT_DMG, "COLLISION")
				_kill(k, false)
				continue
		# far-behind despawn — never for locked-arena drones (they gate a door)
		if e.arena_id < 0 and player.ring_idx > 20 \
				and node.position.distance_squared_to(player.position) > 90000.0:
			node.queue_free()
			enemies.remove_at(k)


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
	exploded.emit(e.node.position, false)
	if scored:
		GameState.score += int(e.score)
	enemy_killed.emit(e.arena_id)
	e.node.queue_free()
	enemies.remove_at(index)
