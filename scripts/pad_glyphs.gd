class_name PadGlyphs
## PR D: button names that match the pad in the player's hands. Godot's JoyButton
## values are positional (A = bottom face button, B = right, X = left, Y = top).
## Nintendo-layout pads (8BitDo, Switch Pro) print those positions as B / A / Y / X,
## so a prompt that says "A" must name the bottom button by its own label.

enum Layout { XBOX, NINTENDO }

const NINTENDO_NAMES := ["8bitdo", "nintendo", "pro controller", "switch", "joy-con"]

const FACE := {
	Layout.XBOX: {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y"},
	Layout.NINTENDO: {JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X"},
}
const SHOULDERS := {
	Layout.XBOX: ["LB", "RB", "LT", "RT"],
	Layout.NINTENDO: ["L", "R", "ZL", "ZR"],
}


## The layout for a pad by its reported name.
static func layout_for(joy_name: String) -> Layout:
	var n := joy_name.to_lower()
	for key in NINTENDO_NAMES:
		if n.contains(key):
			return Layout.NINTENDO
	return Layout.XBOX


## The layout of the pad driving the ship.
static func current_layout() -> Layout:
	return layout_for(Input.get_joy_name(GameState.pad_device))


## The printed label of a face button (A/B/X/Y) or shoulder (LB/RB) on `layout`.
static func label(button: JoyButton, layout: Layout = current_layout()) -> String:
	var face: Dictionary = FACE[layout]
	if face.has(button):
		return face[button]
	var sh: Array = SHOULDERS[layout]
	match button:
		JOY_BUTTON_LEFT_SHOULDER:
			return sh[0]
		JOY_BUTTON_RIGHT_SHOULDER:
			return sh[1]
		JOY_BUTTON_START:
			return "+" if layout == Layout.NINTENDO else "MENU"
		JOY_BUTTON_BACK:
			return "-" if layout == Layout.NINTENDO else "VIEW"
	return "?"


## The printed label of a trigger (JOY_AXIS_TRIGGER_LEFT / _RIGHT) on `layout`.
static func trigger(axis: JoyAxis, layout: Layout = current_layout()) -> String:
	var sh: Array = SHOULDERS[layout]
	return sh[2] if axis == JOY_AXIS_TRIGGER_LEFT else sh[3]
