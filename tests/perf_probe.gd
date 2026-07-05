extends Node
## Headless perf probe: godot --headless tests/perf_probe.tscn
## Boots the real game, launches level 1, and steps the simulation with a fixed
## delta while timing every step with Time.get_ticks_usec(). Any sim step whose
## CPU cost exceeds SPIKE_US is reported with what changed that frame (chunks
## built, enemies spawned, ring index) so stutter causes can be attributed.
## NOTE: headless uses the dummy rasterizer — this measures CPU/script cost only;
## shader compilation and draw costs do not appear here.

const SPIKE_US := 8000   # 8 ms of script time in a 16.6 ms frame budget


func _ready() -> void:
	_run()


func _run() -> void:
	# the probe completes levels and would fold its score into the player's real
	# records — snapshot user:// records/settings and restore them on exit
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null

	var t_boot := Time.get_ticks_usec()
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	print("[perf] boot+instantiate: %.1f ms" % ((Time.get_ticks_usec() - t_boot) / 1000.0))
	await get_tree().process_frame

	# pin to level 1 regardless of what sector the records file would select
	GameState.level_index = 0
	GameState.score = 0
	var t_brief := Time.get_ticks_usec()
	game._show_briefing()   # builds the level world + shader warm-up rig
	print("[perf] briefing (level build + warmup rig): %.1f ms" % [
		(Time.get_ticks_usec() - t_brief) / 1000.0])
	for i in 30:   # let the warm-up rig render/compile behind the briefing
		await get_tree().process_frame
	var t_launch := Time.get_ticks_usec()
	game._on_launch()   # BRIEFING -> PLAYING
	print("[perf] launch: %.1f ms" % ((Time.get_ticks_usec() - t_launch) / 1000.0))
	await get_tree().process_frame
	assert(game.state == game.State.PLAYING)

	# rendered mode (VR_PERF_RENDERED=1, run without --headless): awaits real frames
	# and measures wall-clock frame deltas, so shader-compile/draw stalls show up.
	var rendered := OS.get_environment("VR_PERF_RENDERED") == "1"

	Input.action_press("fire")
	var dt := 1.0 / 60.0
	var spikes := 0
	var worst_us := 0
	var hist := {}   # bucket ms -> count
	var t_prev := Time.get_ticks_usec()
	for f in 60 * 240:
		GameState.shields = 100.0   # immortal: must traverse the whole level
		var ring_before: int = game.player.ring_idx
		var built_before: int = game.world._built_up_to
		var enemies_before: int = game.enemy_mgr.enemies.size()
		var t0 := Time.get_ticks_usec()
		var us: int
		if rendered:
			await get_tree().process_frame   # engine runs _process + renders
			us = int(Time.get_ticks_usec() - t_prev)
			t_prev = Time.get_ticks_usec()
		else:
			game._process(dt)
			us = int(Time.get_ticks_usec() - t0)
		worst_us = maxi(worst_us, us)
		var bucket := us / 2000   # 2 ms buckets
		hist[bucket] = int(hist.get(bucket, 0)) + 1
		var threshold := 40000 if rendered else SPIKE_US   # rendered frames are ~16ms anyway
		if us > threshold:
			spikes += 1
			print("[spike] t=%.1fs step=%d cost=%.1fms ring=%d->%d built=%d->%d enemies=%d->%d" % [
				f * dt, f, us / 1000.0, ring_before, game.player.ring_idx,
				built_before, game.world._built_up_to,
				enemies_before, game.enemy_mgr.enemies.size()])
		if game.state != game.State.PLAYING:
			break
	Input.action_release("fire")
	print("[perf] worst step: %.1f ms · spikes>%.0fms: %d" % [
		worst_us / 1000.0, SPIKE_US / 1000.0, spikes])
	var buckets := hist.keys()
	buckets.sort()
	for b in buckets:
		print("[hist] %d-%dms: %d steps" % [b * 2, b * 2 + 2, hist[b]])
	print("PERF PROBE COMPLETE ring=%d/%d state=%d" % [
		game.player.ring_idx, game.path.rings.size(), game.state])
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	get_tree().quit()
