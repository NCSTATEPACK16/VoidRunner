extends CanvasLayer
## M4b touch layer: replaces the M4a relative-drag spike with per-finger zone
## ownership and a floating rate-control joystick.
##
## Every touch is owned by exactly one of: a button (FIRE/WEAPON/BOMB, right side)
## or the steering stick (anywhere in the left 45%). No touch can affect both, which
## is what makes "steer while firing" actually work on two thumbs — the M4a spike
## let the whole non-button screen steer, so a thumb reaching for FIRE could yank
## the ship mid-corner.
##
## Lives OUTSIDE the 320x200 SubViewport (like Overlays) so button/stick geometry is
## in 320x200 canvas units (matching hud.gd/overlays.gd), not real screen pixels —
## the canvas_items viewport scale handles the rendering mapping.
class_name TouchControls

signal fire_held(down: bool)
signal weapon_tapped
signal bomb_tapped

## D9: the touch steering stick — radius and dead zone, in 320x200 canvas units.
const STICK_RADIUS := 40.0
const STICK_DEAD_ZONE := 3.0
## Fraction of screen width, from the left edge, that can start a steering touch.
const LEFT_ZONE_FRAC := 0.45
## D10: double-tap window/radius to toggle boost, in seconds / canvas units.
const BOOST_TAP_WINDOW := 0.3
const BOOST_TAP_DIST := 15.0
## Button sizes (diameter, canvas units) per the "Thumbs On Glass" spec, rescaled
## into the 320x200 canvas_items space.
const FIRE_SIZE := 32.0
const SIDE_SIZE := 22.0
## Idle fade: how long with no touch before the layer dims, and to what alpha.
const IDLE_FADE_AFTER := 2.5
const IDLE_ALPHA := 0.35

var player: PlayerShip
var active := false

var _steer_touch := -1        # finger index currently steering, -1 = none
var _fire_touch := -1
var _weapon_touch := -1
var _bomb_touch := -1

var _stick_center := Vector2.ZERO
var _boost_active := false
var _last_tap_time := -999.0
var _last_tap_pos := Vector2.ZERO
var _idle_t := 0.0

var _fps_label: Label
var _fps_accum := 0.0
var _fps_frames := 0
var _worst_frame := 0.0

var _root: Control
var _fire_btn: Panel
var _weapon_btn: Panel
var _bomb_btn: Panel
var _stick_ring: Panel
var _stick_knob: Panel


func _ready() -> void:
	layer = 12   # above the HUD, below the overlays (10) is wrong — overlays must win
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()
	visible = false
	set_process(false)
	set_process_input(false)


func _build() -> void:
	_fire_btn = _make_button(FIRE_SIZE, Vector2(40.0, 28.0), "FIRE",
		Color(1.0, 0.45, 0.2, 0.14), Color(1.0, 0.61, 0.25, 0.7))
	_bomb_btn = _make_button(SIDE_SIZE, Vector2(76.0, 28.0), "BOMB",
		Color(0.55, 0.2, 0.85, 0.14), Color(0.7, 0.4, 1.0, 0.7))
	_weapon_btn = _make_button(SIDE_SIZE, Vector2(62.0, 60.0), "WPN",
		Color(0.2, 0.55, 0.85, 0.14), Color(0.4, 0.75, 1.0, 0.7))
	# floating stick visuals — hidden until a steering touch begins
	_stick_ring = Panel.new()
	var ring_sb := StyleBoxFlat.new()
	ring_sb.bg_color = Color(0, 0, 0, 0)
	ring_sb.border_color = Color(1.0, 0.61, 0.25, 0.55)
	ring_sb.set_border_width_all(2)
	ring_sb.set_corner_radius_all(int(STICK_RADIUS))
	_stick_ring.add_theme_stylebox_override("panel", ring_sb)
	_stick_ring.size = Vector2(STICK_RADIUS, STICK_RADIUS) * 2.0
	_stick_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_ring.visible = false
	_root.add_child(_stick_ring)
	_stick_knob = Panel.new()
	var knob_sb := StyleBoxFlat.new()
	knob_sb.bg_color = Color(1.0, 0.75, 0.45, 0.55)
	knob_sb.set_corner_radius_all(28)
	_stick_knob.add_theme_stylebox_override("panel", knob_sb)
	_stick_knob.size = Vector2(56.0, 56.0)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.visible = false
	_root.add_child(_stick_knob)
	# framerate readout — the M4a spike's whole purpose, kept for the M4d Android check
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 12)
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_root.add_child(_fps_label)


