extends Node
## Headless checkpoint probe (v4c A2): godot --headless tests/checkpoint_probe.tscn
## For every campaign sector: fly it on the rail (RailAssist, god mode) and record every
## checkpoint the game stores (the sector start and each cleared bulkhead on RUNNER), then
## resume from each one through the real CONTINUE path (save file -> _on_continue ->
## briefing -> launch) and fly on to LEVEL_CLEAR. Every sector must complete from every one
## of its checkpoints. A resume that gets stuck prints STUCK with the state and ring and
## the run exits non-zero (no asserts: they would hang a headless run).
## Restores records/settings/checkpoint on exit, like the other probes.

const RailAssist := preload("res://tests/rail_assist.gd")
const PROBE_SEED := 4141
const MAX_STEPS := 60 * 300       # per flight: five minutes is a stuck run


func _ready() -> void:
	_run()


## Fly the current sector until it stops PLAYING. When `rec` is given, every new checkpoint
## ring the game stores is copied into it. Returns {steps, done, ring, state}.
func _fly(game: Node3D, rec: Dictionary) -> Dictionary:
	var dt := 1.0 / 60.0
	var steps := 0
	Input.action_press("fire")
	for f in MAX_STEPS:
		GameState.shields = 100.0
		GameState.is_dead = false
		RailAssist.step(game, f, true)
		game._process(dt)
		steps += 1
		var cp: Dictionary = game._checkpoint
		if not cp.is_empty() and int(cp.level_index) == GameState.level_index \
				and not rec.has(int(cp.ring)):
			rec[int(cp.ring)] = cp.duplicate(true)
		if game.state != game.State.PLAYING:
			break
	Input.action_release("fire")
	return {"steps": steps, "ring": game.player.ring_idx, "state": game.state,
		"done": game.state == game.State.LEVEL_CLEAR or game.state == game.State.VICTORY}


func _run() -> void:
	var saved := {}
	for f in ["user://records.cfg", "user://settings.cfg", "user://checkpoint.cfg"]:
		saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	seed(PROBE_SEED)
	GameState.reset_run()
	GameState.unlocked_level = 8
	var sectors := 0
	var points := 0
	var failed := 0
	for li in game.levels.size():
		GameState.reset_run()
		GameState.difficulty = 1   # RUNNER: bulkhead checkpoints save
		GameState.level_index = li
		game._resume = {}
		game._checkpoint = {}
		game._show_briefing()
		for i in 3:
			await get_tree().process_frame
		game._on_launch()
		var rec := {}
		var first := _fly(game, rec)
		print("[cp] L%d first flight: %s in %d steps, checkpoints at rings %s" % [
			li + 1, "CLEAR" if first.done else "STUCK state=%d ring=%d" % [first.state, first.ring],
			first.steps, str(rec.keys())])
		if not first.done:
			failed += 1
			continue
		sectors += 1
		var rings := rec.keys()
		rings.sort()
		for ring in rings:
			GameState.reset_run()
			GameState.difficulty = 1
			GameState.level_index = li
			GameState.save_checkpoint(rec[ring])   # the file CONTINUE reads
			game._checkpoint = {}
			game._resume = {}
			game._on_continue()
			for i in 3:
				await get_tree().process_frame
			var ok_resume: bool = not game._resume.is_empty() and game.state == game.State.BRIEFING
			game._on_launch()
			var start_ring: int = game.player.ring_idx
			var r := _fly(game, {})
			points += 1
			if r.done and ok_resume:
				print("[cp] L%d from ring %d: CLEAR in %d steps" % [li + 1, ring, r.steps])
			else:
				failed += 1
				var why := "resume path not taken"
				if not r.done:
					if not game.world.portal_active:
						why = "STUCK, exit dark (objective %d/%d)" % [game._obj_done, game._obj_total]
					elif start_ring > game.path.main_ring_count - 6:
						why = "STUCK, resumed past the exit portal (ring %d, portal at %d)" % [
							start_ring, game.path.main_ring_count - 6]
					else:
						why = "STUCK"
				print("[cp] L%d from ring %d: FAILED %s state=%d ring=%d/%d steps=%d saved objective=%s cleared=%s" % [
					li + 1, ring, why, r.state, r.ring, game.path.main_ring_count, r.steps,
					str(rec[ring].get("objective", {})), str(rec[ring].cleared_arenas)])
	for f in saved:
		if saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fh := FileAccess.open(f, FileAccess.WRITE)
			fh.store_buffer(saved[f])
			fh.close()
	if failed == 0 and sectors == game.levels.size():
		print("CHECKPOINT PROBE COMPLETE — %d sectors, %d checkpoints, all clear" % [sectors, points])
		get_tree().quit()
	else:
		print("CHECKPOINT PROBE FAILED — %d failures (%d sectors flown, %d checkpoints)" % [failed, sectors, points])
		get_tree().quit(1)
