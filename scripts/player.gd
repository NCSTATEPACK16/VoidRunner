class_name PlayerShip
extends Node3D
## Flight controller (PLAN.md D3) — constant forward speed, mouse + arrow steering,
## wall clamp/bounce/damage. Direct port of the v2.2 update()'s player block; the
## numbers here are the shipped v2.2 tuning from PROJECT.md §5.

signal damaged(amount: float, message: String)

const BASE_SPEED := 18.0
const BOOST_SPEED := 38.0
const BRAKE_SPEED := 8.0
const ENERGY_DRAIN := 20.0
const ENERGY_REGEN := 11.0
const SHIELD_REGEN := 1.5
const REGEN_DELAY := 6.0
const WALL_DMG := 5.0
const PITCH_LIMIT := 0.62
const KB_YAW_RATE := 1.7
const KB_PITCH_RATE := 1.15
const MOUSE_SENS := 0.0021

var path: PathGen
var world: WorldBuilder

var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var speed := BASE_SPEED
var ring_idx := 1
var bounce := Vector3.ZERO
var shake := 0.0
var wall_hurt_t := 0.0
var last_damage := -99.0
var elapsed := 0.0
var active := false           # only steers/moves while the run is live

var _turn_sm := 0.0
var camera: Camera3D
var _headlight: OmniLight3D
var muzzle_light: OmniLight3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	_headlight = OmniLight3D.new()
	_headlight.light_color = Color("7fa8ff")
	_headlight.light_energy = 1.25
	_headlight.omni_range = 70.0
	_headlight.position = Vector3(0, 0, -6)
	add_child(_headlight)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 30.0
	muzzle_light.position = Vector3(0, -0.4, -4)
	add_child(muzzle_light)


func reset_to_start() -> void:
	position = path.rings[1].p
	yaw = 0.0
	pitch = 0.0
	roll = 0.0
	_turn_sm = 0.0
	speed = BASE_SPEED
	ring_idx = 1
	bounce = Vector3.ZERO
	shake = 0.0
	wall_hurt_t = 0.0
	last_damage = -99.0
	elapsed = 0.0
	rotation = Vector3.ZERO
	camera.position = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -PITCH_LIMIT, PITCH_LIMIT)
		_turn_sm += -event.relative.x * MOUSE_SENS


func forward() -> Vector3:
	return PathGen.forward_from(yaw, pitch)


func update_flight(delta: float) -> void:
	elapsed += delta
	# --- keyboard steering (PC or iPad keyboard) ---
	var ts := KB_YAW_RATE * delta
	var ps := KB_PITCH_RATE * delta
	if Input.is_action_pressed("steer_left"):
		yaw += ts
		_turn_sm += ts * 0.6
	if Input.is_action_pressed("steer_right"):
		yaw -= ts
		_turn_sm -= ts * 0.6
	if Input.is_action_pressed("steer_up"):
		pitch = minf(PITCH_LIMIT, pitch + ps)
	if Input.is_action_pressed("steer_down"):
		pitch = maxf(-PITCH_LIMIT, pitch - ps)
	# --- speed / energy (energy = afterburner reserve only) ---
	var target := BASE_SPEED
	var boosting := Input.is_action_pressed("boost") and GameState.energy > 0.5
	if boosting:
		target = BOOST_SPEED
	if Input.is_action_pressed("brake"):
		target = BRAKE_SPEED
	speed += (target - speed) * minf(1.0, delta * 4.0)
	if boosting:
		GameState.energy -= ENERGY_DRAIN * delta
	else:
		GameState.energy += ENERGY_REGEN * delta
	if elapsed - last_damage > REGEN_DELAY:
		GameState.shields += SHIELD_REGEN * delta
	AudioSys.set_engine(speed, BOOST_SPEED)
	# --- move ---
	var fwd := forward()
	position += fwd * (speed * delta)
	position += bounce * delta
	bounce *= pow(0.015, delta)
	wall_hurt_t -= delta
	ring_idx = path.nearest_ring(position, ring_idx)
	_wall_collide()
	_door_collide()
	# --- camera framing ---
	_turn_sm *= pow(0.0001, delta)
	roll += (clampf(_turn_sm * 7.0, -0.28, 0.28) - roll) * minf(1.0, delta * 6.0)
	rotation = Vector3(pitch, yaw, roll)
	shake = maxf(0.0, shake - delta * 1.4)
	if shake > 0.0:
		camera.position = Vector3(
			(randf() - 0.5) * shake * 0.7, (randf() - 0.5) * shake * 0.7, 0.0)
	else:
		camera.position = Vector3.ZERO
	muzzle_light.light_energy *= pow(0.0006, delta)


func _wall_collide() -> void:
	var ring: Dictionary = path.rings[ring_idx]
	var rel := position - ring.p as Vector3
	var lat: float = rel.dot(ring.r)
	var vert: float = rel.dot(ring.u)
	var max_l: float = ring.hw - 1.6
	var max_v: float = ring.hh - 1.3
	var hit := false
	if lat > max_l:
		position += ring.r * (max_l - lat)
		bounce += ring.r * -16.0
		hit = true
	elif lat < -max_l:
		position += ring.r * (-max_l - lat)
		bounce += ring.r * 16.0
		hit = true
	if vert > max_v:
		position += ring.u * (max_v - vert)
		bounce += ring.u * -16.0
		hit = true
	elif vert < -max_v:
		position += ring.u * (-max_v - vert)
		bounce += ring.u * 16.0
		hit = true
	if hit and wall_hurt_t <= 0.0:
		wall_hurt_t = 0.45
		take_damage(WALL_DMG, "HULL IMPACT")


## Phase E: a closed kill-locked door acts like a wall cap — bounce off it.
func _door_collide() -> void:
	var door_ring := world.door_blocking(ring_idx)
	if door_ring < 0:
		return
	var ring: Dictionary = path.rings[door_ring]
	var ahead: float = (position - ring.p as Vector3).dot(ring.d)
	if ahead > -2.0:
		position += ring.d * (-2.0 - ahead)
		bounce += ring.d * -14.0
		if wall_hurt_t <= 0.0:
			wall_hurt_t = 0.45
			take_damage(2.0, "BULKHEAD SEALED — CLEAR ALL HOSTILES")


func take_damage(amount: float, message: String) -> void:
	if GameState.is_dead:
		return
	GameState.shields -= amount
	last_damage = elapsed
	shake = minf(0.6, shake + 0.35)
	AudioSys.play_hit()
	damaged.emit(amount, message)


func flash_muzzle(color: Color) -> void:
	muzzle_light.light_color = color
	muzzle_light.light_energy = 2.4
