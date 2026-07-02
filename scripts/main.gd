extends Control
## Boot scene placeholder — Phase 0 pipeline check.
## Proves the rendering profile (320x200 viewport, nearest filter, Compatibility
## renderer) and the web export both work before any game content exists.

@onready var status_label: Label = $StatusLabel

var _blink_time := 0.0


func _ready() -> void:
	var version: Dictionary = Engine.get_version_info()
	status_label.text = "PIPELINE OK — GODOT %d.%d.%d %s" % [
		version.major, version.minor, version.patch, OS.get_name().to_upper()
	]


func _process(delta: float) -> void:
	_blink_time += delta
	status_label.visible = fmod(_blink_time, 1.0) < 0.7
