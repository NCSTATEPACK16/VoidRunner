class_name PickupManager
extends Node3D
## Phase J pickups: shield / energy / missile drops from destroyed enemies.
## Billboarded sprites that bob in place, magnet toward the player when close,
## and expire (blinking) if ignored — fly through to collect. Distance checks,
## no physics bodies, same as every other system in this game.

signal collected(kind: String, value: int)   # value: salvage amount, else 0

const MAGNET_RANGE_SQ := 14.0 * 14.0
const MAGNET_SPEED := 18.0
const COLLECT_RANGE_SQ := 9.0
const LIFETIME := 12.0
const BLINK_AT := 3.0     # blink for the last N seconds before expiring

const EFFECT := {
	"shield": 20.0,   # shields restored
	"energy": 30.0,   # afterburner/laser energy restored
	"missile": 3,     # missiles added
	"bomb": 1,        # V2.0 plasma bomb added (capped at GameState.PLASMA_MAX)
}

var player: PlayerShip
var path: PathGen

var _pickups: Array[Dictionary] = []
var _stations: Array[Dictionary] = []   # boss resupply: {kind, pos, bob_p, node|null}
var _frames := {}   # 3.0: kind -> baked spin frames (SpriteForge)
var _spin_t := 0.0
const SPIN_FPS := 10.0


func _ready() -> void:
	for kind in SpriteModels.PICKUPS:
		_frames[kind] = SpriteForge.pickup_frames(kind)


func clear_all() -> void:
	for p in _pickups:
		p.node.queue_free()
	_pickups.clear()
	for s in _stations:
		if s.node:
			s.node.queue_free()
	_stations.clear()


func warmup_textures() -> Array:
	var texes: Array = []
	for kind in _frames:
		texes.append(_frames[kind][0])
	return texes


## 3.0: every pickup spins on the same clock (one texture swap each).
func _spin(node: Sprite3D, kind: String, phase: float) -> void:
	var fr: Array = _frames[kind]
	node.texture = fr[int(_spin_t * SPIN_FPS + phase) % fr.size()]


## Boss resupply station: a fixed pickup on the boss room's back wall. Never
## expires; collecting it empties the slot until replenish_stations() (called on
## each boss phase transition) respawns it at its anchor position.
func add_station(pos: Vector3, kind: String) -> void:
	var station := {"kind": kind, "pos": pos, "bob_p": randf() * TAU, "node": null}
	_stations.append(station)
	_respawn_station(station)


func replenish_stations() -> void:
	for s in _stations:
		if s.node == null:
			_respawn_station(s)


func _respawn_station(s: Dictionary) -> void:
	var sprite := SpriteGen.make_sprite(_frames[s.kind][0], 3.4)
	sprite.position = s.pos
	add_child(sprite)
	s.node = sprite


func spawn_drop(pos: Vector3, ring: int, kind: String, value := 0) -> void:
	var sprite := SpriteGen.make_sprite(_frames[kind][0], 2.6)
	sprite.position = path.clamp_to_ring(pos, ring, 2.0)
	add_child(sprite)
	_pickups.append({
		"node": sprite, "kind": kind, "bob_p": randf() * TAU, "life": LIFETIME,
		"value": value,   # V2.2 L3b: salvage amount rides the drop
	})


func update_pickups(delta: float) -> void:
	# V2.2 L3c: magnet coil rank widens the pull radius (squared-space compare)
	var m := GameState.magnet_mult()
	var magnet_r2 := MAGNET_RANGE_SQ * m * m
	_spin_t += delta
	for i in range(_pickups.size() - 1, -1, -1):
		var p: Dictionary = _pickups[i]
		var node: Sprite3D = p.node
		p.life -= delta
		if p.life <= 0.0:
			node.queue_free()
			_pickups.remove_at(i)
			continue
		p.bob_p += delta * 2.4
		node.position.y += sin(p.bob_p) * delta * 0.6
		_spin(node, p.kind, p.bob_p)
		var to_player: Vector3 = player.position - node.position
		var d2 := to_player.length_squared()
		if d2 < COLLECT_RANGE_SQ:
			_collect(p.kind, p.get("value", 0))
			node.queue_free()
			_pickups.remove_at(i)
			continue
		if d2 < magnet_r2:
			node.position += to_player.normalized() * (MAGNET_SPEED * delta)
		node.visible = p.life > BLINK_AT or int(p.life * 6.0) % 2 == 0
	for s in _stations:
		if s.node == null:
			continue
		var node: Sprite3D = s.node
		s.bob_p += delta * 2.4
		node.position = s.pos + Vector3.UP * sin(s.bob_p) * 0.5
		_spin(node, s.kind, s.bob_p)
		if player.position.distance_squared_to(node.position) < COLLECT_RANGE_SQ:
			_collect(s.kind)
			node.queue_free()
			s.node = null


func _collect(kind: String, value := 0) -> void:
	match kind:
		"shield":
			GameState.shields += EFFECT.shield
		"energy":
			GameState.energy += EFFECT.energy
		"missile":
			GameState.missiles += int(EFFECT.missile)
		"bomb":
			GameState.plasma_bombs += int(EFFECT.bomb)
		"salvage":   # V2.2 L3b: straight into the level's unbanked haul
			GameState.salvage_run += value
			GameState.salvage_changed.emit(GameState.salvage_total())
	collected.emit(kind, value)
