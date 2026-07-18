extends Node
## Rendered screenshot probe (K7 gate prep): godot tests/screenshot_probe.tscn
## (NO --headless — it needs the real rasterizer). Boots the game, flies three
## representative moments, and saves the native 320x200 SubViewport frame as PNG:
##   1. L1 plain corridor in flight   -> shot_corridor.png
##   1b. Tab automap over explored L1  -> shot_automap.png
##   2. L1 first arena, guards live   -> shot_arena.png
##   3. L3 boss room, boss in view    -> shot_boss.png
## Output dir: VR_SHOT_DIR env var, else user://shots. Restores records/settings.


func _ready() -> void:
	_run()


func _shot_dir() -> String:
	var dir := OS.get_environment("VR_SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _capture(game: Node3D, file_name: String, dir: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = (game.view as SubViewport).get_texture().get_image()
	img.save_png(dir + "/" + file_name)
	print("[shot] %s/%s" % [dir, file_name])


## Rail-steer like the smoke test so corners never stall the flight.
func _fly(game: Node3D, frames: int) -> void:
	for f in frames:
		GameState.shields = 100.0
		var pd: Vector3 = game.path.rings[mini(game.player.ring_idx + 2,
			game.path.rings.size() - 1)].d
		game.player.yaw = atan2(-pd.x, -pd.z)
		game.player.pitch = clampf(asin(pd.y), -0.6, 0.6)
		await get_tree().process_frame


func _run() -> void:
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var dir := _shot_dir()
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.unlocked_level = 0
	game.overlays._sector = 0
	GameState.level_index = 0
	GameState.score = 0
	game._show_briefing()
	for i in 30:
		await get_tree().process_frame   # warm-up rig compiles behind the briefing
	game._on_launch()
	await get_tree().process_frame
	# 1) corridor in flight — far enough in that fog/strip/lighting all read
	await _fly(game, 60 * 6)
	await _capture(game, "shot_corridor.png", dir)
	# 1b) Tab automap over the explored corridor — must read as a 1995 automap
	game._open_automap()
	await _capture(game, "shot_automap.png", dir)
	game.automap.close()
	# 2) first arena with its guards still alive
	var arena: Dictionary = game.path.arenas[0]
	var aring: Dictionary = game.path.rings[arena.start + 2]
	game.player.ring_idx = arena.start + 2
	game.player.position = aring.p
	game.player.yaw = atan2(-aring.d.x, -aring.d.z)
	game.player.pitch = 0.0
	await _fly(game, 30)   # let enemies turn toward us and shots fly
	await _capture(game, "shot_arena.png", dir)
	# 3) L3 boss room with the boss in frame
	GameState.reset_run()
	GameState.level_index = 2
	game._launch_level()
	await get_tree().process_frame
	var room: Dictionary = game.path.arenas.back()
	# the boss sits at room.end - 8 and boss-level fog ends ~110 u: shoot from
	# ~5 rings (60 u) out so the signature is actually in frame
	var bidx: int = room.end - 13
	var bring: Dictionary = game.path.rings[bidx]
	game.player.ring_idx = bidx
	game.player.position = bring.p
	game.player.yaw = atan2(-bring.d.x, -bring.d.z)
	game.player.pitch = 0.0
	await _fly(game, 45)
	await _capture(game, "shot_boss.png", dir)
	print("SCREENSHOT PROBE COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
