extends Node
## Visual verification for the polish batch (NOT --headless). Captures:
##   verify_light.png  — L1 corridor: brighter tunnel + score clearing the strut
##   verify_amber.png  — same frame with AMBER TERMINAL mode on
##   verify_clear.png  — the level-clear screen with a full 4-line body + RANK
## Restores records/settings on exit.


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


func _run() -> void:
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var dir := _dir()
	get_window().size = Vector2i(960, 600)   # so native-res overlays render legibly

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
		await get_tree().process_frame
	game._on_launch()
	await _fly(game, 60 * 5)

	# 1) brighter tunnel + score placement (game view = the SubViewport)
	await RenderingServer.frame_post_draw
	(game.view as SubViewport).get_texture().get_image().save_png(dir + "/verify_light.png")
	print("[cap] verify_light.png")

	# 2) amber terminal mode on
	GameState.amber_mode = true
	GameState.apply_settings()
	await _fly(game, 20)
	await RenderingServer.frame_post_draw
	(game.view as SubViewport).get_texture().get_image().save_png(dir + "/verify_amber.png")
	print("[cap] verify_amber.png")
	GameState.amber_mode = false
	GameState.apply_settings()

	# 3) level-clear screen with the full 4-line body (overlay = native window res)
	game.overlays.set_level_clear("L1 · STARLIGHT APPROACH", 500, 2125,
		"L2 · SUPPLY ARTERY", 9, 7, 95.0, "B", false, 1, 1)
	game.overlays.show_only("level_clear")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/verify_clear.png")
	print("[cap] verify_clear.png")

	print("CAPTURE VERIFY COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
