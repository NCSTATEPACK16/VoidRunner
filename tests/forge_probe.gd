extends Node
## Rendered art-review probe (NOT --headless): bake every SpriteForge atlas and
## save contact sheets — each enemy/boss as its 8 angles x 2 idle frames plus the
## flash row, pickups as their 8 spin frames.
##   xvfb-run godot --path . tests/forge_probe.tscn
## Output: VR_SHOT_DIR env var, else user://shots.


func _ready() -> void:
	var dir := OS.get_environment("VR_SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	# PR E: VR_FORGE_RENDER=1 renders even with prebaked atlases present (the bake
	# A/B); VR_FORGE_COMPARE=1 renders, then checks the prebaked sheets match it
	var compare := OS.get_environment("VR_FORGE_COMPARE") == "1"
	SpriteForge.render_only = compare or OS.get_environment("VR_FORGE_RENDER") == "1"
	var t0 := Time.get_ticks_msec()
	SpriteForge.bake(self)
	print("[forge] baked in %d ms (bake_ms %d), %d sheets, gpu=%s" % [Time.get_ticks_msec() - t0,
		SpriteForge.bake_ms, SpriteForge.sheet_count, SpriteForge.gpu_baked])
	SpriteForge.bake_bosses()   # deferred to the first boss in the game; forced here
	print("[forge] boss sheet baked in %d ms (deferred from boot)" % SpriteForge.boss_bake_ms)
	SpriteForge.bake_objects()   # deferred to the first mission object; forced here
	print("[forge] objects sheet baked in %d ms (deferred from boot)" % SpriteForge.objects_bake_ms)
	for group in [SpriteModels.ENEMIES, SpriteModels.BOSSES, SpriteModels.OBJECTS]:
		var cell: int = (SpriteForge.sprite_set(group[0]).tex[0] as Texture2D).get_width()
		var sheet := Image.create(cell * 8, cell * 3 * group.size(), false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.16, 0.16, 0.2))
		for gi in group.size():
			var st: Dictionary = SpriteForge.sprite_set(group[gi])
			for a in st.angles:
				for f in st.anim:
					var img: Image = (st.tex[a * st.anim + f] as ImageTexture).get_image()
					sheet.blend_rect(img, Rect2i(0, 0, cell, cell), Vector2i(a * cell, (gi * 3 + f) * cell))
				var fl: Image = (st.flash[a] as ImageTexture).get_image()
				sheet.blend_rect(fl, Rect2i(0, 0, cell, cell), Vector2i(a * cell, (gi * 3 + 2) * cell))
		var name := "forge_enemies.png"
		if group == SpriteModels.BOSSES:
			name = "forge_bosses.png"
		elif group == SpriteModels.OBJECTS:
			name = "forge_objects.png"
		sheet.save_png(dir + "/" + name)
	var pk := Image.create(32 * 8, 32 * (SpriteModels.PICKUPS.size() + 1), false, Image.FORMAT_RGBA8)
	pk.fill(Color(0.16, 0.16, 0.2))
	for i in SpriteModels.PICKUPS.size():
		var frames: Array = SpriteForge.pickup_frames(SpriteModels.PICKUPS[i])
		for k in frames.size():
			pk.blend_rect((frames[k] as ImageTexture).get_image(), Rect2i(0, 0, 32, 32), Vector2i(k * 32, i * 32))
	pk.blend_rect(SpriteForge.prop_texture().get_image(), Rect2i(0, 0, 32, 32),
		Vector2i(0, SpriteModels.PICKUPS.size() * 32))
	pk.save_png(dir + "/forge_pickups.png")
	print("[forge] prebaked=%s" % SpriteForge.prebaked)
	if compare:
		_compare_prebaked()
	print("FORGE PROBE COMPLETE")
	get_tree().quit()


## Every rendered frame and flash, against the same cell of the prebaked sheets.
func _compare_prebaked() -> void:
	var rendered := {}
	for id in SpriteModels.ENEMIES + SpriteModels.BOSSES + SpriteModels.OBJECTS:
		rendered[id] = _images(SpriteForge.sprite_set(id))
	for kind in SpriteModels.PICKUPS:
		rendered[kind] = SpriteForge.pickup_frames(kind).map(func(t): return (t as Texture2D).get_image())
	rendered["prop"] = [SpriteForge.prop_texture().get_image()]
	var ok := SpriteForge.load_all_baked()
	var bad: Array = []
	var cells := 0
	for id in rendered:
		var now: Array
		if SpriteModels.PICKUPS.has(id):
			now = SpriteForge.pickup_frames(id).map(func(t): return (t as Texture2D).get_image())
		elif id == "prop":
			now = [SpriteForge.prop_texture().get_image()]
		else:
			now = _images(SpriteForge.sprite_set(id))
		if now.size() != rendered[id].size():
			bad.append("%s: %d frames, prebaked %d" % [id, rendered[id].size(), now.size()])
			continue
		for i in now.size():
			cells += 1
			if (now[i] as Image).get_data() != (rendered[id][i] as Image).get_data():
				bad.append("%s frame %d" % [id, i])
	if ok and bad.is_empty():
		print("PREBAKE PARITY OK — %d cells identical to a fresh render" % cells)
	else:
		print("PREBAKE PARITY FAILED (loaded=%s): %s" % [ok, ", ".join(bad.slice(0, 12))])


func _images(st: Dictionary) -> Array:
	var out: Array = []
	for t in st.tex + st.flash:
		out.append((t as Texture2D).get_image())
	return out
