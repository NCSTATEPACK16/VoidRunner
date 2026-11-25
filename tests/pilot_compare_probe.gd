extends Node
## PR F A/B probe (rendered, NOT --headless): the same three in-game frames with the
## CC0 pilot off (the code-built sprites) or on, plus a turntable strip per pilot id.
##   VR_PILOT=off godot --path . tests/pilot_compare_probe.tscn
##   VR_PILOT=on  godot --path . tests/pilot_compare_probe.tscn
## Output: VR_SHOT_DIR (else user://shots), files prefixed with the mode:
##   <mode>_corridor.png  three drones down an L1 straight
##   <mode>_hulk.png      a hulk close, a second one further back
##   <mode>_boss.png      the L3 sentinel in its boss room
##   <mode>_turn_<id>.png every baked angle, idle frame 0
## Restores records/settings/checkpoint.

const IDS := ["drone", "hulk", "sentinel"]


func _ready() -> void:
	_run()


func _cap(game: Node3D, path: String) -> void:
	await RenderingServer.frame_post_draw
	(game.view as SubViewport).get_texture().get_image().save_png(path)
	print("[shot] ", path)


## Park the ship on ring `ri` looking down the path, frames of settle time.
func _park(game: Node3D, ri: int, frames: int) -> void:
	var ring: Dictionary = game.path.rings[ri]
	for f in frames:
		GameState.shields = 100.0
		game.player.ring_idx = ri
		game.player.position = ring.p
		game.player.yaw = atan2(-ring.d.x, -ring.d.z)
		game.player.pitch = 0.0
		await get_tree().process_frame


## The first ring of a plain straight (no arena) at least `len` rings long.
func _straight(game: Node3D, len: int) -> int:
	for r in range(12, game.path.main_ring_count - len):
		var ok := true
		for q in range(r, r + len):
			ok = ok and not game.path.rings[q].arena and game.enemy_mgr._straight(q)
		if ok:
			return r
	return 12


func _place(game: Node3D, id: String, offset: Vector3) -> void:
	var em: EnemyManager = game.enemy_mgr
	em.spawn(game.player.ring_idx, -1, id)
	var en: Dictionary = em.enemies.back()
	en.node.position = game.player.position + offset
	en.facing = -game.player.forward()
	en.fire_t = 99.0


func _run() -> void:
	var mode := OS.get_environment("VR_PILOT")
	if mode == "":
		mode = "on"
	if mode == "off":
		SpriteModels.GLB_SOURCES = {}
	SpriteForge.render_only = true   # never the prebaked sheets: they'd be one mode only
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg", "user://checkpoint.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var dir := OS.get_environment("VR_SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.reduce_flashing = true
	# 1) three drones down an L1 straight
	GameState.reset_run()
	GameState.level_index = 0
	game._launch_level()
	await get_tree().process_frame
	game.enemy_mgr.clear_all()
	await _park(game, _straight(game, 10), 3)
	var fwd: Vector3 = game.player.forward()
	var right := fwd.cross(Vector3.UP).normalized()
	_place(game, "drone", fwd * 14.0 + right * 3.5 + Vector3.UP * 1.0)
	_place(game, "drone", fwd * 24.0 - right * 4.0 - Vector3.UP * 0.5)
	_place(game, "drone", fwd * 36.0 + right * 1.0 + Vector3.UP * 2.0)
	await _park(game, game.player.ring_idx, 4)
	await _cap(game, "%s/%s_corridor.png" % [dir, mode])
	# 2) hulks: one close, three-quarter view; one further back
	game.enemy_mgr.clear_all()
	_place(game, "hulk", fwd * 12.0 - right * 2.5)
	game.enemy_mgr.enemies.back().facing = (-fwd + right * 0.8).normalized()
	_place(game, "hulk", fwd * 30.0 + right * 4.0 + Vector3.UP * 1.5)
	await _park(game, game.player.ring_idx, 4)
	await _cap(game, "%s/%s_hulk.png" % [dir, mode])
	# 3) the L3 sentinel in its boss room (as screenshot_probe's shot_boss)
	game.enemy_mgr.clear_all()
	GameState.reset_run()
	GameState.level_index = 2
	game._launch_level()
	await get_tree().process_frame
	var room: Dictionary = game.path.arenas.back()
	await _park(game, room.end - 13, 45)
	await _cap(game, "%s/%s_boss.png" % [dir, mode])
	# 4) turntable strips
	for id in IDS:
		var st: Dictionary = SpriteForge.sprite_set(id)
		var cell: int = (st.tex[0] as Texture2D).get_width()
		var strip := Image.create(cell * st.angles, cell, false, Image.FORMAT_RGBA8)
		strip.fill(Color(0.06, 0.06, 0.09))
		for a in st.angles:
			strip.blend_rect((st.tex[a * st.anim] as ImageTexture).get_image(),
				Rect2i(0, 0, cell, cell), Vector2i(a * cell, 0))
		strip.save_png("%s/%s_turn_%s.png" % [dir, mode, id])
	for f in saved:
		if saved[f] == null:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fa := FileAccess.open(f, FileAccess.WRITE)
			fa.store_buffer(saved[f])
			fa.close()
	print("PILOT COMPARE COMPLETE (%s)" % mode)
	get_tree().quit()
