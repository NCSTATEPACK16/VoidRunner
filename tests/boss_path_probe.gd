extends SceneTree
## Throwaway probe: validate the Phase J boss-room PathGen shape from the CLI.
## godot --headless --path . --script tests/boss_path_probe.gd


func _init() -> void:
	for cfg in [[54, 333], [56, 666], [58, 999]]:
		var p := PathGen.new()
		p.generate(cfg[0], cfg[1], 0.3, true)
		print("rings=%d arenas=%d" % [p.rings.size(), p.arenas.size()])
		for a in p.arenas:
			print("  arena start=%d end=%d door=%d final=%s spawns=%d" % [
				a.start, a.end, a.door_ring, a.is_final, a.spawn_rings.size()])
		var last: Dictionary = p.rings[p.rings.size() - 1]
		var centers := 0
		for r in p.rings:
			if r.arena_center:
				centers += 1
		print("  last hw=%.1f hh=%.1f lights=%d" % [last.hw, last.hh, centers])
	quit()
