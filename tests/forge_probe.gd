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
		# PR F: sets differ in angles and frames (the CC0 pilot is 16 x 4), so each id
		# gets anim + 1 rows (its frames, then the flash) and the sheet is as wide as
		# the widest set, laid out at that set's own cell size
		var cell := 0
		var cols := 0
		var rows := 0
		for id in group:
			var st0: Dictionary = SpriteForge.sprite_set(id)
			cell = maxi(cell, (st0.tex[0] as Texture2D).get_width())
			cols = maxi(cols, int(st0.angles))
			rows += int(st0.anim) + 1
		var sheet := Image.create(cell * cols, cell * rows, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.16, 0.16, 0.2))
		var row := 0
		for gi in group.size():
			var st: Dictionary = SpriteForge.sprite_set(group[gi])
			var c: int = (st.tex[0] as Texture2D).get_width()
			for a in st.angles:
				for f in st.anim:
					var img: Image = (st.tex[a * st.anim + f] as ImageTexture).get_image()
					sheet.blend_rect(img, Rect2i(0, 0, c, c), Vector2i(a * cell, (row + f) * cell))
				var fl: Image = (st.flash[a] as ImageTexture).get_image()
				sheet.blend_rect(fl, Rect2i(0, 0, c, c), Vector2i(a * cell, (row + st.anim) * cell))
			row += int(st.anim) + 1
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
