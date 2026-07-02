extends Node
## Autoload: registers the whole Input Map in code at boot.
## Mapping mirrors PROJECT.md §11.4 / the v2.2 web build: arrows + mouse steer,
## LMB/Space/X fire, W/RMB afterburner, S brake, 1-4 weapons, Backspace cycles, P pause.


func _init() -> void:
	_key_action("steer_left", KEY_LEFT)
	_key_action("steer_right", KEY_RIGHT)
	_key_action("steer_up", KEY_UP)
	_key_action("steer_down", KEY_DOWN)
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
	_key_action("pause_game", KEY_P)
	_add_key("pause_game", KEY_ESCAPE)


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
