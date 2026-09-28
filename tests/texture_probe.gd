extends SceneTree
## Dev probe: paint every theme's texture set and save one contact sheet per
## theme (and one of the 256-color palette). CPU-only, so it runs headless:
##   godot --headless --path . --script res://tests/texture_probe.gd
## Output dir: VR_SHOT_DIR env var, else user://shots.


func _init() -> void:
	var dir := OS.get_environment("VR_SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var t0 := Time.get_ticks_msec()
	for theme_id in TextureGen.THEMES:
		var t1 := Time.get_ticks_msec()
		var texes: Dictionary = TextureGen.theme_textures(theme_id)
		var ms := Time.get_ticks_msec() - t1
		var keys: Array = TextureGen.KEYS
		var sheet := Image.create(64 * keys.size() + 2 * (keys.size() - 1), 64 * 2 + 2, false,
			Image.FORMAT_RGBA8)
		sheet.fill(Color(0.2, 0.2, 0.2))
		for i in keys.size():
			var img: Image = (texes[keys[i]] as ImageTexture).get_image()
			img.clear_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
			var lit := img.duplicate() as Image
			var glow := img.duplicate() as Image
			for y in 64:
				for x in 64:
					var c := img.get_pixel(x, y)
					lit.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
					# second row: full-bright mask (white = glows)
					glow.set_pixel(x, y, Color.WHITE if c.a < 0.5 else Color(0.05, 0.05, 0.08))
			sheet.blit_rect(lit, Rect2i(0, 0, 64, 64), Vector2i(i * 66, 0))
			sheet.blit_rect(glow, Rect2i(0, 0, 64, 64), Vector2i(i * 66, 66))
		sheet.save_png(dir + "/tex_%s.png" % theme_id)
		print("[tex] %s painted in %d ms" % [theme_id, ms])
	var pal := Image.create(16 * 8, 16 * 8, false, Image.FORMAT_RGBA8)
	for i in Palette.ALL.size():
		pal.fill_rect(Rect2i((i % 16) * 8, (i / 16) * 8, 8, 8), Palette.ALL[i])
	pal.save_png(dir + "/palette.png")
	print("TEXTURE PROBE COMPLETE in %d ms" % (Time.get_ticks_msec() - t0))
	quit()
