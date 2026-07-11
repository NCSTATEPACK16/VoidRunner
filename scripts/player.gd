class_name PlayerShip
extends Node3D
## Flight controller (PLAN.md D3) — constant forward speed, mouse + arrow steering,
## wall clamp/bounce/damage. Direct port of the v2.2 update()'s player block; the
## numbers here are the shipped v2.2 tuning from PROJECT.md §5.

signal damaged(amount: float, message: String)
signal notified(message: String)          # HUD callouts that aren't damage (K4)
signal dodged(direction: Vector3)         # K4: game.gd hangs sparks + SFX on this

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

# K4 dodge roll: a quick lateral displacement with a short invulnerability window.
# Spends the shared afterburner energy pool — evading and boosting compete.
const DODGE_COST := 20.0
const DODGE_DIST := 14.0
const DODGE_TIME := 0.25
const DODGE_IFRAMES := 0.4
const DODGE_CD := 1.2
const DOUBLE_TAP := 0.28

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

var dodge_cd := 0.0           # public: the HUD's evade lamp reads this
var iframes_t := 0.0
var _dodge_t := 0.0
var _dodge_dir := Vector3.ZERO
var _tap_l := -99.0
var _tap_r := -99.0

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
	dodge_cd = 0.0
	iframes_t = 0.0
	_dodge_t = 0.0
	_dodge_dir = Vector3.ZERO
	_tap_l = -99.0
	_tap_r = -99.0
	rotation = Vector3.ZERO
	camera.position = Vector3.ZERO


## Called by game.gd from root-viewport input — the ship sits inside the 320x200
## SubViewport (I4), which unhandled input doesn't reach.
func apply_mouse_look(relative: Vector2) -> void:
	if not active:
		return
	var sens := MOUSE_SENS * GameState.mouse_sens_mult   # Phase H settings
	yaw -= relative.x * sens
	pitch = clampf(pitch - relative.y * sens, -PITCH_LIMIT, PITCH_LIMIT)
	_turn_sm += -relative.x * sens


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
	# --- K6: opt-in gamepad — analog left-stick steer (buttons ride the Input Map;
	# no pad connected reads 0, so this is inert unless the setting is on) ---
	if GameState.gamepad_enabled:
		var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		var jy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
		if absf(jx) > 0.15:
			yaw -= jx * KB_YAW_RATE * delta
			_turn_sm -= jx * ts * 0.6
		if absf(jy) > 0.15:
			pitch = clampf(pitch - jy * KB_PITCH_RATE * delta, -PITCH_LIMIT, PITCH_LIMIT)
	# --- K4 dodge roll: A/D keys, or a double-tap on the steer keys ---
	dodge_cd = maxf(0.0, dodge_cd - delta)
	iframes_t = maxf(0.0, iframes_t - delta)
	if Input.is_action_just_pressed("dodge_left"):
		_try_dodge(-1.0)
	if Input.is_action_just_pressed("dodge_right"):
		_try_dodge(1.0)
	if Input.is_action_just_pressed("steer_left"):
		if elapsed - _tap_l < DOUBLE_TAP:
			_try_dodge(-1.0)
		_tap_l = elapsed
	if Input.is_action_just_pressed("steer_right"):
		if elapsed - _tap_r < DOUBLE_TAP:
			_try_dodge(1.0)
		_tap_r = elapsed
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
	if _dodge_t > 0.0:
		# decelerating triangle profile — integrates to exactly DODGE_DIST
		position += _dodge_dir * (2.0 * DODGE_DIST / DODGE_TIME) * (_dodge_t / DODGE_TIME) * delta
		_dodge_t -= delta
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


## K4: start a dodge if it's off cooldown and the shared energy pool can pay for it.
## dir_sign: -1 = roll left, +1 = roll right (ship-relative).
func _try_dodge(dir_sign: float) -> void:
	if not active or dodge_cd > 0.0 or _dodge_t > 0.0:
		return
	if GameState.energy < DODGE_COST:
		notified.emit("LOW ENERGY")
		return
	GameState.energy -= DODGE_COST
	dodge_cd = DODGE_CD
	_dodge_t = DODGE_TIME
	iframes_t = DODGE_IFRAMES
	_dodge_dir = forward().cross(Vector3.UP).normalized() * dir_sign
	_turn_sm -= dir_sign * 0.22   # lean the camera into the roll
	dodged.emit(_dodge_dir)


func _wall_collide() -> void:
	var ring: Dictionary = path.rings[ring_idx]
	var rel := position - ring.p as Vector3
	var lat: float = rel.dot(ring.r)
	var vert: float = rel.dot(ring.u)
	var max_l: float = ring.hw - 1.6
	# K2/V-08: floor can be raised (fo) and ceiling dropped (co) per ring
	var max_top: float = ring.hh - ring.co - 1.3
	var max_bot: float = ring.hh - ring.fo - 1.3
	var hit := false
	if lat > max_l:
		position += ring.r * (max_l - lat)
		bounce += ring.r * -16.0
		hit = true
	elif lat < -max_l:
		position += ring.r * (-max_l - lat)
		bounce += ring.r * 16.0
		hit = true
	if vert > max_top:
		position += ring.u * (max_top - vert)
		bounce += ring.u * -16.0
		hit = true
	elif vert < -max_bot:
		position += ring.u * (-max_bot - vert)
		bounce += ring.u * 16.0
		hit = true
	# K4: a dash ends at the wall — one clamped contact, damage-free, instead of
	# feeding the bounce impulse every contact frame into a violent ricochet
	# (tunnels are narrower than DODGE_DIST, so corridor dodges always reach a wall).
	if hit and _dodge_t > 0.0:
		_dodge_t = 0.0
	elif hit and wall_hurt_t <= 0.0:
		wall_hurt_t = 0.45
		take_damage(WALL_DMG, "HULL IMPACT", true)


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
			take_damage(2.0, "BULKHEAD SEALED — CLEAR ALL HOSTILES", true)


## pierce_evade: wall/bulkhead scrapes still hurt mid-dodge (no rolling along walls
## for free); everything else — shots, contact, crushers, blasts — respects i-frames.
func take_damage(amount: float, message: String, pierce_evade := false) -> void:
	if GameState.is_dead:
		return
	if iframes_t > 0.0 and not pierce_evade:
		return
	GameState.shields -= amount
	last_damage = elapsed
	shake = minf(0.6, shake + 0.35)
	AudioSys.play_hit()
	damaged.emit(amount, message)


func flash_muzzle(color: Color) -> void:
	muzzle_light.light_color = color
	muzzle_light.light_energy = 2.4
