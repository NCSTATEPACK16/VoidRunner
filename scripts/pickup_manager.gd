class_name PickupManager
extends Node3D
## Phase J pickups: shield / energy / missile drops from destroyed enemies.
## Billboarded sprites that bob in place, magnet toward the player when close,
## and expire (blinking) if ignored — fly through to collect. Distance checks,
## no physics bodies, same as every other system in this game.

signal collected(kind: String)

const MAGNET_RANGE_SQ := 14.0 * 14.0
const MAGNET_SPEED := 18.0
const COLLECT_RANGE_SQ := 9.0
const LIFETIME := 12.0
const BLINK_AT := 3.0     # blink for the last N seconds before expiring

const EFFECT := {
	"shield": 20.0,   # shields restored
	"energy": 30.0,   # afterburner/laser energy restored
	"missile": 3,     # missiles added
}

var player: PlayerShip
var path: PathGen

var _pickups: Array[Dictionary] = []
var _textures := {}


func _ready() -> void:
	for kind in EFFECT:
		_textures[kind] = SpriteGen.pickup_texture(kind)


func clear_all() -> void:
	for p in _pickups:
		p.node.queue_free()
	_pickups.clear()


func spawn_drop(pos: Vector3, ring: int, kind: String) -> void:
	var sprite := SpriteGen.make_sprite(_textures[kind], 2.2)
	sprite.position = path.clamp_to_ring(pos, ring, 2.0)
	add_child(sprite)
	_pickups.append({
		"node": sprite, "kind": kind, "bob_p": randf() * TAU, "life": LIFETIME,
	})


func update_pickups(delta: float) -> void:
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
		var to_player: Vector3 = player.position - node.position
		var d2 := to_player.length_squared()
		if d2 < COLLECT_RANGE_SQ:
			_collect(p.kind)
			node.queue_free()
			_pickups.remove_at(i)
			continue
		if d2 < MAGNET_RANGE_SQ:
			node.position += to_player.normalized() * (MAGNET_SPEED * delta)
		node.visible = p.life > BLINK_AT or int(p.life * 6.0) % 2 == 0


func _collect(kind: String) -> void:
	match kind:
		"shield":
			GameState.shields += EFFECT.shield
		"energy":
			GameState.energy += EFFECT.energy
		"missile":
			GameState.missiles += int(EFFECT.missile)
	collected.emit(kind)
