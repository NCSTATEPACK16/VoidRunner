class_name PadWatch
extends Node
## PR D: gamepad hot-plug. Tracks which pad drives the ship, turns the pad
## bindings on by itself on native mobile builds (web and desktop keep K6's
## opt-in setting), and tells game.gd when the pad comes and goes, so it can hide
## the touch layer while a pad is in use and pause the run if the pad drops out.

signal pad_connected(device: int)
signal pad_lost(device: int)

## True while a pad is connected and its bindings are on.
var live := false
## Whether a connect turns the bindings on by itself (native mobile only).
var auto_enable := OS.has_feature("mobile") and not OS.has_feature("web")


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for d in Input.get_connected_joypads():
		on_connected(d)   # a pad paired before launch counts as a connect


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		on_connected(device)
	else:
		on_disconnected(device)


func on_connected(device: int) -> void:
	GameState.pad_device = device
	if auto_enable and not GameState.gamepad_enabled:
		GameState.gamepad_enabled = true
		InputSetup.set_gamepad(true)
	live = GameState.gamepad_enabled
	pad_connected.emit(device)


## Only the pad driving the ship matters; a second pad dropping out is ignored.
func on_disconnected(device: int, remaining: Array = Input.get_connected_joypads()) -> void:
	if device != GameState.pad_device:
		return
	var rest := remaining.filter(func(d: int) -> bool: return d != device)
	if not rest.is_empty():
		GameState.pad_device = int(rest[0])   # hand over to the pad still connected
		return
	live = false
	pad_lost.emit(device)
