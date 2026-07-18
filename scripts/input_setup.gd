extends Node
## Autoload: registers the whole Input Map in code at boot.
## Mapping mirrors PROJECT.md §11.4 / the v2.2 web build: arrows + mouse steer,
## LMB/Space/X fire, W/RMB afterburner, S brake, A/D evade roll (K4), 1-4 weapons,
## Backspace cycles, P plasma bomb (V2.0 — the original's spacebar screen-clear,
## on P since Space stays fire), Enter/ESC pause (P used to pause; Enter is the
## iPad-reliable replacement).


func _init() -> void:
	_key_action("steer_left", KEY_LEFT)
	_key_action("steer_right", KEY_RIGHT)
	_key_action("steer_up", KEY_UP)
	_key_action("steer_down", KEY_DOWN)
	_key_action("dodge_left", KEY_A)
	_key_action("dodge_right", KEY_D)
	_key_action("fire", KEY_SPACE)
	_add_key("fire", KEY_X)
	_add_mouse("fire", MOUSE_BUTTON_LEFT)
	_key_action("boost", KEY_W)
	_add_mouse("boost", MOUSE_BUTTON_RIGHT)
	_key_action("brake", KEY_S)
	_key_action("weapon_1", KEY_1)
	_key_action("weapon_2", KEY_2)
	_key_action("weapon_3", KEY_3)
	_key_action("weapon_4", KEY_4)
	_key_action("weapon_cycle", KEY_BACKSPACE)
	_key_action("plasma_bomb", KEY_P)
	_key_action("pause_game", KEY_ENTER)
	_add_key("pause_game", KEY_ESCAPE)
	_key_action("automap", KEY_TAB)   # V2.2 L4a: Tab opens the paused automap


## K6: opt-in gamepad bindings — a settings toggle, OFF by default (John's call).
## Left stick steers via the analog read in player.gd (no steer-action bindings,
## which would double-apply); buttons ride the Input Map: A/RT fire, RB/LT boost,
## LB brake, X/B dodge left/right, d-pad = weapons 1-4, Start = pause.
var _gamepad_events: Array = []   # [action, event] pairs, for clean removal


func set_gamepad(enabled: bool) -> void:
	if enabled == (not _gamepad_events.is_empty()):
		return
	if not enabled:
		for pair in _gamepad_events:
			InputMap.action_erase_event(pair[0], pair[1])
		_gamepad_events.clear()
		return
	_pad_button("fire", JOY_BUTTON_A)
	_pad_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_pad_button("boost", JOY_BUTTON_RIGHT_SHOULDER)
	_pad_axis("boost", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_pad_button("brake", JOY_BUTTON_LEFT_SHOULDER)
	_pad_button("dodge_left", JOY_BUTTON_X)
	_pad_button("dodge_right", JOY_BUTTON_B)
	_pad_button("weapon_1", JOY_BUTTON_DPAD_UP)
	_pad_button("weapon_2", JOY_BUTTON_DPAD_RIGHT)
	_pad_button("weapon_3", JOY_BUTTON_DPAD_DOWN)
	_pad_button("weapon_4", JOY_BUTTON_DPAD_LEFT)
	_pad_button("pause_game", JOY_BUTTON_START)
	if InputMap.has_action("plasma_bomb"):
		_pad_button("plasma_bomb", JOY_BUTTON_Y)
	if InputMap.has_action("automap"):
		_pad_button("automap", JOY_BUTTON_BACK)   # V2.2 L4a: Back toggles the map


func _pad_button(action: StringName, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
	_gamepad_events.append([action, ev])


func _pad_axis(action: StringName, axis: JoyAxis, direction: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)
	_gamepad_events.append([action, ev])


func _key_action(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	_add_key(action, key)


func _add_key(action: StringName, key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _add_mouse(action: StringName, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
