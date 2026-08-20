extends CanvasLayer
## M4a mobile spike: the minimum touch layer that makes VOID RUNNER playable with
## thumbs, plus an on-screen framerate readout so the go/no-go is decided by a
## number rather than by how it felt.
##
## Constant-forward flight is why this is small: there is no movement stick to
## design, which is the hard part of touch FPS controls and the part this game
## structurally does not have. Steering is a relative drag anywhere on the left
## of the screen; firing is a thumb button on the right.
##
## Lives OUTSIDE the 320x200 SubViewport (like Overlays) so the buttons are sized
## in real screen pixels — a 44 px touch target inside a 320-wide viewport would
## be a third of the screen.
class_name TouchControls

signal fire_held(down: bool)

## Apple's and Google's minimum comfortable touch target, in screen pixels.
const TOUCH_MIN := 64.0
## Drag-to-look gain. Tuned so a thumb sweep across a third of the screen turns
## about as far as the same sweep of a mouse does at default sensitivity.
const DRAG_GAIN := 0.55

var player: PlayerShip
var active := false

var _steer_touch := -1        # finger index currently steering, -1 = none
var _fire_touch := -1
var _fps_label: Label
var _fps_accum := 0.0
var _fps_frames := 0
var _worst_frame := 0.0
var _root: Control
var _fire_btn: Panel


func _ready() -> void:
	layer = 12   # above the HUD, below the overlays (10) is wrong — overlays must win
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	# fire pad, bottom-right, deliberately large: a missed shot on a phone reads
	# as the game being broken, not as the player having missed
	_fire_btn = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.45, 0.2, 0.14)
	sb.border_color = Color(1.0, 0.61, 0.25, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(TOUCH_MIN))
	_fire_btn.add_theme_stylebox_override("panel", sb)
	_fire_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fire_btn.size = Vector2(TOUCH_MIN * 2.0, TOUCH_MIN * 2.0)
	_fire_btn.position = Vector2(-TOUCH_MIN * 2.6, -TOUCH_MIN * 2.6)
	_fire_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fire_btn)
	var l := Label.new()
	l.text = "FIRE"
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-22, -12)
	_fire_btn.add_child(l)
	# framerate readout — the spike's whole purpose
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 12)
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_root.add_child(_fps_label)


func enable(p: PlayerShip) -> void:
	player = p
	active = true
	visible = true
	set_process(true)
	set_process_input(true)


## True when this screen point is inside the fire pad.
func _in_fire(pos: Vector2) -> bool:
	return _fire_btn.get_global_rect().has_point(pos)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _in_fire(t.position) and _fire_touch < 0:
				_fire_touch = t.index
				fire_held.emit(true)
			elif _steer_touch < 0:
				_steer_touch = t.index   # anywhere else steers
		else:
			if t.index == _fire_touch:
				_fire_touch = -1
				fire_held.emit(false)
			if t.index == _steer_touch:
				_steer_touch = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _steer_touch and player != null:
			player.apply_mouse_look(d.relative * DRAG_GAIN)


func _process(delta: float) -> void:
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
