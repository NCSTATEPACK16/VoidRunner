class_name PropManager
extends Node3D
## K3 destructible props: fuel cells scattered through arenas. Shootable; a
## detonation splashes nearby enemies (and the player, lightly) and chain-fuses
## other cells in range — the 1995 manual's exploding barrels, VOID RUNNER
## flavored. Destroying every cell in a level is the optional secondary
## objective (bonus scored in game._level_complete). Distance checks only,
## no physics bodies, same as every other system in this game.

signal cell_destroyed

const HIT_R2 := 5.0            # player-shot-vs-cell collision sphere²
const CHAIN_RADIUS := 13.0
const CHAIN_FUSE := 0.18       # stagger so chains read as pop-pop-pop, not one bang
const SPLASH_RADIUS := 13.0
const ENEMY_SPLASH_DMG := 45
const PLAYER_SPLASH_DMG := 8.0
const SCORE := 75

var player: PlayerShip
var enemy_mgr: EnemyManager
var shot_mgr: ShotManager

var props: Array[Dictionary] = []   # {node, hp, fuse (-1 = idle)}
var _tex: ImageTexture


func _ready() -> void:
	_tex = SpriteGen.prop_texture()


func clear_all() -> void:
	for p in props:
		p.node.queue_free()
	props.clear()


func warmup_textures() -> Array:
	return [_tex]


func spawn_prop(pos: Vector3) -> void:
	var sprite := SpriteGen.make_sprite(_tex, 2.6)
	sprite.position = pos
	add_child(sprite)
	props.append({"node": sprite, "hp": 2, "fuse": -1.0})


## Direct hit from a player shot (wired into shot_manager's collision loop).
func damage_prop(index: int, dmg: int) -> void:
	var p: Dictionary = props[index]
	if p.fuse >= 0.0:
		return
	p.hp -= dmg
	if p.hp <= 0:
		p.fuse = 0.0   # detonates on the next update tick


## Fuse every idle cell within radius — chains and MISSILE splash both land here.
func splash(pos: Vector3, radius: float) -> void:
	for p in props:
		if p.fuse < 0.0 and p.node.position.distance_squared_to(pos) < radius * radius:
			p.fuse = CHAIN_FUSE


func update_props(delta: float) -> void:
	for i in range(props.size() - 1, -1, -1):
		var p: Dictionary = props[i]
		if p.fuse < 0.0:
			continue
		p.fuse -= delta
		if p.fuse <= 0.0:
			var pos: Vector3 = p.node.position
			p.node.queue_free()
			props.remove_at(i)
			_explode(pos)


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
