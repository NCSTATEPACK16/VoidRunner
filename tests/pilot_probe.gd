extends Node
## PR F rendered A/B probe (NOT --headless): the CC0 pilot's three sprites at game
## size, after the palette pass. A trio of drones and a pair of hulks in an L3
## corridor, then the L3 boss (the sentinel) in its room.
##   xvfb-run godot --path . tests/pilot_probe.tscn                  (pilot on)
##   VR_PILOT_OFF=1 xvfb-run godot --path . tests/pilot_probe.tscn   (code-built)
## Output: VR_SHOT_DIR env var, else user://shots; files are pilot_<on|off>_*.png.
## Restores records/settings/checkpoint.


func _ready() -> void:
	_run()


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


## Line up `type`s ahead of the ship at the given offsets (forward, right, up), each
## turned a different way so several baked angles show.
func _lineup(game: Node3D, type: String, offs: Array) -> void:
	var em: EnemyManager = game.enemy_mgr
	var fwd: Vector3 = game.player.forward()
	var right := fwd.cross(Vector3.UP).normalized()
	for i in offs.size():
		var o: Vector3 = offs[i]
		em.spawn(game.player.ring_idx, -1, type, true)
		var e: Dictionary = em.enemies.back()
		e.node.position = game.player.position + fwd * o.x + right * o.y + Vector3.UP * o.z
		e.facing = (-fwd).rotated(Vector3.UP, i * 0.9)
		e.fire_t = 99.0   # hold fire for the capture


func _run() -> void:
	var off := OS.get_environment("VR_PILOT_OFF") == "1"
	SpriteModels.pilot_on = not off
	var tag := "off" if off else "on"
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
	print("[pilot] %s: prebaked=%s drone %d angles x %d frames" % [tag, SpriteForge.prebaked,
		SpriteForge.sprite_set("drone").angles, SpriteForge.sprite_set("drone").anim])
	GameState.reset_run()
	GameState.level_index = 2   # L3: plain corridors, and the sentinel's room
	game._launch_level()
	await get_tree().process_frame
	_jump(game, mini(24, game.path.rings.size() - 2))
	await _fly(game, 20)
	game.enemy_mgr.clear_all()
	game.shot_mgr.clear_all()
	_lineup(game, "drone", [Vector3(9, -3, 0.5), Vector3(15, 3, 1.0), Vector3(24, -1, -0.5)])
	await _fly(game, 6)
	await _cap(game, dir + "/pilot_%s_drones.png" % tag)
	game.enemy_mgr.clear_all()
	game.shot_mgr.clear_all()
	_lineup(game, "hulk", [Vector3(11, -3, 0.0), Vector3(19, 3, 0.5)])
	await _fly(game, 6)
	await _cap(game, dir + "/pilot_%s_hulks.png" % tag)
	# the boss spawns with the level, and clear_all above took it: relaunch L3
	GameState.reset_run()
	GameState.level_index = 2
	game._launch_level()
	await get_tree().process_frame
	var arena: Dictionary = game.path.arenas.back()
	_jump(game, arena.end - 13)   # the boss sits at room.end - 8; frame it from ~60 u
	await _fly(game, 45)
	await _cap(game, dir + "/pilot_%s_boss.png" % tag)
	print("PILOT PROBE COMPLETE")
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
