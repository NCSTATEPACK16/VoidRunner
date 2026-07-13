extends Node
## Headless check of the V2.1 web load/warm path (game._web_load_and_warm). The
## overlay + actual shader-compile behaviour is only observable in a real browser;
## what this proves headless is that the muted combat warm-up runs and cleans up
## without leaking state: shot pools drained, boom lights dark, level_shots
## restored, audio unmuted, the warm gate cleared, and the level world built.
## godot --headless --path . tests/warmup_probe.tscn


func _ready() -> void:
	_run()


func _run() -> void:
	# the path completes a level build — snapshot user:// records/settings, restore on exit
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null

	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	# game.gd:_ready re-loads records after boot — pin sector 0 AFTER it, as the
	# smoke/perf probes do, so a machine with progress can't launch a later level
	GameState.unlocked_level = 0
	game.overlays._sector = 0
	GameState.level_index = 0
	GameState.gauntlet_mode = false
	game._gauntlet = false

	var shots_before := GameState.level_shots
	var mute_before := AudioServer.is_bus_mute(0)
	# drive the web path directly: the JS-bridge helpers no-op off-web, the rest
	# (build + muted fire/explosion warm-up + teardown) is platform-agnostic
	await game._web_load_and_warm()

	assert(game._warming == false)                  # launch gate cleared
	assert(game._warmup_rig == null)                # warm-up rig torn down
	assert(game.shot_mgr._pshots.is_empty())        # muted warm-up shots cleared
	assert(game.shot_mgr._explosions.is_empty())
	assert(game.shot_mgr._sparks.is_empty())
	assert(GameState.level_shots == shots_before)   # accuracy stat left untouched
	assert(AudioServer.is_bus_mute(0) == mute_before)  # audio mute restored
	var dark := true
	for l in game.shot_mgr._boom_lights:
		if l.light_energy != 0.0:
			dark = false
	assert(dark)                                    # no explosion light leaked into play
	assert(game.path != null and game.path.rings.size() > 0)  # level world was built
	print("warmup ok — rig freed, %d boom lights dark, shots=%d, %d rings built" % [
		game.shot_mgr._boom_lights.size(), GameState.level_shots, game.path.rings.size()])
	print("WARMUP PROBE COMPLETE")

	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
