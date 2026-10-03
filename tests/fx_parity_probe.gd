extends Node
## v4 perf groundwork, rendered (NOT --headless): an FxBatch effect must look like the
## Sprite3D it replaced. An orthographic camera at 10 px per world unit looks at pairs
## of the same frame at the same size: the top row is Sprite3Ds from
## SpriteGen.make_sprite, the bottom row one FxBatch instance each, exactly 100 px
## lower. The two halves of the frame must match pixel for pixel, a tinted debris
## chunk included. A tint may land 1-2 steps off in a channel (instance colours
## travel as half floats; the palette pass snaps both to the same entry), so a pixel
## differs when any channel is more than TOL away.
##   xvfb-run godot --rendering-driver opengl3 --path . tests/fx_parity_probe.tscn
## Prints FX PARITY OK, or FX PARITY FAILED with the differing pixels per case, and
## saves fx_parity.png to VR_SHOT_DIR (else user://shots).

const W := 320
const H := 200
const TOL := 2.5 / 255.0


func _ready() -> void:
	_run()


func _run() -> void:
	var dir := OS.get_environment("VR_SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 20.0   # 200 px tall: 10 px per world unit
	cam.position = Vector3(0, 0, 10)
	vp.add_child(cam)
	cam.current = true
	# [name, frames, cell, world size, tint] — sizes are whole pixels at this scale
	var cases := [
		["fireball", FxGen.fireball_frames(), 3, 4.8, Color.WHITE],
		["shock ring", FxGen.shockwave_frames(), 1, 4.8, Color.WHITE],
		["smoke", FxGen.smoke_frames(), 4, 3.2, Color.WHITE],
		["enemy plasma", FxGen.plasma_frames(), 1, 3.2, Color.WHITE],
		["tinted debris", SpriteGen.gib_frames(), 2, 2.0, Color(0.38, 0.44, 0.66)],
		["spark", [SpriteGen.star_texture(Palette.ORANGE_3, Palette.ORANGE_1, 8)], 0, 1.6,
			Color.WHITE],
	]
	for i in cases.size():
		var c: Array = cases[i]
		var x := -13.0 + i * 5.2
		var frames: Array = c[1]
		var s := SpriteGen.make_sprite(frames[c[2]], c[3])
		s.modulate = c[4]
		s.position = Vector3(x, 5.0, 0.0)
		vp.add_child(s)
		var b := FxBatch.new(frames, 1, c[4] != Color.WHITE)
		vp.add_child(b)
		b.begin()
		b.add(Vector3(x, -5.0, 0.0), c[3], c[2], c[4])
		b.end()
	for f in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(dir + "/fx_parity.png")
	var bg := img.get_pixel(0, 0)
	var failed := false
	for i in cases.size():
		var cx := int(round((-13.0 + i * 5.2 + 16.0) * 10.0))
		var half := 26
		var diff := 0
		var drawn := 0
		for y in 100:
			for x in range(maxi(cx - half, 0), mini(cx + half, W)):
				var top := img.get_pixel(x, y)
				if top != bg:
					drawn += 1
				var bot := img.get_pixel(x, y + 100)
				if maxf(maxf(absf(top.r - bot.r), absf(top.g - bot.g)),
						maxf(absf(top.b - bot.b), absf(top.a - bot.a))) > TOL:
					diff += 1
		print("[parity] %s: %d px drawn, %d differ" % [cases[i][0], drawn, diff])
		if diff > 0 or drawn == 0:
			failed = true
	print("FX PARITY FAILED" if failed else "FX PARITY OK")
	get_tree().quit()