## One button, bottom-right-anchored, offset (right, up) screen pixels from that
## corner. Used for FIRE/WEAPON/BOMB so the three share one code path.
func _make_button(size: float, offset_from_br: Vector2, text: String,
		fill: Color, border: Color) -> Panel:
	var btn := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(size))
	btn.add_theme_stylebox_override("panel", sb)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.size = Vector2(size, size)
	btn.position = Vector2(-offset_from_br.x - size * 0.5, -offset_from_br.y - size * 0.5)
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(btn)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14 if size < FIRE_SIZE else 20)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.8))
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-l.text.length() * 4.5, -10)
	btn.add_child(l)
	return btn


func enable(p: PlayerShip) -> void:
	player = p
	set_flight_active(true)


## M4b: called every frame from game.gd with (state == State.PLAYING). Replaces the
## M4a behavior where enable() turned the layer on once and nothing ever turned it
## back off — which is why the fire pad used to paint over the game-over screen and
## every menu.
func set_flight_active(flag: bool) -> void:
	if flag == active:
		return
	active = flag
	visible = flag
	set_process(flag)
	set_process_input(flag)
	if not flag:
		_release_all()


## Releases every action/touch this layer might be holding down. Needed because
## set_process_input(false) means a touch's eventual "up" event is never delivered
## here — without this, pausing mid-turn or mid-boost would leave that input stuck
## pressed for the rest of the run.
func _release_all() -> void:
	if _fire_touch >= 0:
		_fire_touch = -1
		fire_held.emit(false)
	_weapon_touch = -1
	_bomb_touch = -1
	_steer_touch = -1
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	Input.action_release("steer_up")
	Input.action_release("steer_down")
	if _boost_active:
		_set_boost(false)
	_stick_ring.visible = false
	_stick_knob.visible = false


func _set_boost(on: bool) -> void:
	_boost_active = on
	if on:
		Input.action_press("boost")
	else:
		Input.action_release("boost")
	var ring_sb := _stick_ring.get_theme_stylebox("panel") as StyleBoxFlat
	ring_sb.border_color = Color(0.4, 1.0, 0.6, 0.8) if on else Color(1.0, 0.61, 0.25, 0.55)


func _in_rect(btn: Panel, pos: Vector2) -> bool:
	return btn.get_global_rect().has_point(pos)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _steer_touch:
			_update_stick(d.position)


func _on_touch(t: InputEventScreenTouch) -> void:
	_idle_t = 0.0
	if t.pressed:
		if _in_rect(_fire_btn, t.position) and _fire_touch < 0:
			_fire_touch = t.index
			fire_held.emit(true)
		elif _in_rect(_bomb_btn, t.position) and _bomb_touch < 0:
			_bomb_touch = t.index
			bomb_tapped.emit()
		elif _in_rect(_weapon_btn, t.position) and _weapon_touch < 0:
			_weapon_touch = t.index
			weapon_tapped.emit()
		elif t.position.x < get_viewport().get_visible_rect().size.x * LEFT_ZONE_FRAC \
				and _steer_touch < 0:
			_steer_touch = t.index
			_start_stick(t.position)
			_check_boost_tap(t.position)
	else:
		if t.index == _fire_touch:
			_fire_touch = -1
			fire_held.emit(false)
		if t.index == _weapon_touch:
			_weapon_touch = -1
		if t.index == _bomb_touch:
			_bomb_touch = -1
		if t.index == _steer_touch:
			_steer_touch = -1
			_end_stick()


