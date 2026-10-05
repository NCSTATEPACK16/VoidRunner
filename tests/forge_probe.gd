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
	var t0 := Time.get_ticks_msec()
	SpriteForge.bake(self)
	print("[forge] baked in %d ms (bake_ms %d), %d sheets, gpu=%s" % [Time.get_ticks_msec() - t0,
		SpriteForge.bake_ms, SpriteForge.sheet_count, SpriteForge.gpu_baked])
	for group in [SpriteModels.ENEMIES, SpriteModels.BOSSES]:
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
		var name := "forge_enemies.png" if group == SpriteModels.ENEMIES else "forge_bosses.png"
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
	print("FORGE PROBE COMPLETE")
	get_tree().quit()
