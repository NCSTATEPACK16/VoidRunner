extends Node
## Rendered art-review probe (NOT --headless): for every campaign level, fly a
## few seconds in and save the native 320x200 frame, then jump into its first
## arena (or boss room) and save that too — one corridor + one arena per level,
## so every zone theme gets eyeballed after a render/texture change.
##   xvfb-run godot --path . tests/gallery_probe.tscn
## Output: VR_SHOT_DIR env var, else user://shots. Restores records/settings.


func _ready() -> void:
	_run()


func _dir() -> String:
	var d := OS.get_environment("VR_SHOT_DIR")
	if d == "":
		d = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _fly(game: Node3D, frames: int) -> void:
	for f in frames:
		GameState.shields = 100.0
		var pd: Vector3 = game.path.rings[mini(game.player.ring_idx + 2,
			game.path.rings.size() - 1)].d
		game.player.yaw = atan2(-pd.x, -pd.z)
		game.player.pitch = clampf(asin(pd.y), -0.6, 0.6)
		await get_tree().process_frame


func _jump(game: Node3D, ri: int) -> void:
	var ring: Dictionary = game.path.rings[ri]
	game.player.ring_idx = ri
	game.player.position = ring.p
	game.player.yaw = atan2(-ring.d.x, -ring.d.z)
	game.player.pitch = 0.0


func _cap(game: Node3D, path: String) -> void:
	await RenderingServer.frame_post_draw
	(game.view as SubViewport).get_texture().get_image().save_png(path)
	print("[shot] ", path)


func _run() -> void:
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var dir := _dir()
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var only := OS.get_environment("VR_GALLERY_LEVELS")   # e.g. "1,5,7"
	for li in game.levels.size():
		if only != "" and not str(li + 1) in only.split(","):
			continue
		GameState.reset_run()
		GameState.level_index = li
		game._launch_level()
		await get_tree().process_frame
		_jump(game, mini(24, game.path.rings.size() - 2))
		await _fly(game, 40)
		await _cap(game, dir + "/gal_L%d_corridor.png" % (li + 1))
		var arena: Dictionary = game.path.arenas[0]
		var ai: int = arena.start + 2
		if game.path.is_boss:
			ai = arena.end - 13   # boss sits at room.end - 8; frame it from ~60 u
		_jump(game, ai)
		await _fly(game, 20)
		await _cap(game, dir + "/gal_L%d_arena.png" % (li + 1))
	print("GALLERY PROBE COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