func _check_boost_tap(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_tap_time < BOOST_TAP_WINDOW and pos.distance_to(_last_tap_pos) < BOOST_TAP_DIST:
		_set_boost(not _boost_active)
		_last_tap_time = -999.0   # consume — a third rapid tap starts a fresh window
	else:
		_last_tap_time = now
		_last_tap_pos = pos


func _start_stick(pos: Vector2) -> void:
	_stick_center = pos
	_stick_ring.position = pos - _stick_ring.size * 0.5
	_stick_knob.position = pos - _stick_knob.size * 0.5
	_stick_ring.visible = true
	_stick_knob.visible = true


func _update_stick(pos: Vector2) -> void:
	var raw := pos - _stick_center
	var clamped := raw.limit_length(STICK_RADIUS)
	_stick_knob.position = _stick_center + clamped - _stick_knob.size * 0.5
	var dist := clamped.length()
	var mag := 0.0
	if dist > STICK_DEAD_ZONE:
		mag = (dist - STICK_DEAD_ZONE) / (STICK_RADIUS - STICK_DEAD_ZONE)
	var dir := clamped / dist if dist > 0.001 else Vector2.ZERO
	var out := dir * mag   # each component in [-1, 1]; magnitude feeds player.gd's strength read
	if out.x > 0.0:
		Input.action_press("steer_right", out.x)
		Input.action_release("steer_left")
	elif out.x < 0.0:
		Input.action_press("steer_left", -out.x)
		Input.action_release("steer_right")
	else:
		Input.action_release("steer_left")
		Input.action_release("steer_right")
	if out.y < 0.0:
		Input.action_press("steer_up", -out.y)
		Input.action_release("steer_down")
	elif out.y > 0.0:
		Input.action_press("steer_down", out.y)
		Input.action_release("steer_up")
	else:
		Input.action_release("steer_up")
		Input.action_release("steer_down")


func _end_stick() -> void:
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	Input.action_release("steer_up")
	Input.action_release("steer_down")
	_stick_ring.visible = false
	_stick_knob.visible = false


func _process(delta: float) -> void:
	# boost runs by itself once toggled on — D10 — so it must be checked here even
	# with no finger on the steer zone at all. The cutoff is 0.5, not 0.0, because
	# that is player.gd's own gate (`boosting := ... and GameState.energy > 0.5`):
	# below it the ship stops boosting AND stops draining, so energy regenerates,
	# crosses back over 0.5, drains again — it never reaches 0.0 at 60 fps. A 0.0
	# test would leave the toggle latched forever, pinning the shared energy pool at
	# ~0.5 and locking the player out of every energy weapon and the dodge.
	if _boost_active and GameState.energy <= 0.5:
		_set_boost(false)
	# idle fade: the layer recedes when nothing has been touched for a couple of
	# seconds, without ever fully hiding — hiding would mean hunting for it again
	_idle_t += delta
	var target_alpha := IDLE_ALPHA if _idle_t > IDLE_FADE_AFTER else 1.0
	_root.modulate.a = move_toward(_root.modulate.a, target_alpha, delta * 2.0)
	# press-state feedback: a held button reads brighter
	_fire_btn.modulate = Color(1.3, 1.3, 1.3) if _fire_touch >= 0 else Color.WHITE
	_bomb_btn.modulate = Color(1.3, 1.3, 1.3) if _bomb_touch >= 0 else Color.WHITE
	_weapon_btn.modulate = Color(1.3, 1.3, 1.3) if _weapon_touch >= 0 else Color.WHITE
	# framerate readout
	_fps_accum += delta
	_fps_frames += 1
	_worst_frame = maxf(_worst_frame, delta)
	if _fps_accum >= 0.5:
		var fps := _fps_frames / _fps_accum
		_fps_label.text = "%d FPS  ·  worst %d ms" % [roundi(fps), roundi(_worst_frame * 1000.0)]
		_fps_label.add_theme_color_override("font_color",
			Color(0.4, 1.0, 0.6) if fps >= 50.0 else Color(1.0, 0.5, 0.3))
		_fps_accum = 0.0
		_fps_frames = 0
		_worst_frame = 0.0
