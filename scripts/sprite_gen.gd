class_name SpriteGen
## Procedural pixel-art sprites (PLAN.md C3): enemy drone frames, projectile stars,
## and explosion frames — drawn pixel-by-pixel from Palette colors, billboarded as
## Sprite3D/AnimatedSprite3D at runtime (never meshes; that's the authenticity rule C4).


## 32x32 drone: grey saucer hull, red eye cluster, stub legs. Frames: 2 idle (leg bob)
## + 1 hit-flash. Returns Array[ImageTexture].
static func drone_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for f in 2:
		frames.append(ImageTexture.create_from_image(_draw_drone(f, false)))
	frames.append(ImageTexture.create_from_image(_draw_drone(0, true)))
	return frames


static func _draw_drone(frame: int, flash: bool) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var hull := Palette.WHITE if flash else Palette.GREY_5
	var hull_dark := Palette.GREY_7 if flash else Palette.GREY_3
	var hull_edge := Palette.GREY_7 if flash else Palette.GREY_1
	# saucer hull: fat ellipse
	_ellipse(img, 16, 13, 12, 6, hull)
	_ellipse(img, 16, 15, 12, 4, hull_dark)
	# top dome
	_ellipse(img, 16, 9, 6, 4, hull)
	_ellipse(img, 16, 8, 4, 2, Palette.GREY_6 if not flash else Palette.WHITE)
	# dark rim
	for x in range(4, 28):
		var y := 13 + int(sqrt(maxf(0.0, 1.0 - pow((x - 16) / 12.0, 2))) * 6.0)
		_px(img, x, y + 1, hull_edge)
	# red eye cluster (front center)
	_rect(img, 13, 12, 6, 3, Palette.RED_1)
	_rect(img, 14, 12, 4, 2, Palette.RED_3)
	_px(img, 15, 12, Palette.RED_4)
	_px(img, 16, 12, Palette.RED_4)
	# stub legs (bob 1 px between frames)
	var leg_y := 19 + frame
	for lx in [8, 15, 22]:
		_rect(img, lx, leg_y, 2, 4, hull_edge)
		_rect(img, lx, leg_y + 4, 2, 1, hull_dark)
	# antenna
	_rect(img, 16, 3, 1, 3, hull_edge)
	_px(img, 16, 2, Palette.RED_3 if frame == 0 else Palette.RED_1)
	return img


## 32x32 weaver: small fast interceptor — swept-back grey wings, slim green
## fuselage, cyan cockpit glow, twin thrusters. Reads as agile/darty next to the
## round drone. Frames: 2 idle (wing bob) + 1 hit-flash. (I3)
static func weaver_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for f in 2:
		frames.append(ImageTexture.create_from_image(_draw_weaver(f, false)))
	frames.append(ImageTexture.create_from_image(_draw_weaver(0, true)))
	return frames


static func _draw_weaver(frame: int, flash: bool) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var hull := Palette.WHITE if flash else Palette.GREEN_2
	var hull_dk := Palette.GREY_7 if flash else Palette.GREEN_1
	var wing := Palette.WHITE if flash else Palette.GREY_5
	var wing_dk := Palette.GREY_7 if flash else Palette.GREY_3
	# swept-back wings forming a shallow V (bob 1 px between frames)
	var wy := 13 + frame
	for i in 12:
		_px(img, 15 - i, wy + i, wing)
		_px(img, 15 - i, wy + i - 1, wing_dk)
		_px(img, 16 + i, wy + i, wing)
		_px(img, 16 + i, wy + i - 1, wing_dk)
	# slim vertical fuselage
	_ellipse(img, 16, 15, 2, 10, hull_dk)
	_ellipse(img, 16, 14, 1, 8, hull)
	# cockpit / eye glow
	_rect(img, 15, 9, 2, 4, Palette.CYAN_3 if not flash else Palette.WHITE)
	# twin tail thrusters (flicker between frames)
	_px(img, 14, 25, Palette.ORANGE_2 if frame == 0 else Palette.ORANGE_3)
	_px(img, 17, 25, Palette.ORANGE_3 if frame == 0 else Palette.ORANGE_2)
	return img


## 32x32 hulk: heavy armored brute — broad navy torso, shoulder plates, a wide red
## eye slit, stubby legs. Reads as slow/tanky. Frames: 2 idle (leg bob) + hit-flash. (I3)
static func hulk_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for f in 2:
		frames.append(ImageTexture.create_from_image(_draw_hulk(f, false)))
	frames.append(ImageTexture.create_from_image(_draw_hulk(0, true)))
	return frames


static func _draw_hulk(frame: int, flash: bool) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var plate := Palette.WHITE if flash else Palette.NAVY_2
	var plate_dk := Palette.GREY_7 if flash else Palette.NAVY_1
	var edge := Palette.WHITE if flash else Palette.GREY_5
	var core := Palette.WHITE if flash else Palette.RED_3
	# broad rectangular torso
	_rect(img, 6, 8, 20, 16, plate_dk)
	_rect(img, 8, 10, 16, 12, plate)
	# shoulder plates (heavier top corners)
	_rect(img, 3, 9, 5, 8, plate_dk)
	_rect(img, 24, 9, 5, 8, plate_dk)
	_rect(img, 3, 9, 5, 2, edge)
	_rect(img, 24, 9, 5, 2, edge)
	# armored brow + wide red eye slit
	_rect(img, 9, 12, 14, 2, Palette.GREY_2)
	_rect(img, 11, 14, 10, 3, core)
	_rect(img, 13, 15, 6, 1, Palette.ORANGE_3 if not flash else Palette.WHITE)
	# plate rivets
	for rx in [10, 16, 22]:
		_px(img, rx, 11, edge)
		_px(img, rx, 21, edge)
	# heavy legs (bob 1 px)
	var ly := 24 + frame
	_rect(img, 8, ly, 4, 4, plate_dk)
	_rect(img, 20, ly, 4, 4, plate_dk)
	return img


## 16x16 four-point star (the enemy-shot shape from the research; also used for
## player bolts in weapon colors).
static func star_texture(core: Color, glow: Color, size: int = 16) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2
	var arm := size / 2 - 1
	for i in range(-arm, arm + 1):
		var fade := 1.0 - absf(i) / float(arm)
		var col := core if fade > 0.55 else glow
		if fade > 0.15:
			_px(img, c + i, c, col)
			_px(img, c, c + i, col)
		if absf(i) <= arm / 3:
			_px(img, c + i, c + i, glow)
			_px(img, c + i, c - i, glow)
	_rect(img, c - 1, c - 1, 2, 2, Palette.WHITE)
	return ImageTexture.create_from_image(img)


## Round bolt for the NEUTRON/SCATTER stream (bright core + halo).
static func bolt_texture(core: Color, glow: Color) -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	_ellipse(img, 6, 6, 5, 3, glow)
	_ellipse(img, 6, 6, 3, 2, core)
	_rect(img, 5, 5, 2, 2, Palette.WHITE)
	return ImageTexture.create_from_image(img)


## Missile: stubby dart with fins and an exhaust pixel.
static func missile_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	_rect(img, 5, 4, 6, 9, Palette.GREY_5)
	_rect(img, 6, 2, 4, 3, Palette.RED_3)
	_rect(img, 3, 10, 3, 3, Palette.GREY_3)
	_rect(img, 10, 10, 3, 3, Palette.GREY_3)
	_rect(img, 6, 13, 4, 2, Palette.ORANGE_2)
	_px(img, 7, 15, Palette.ORANGE_3)
	_px(img, 8, 15, Palette.ORANGE_3)
	return ImageTexture.create_from_image(img)


## 4-frame expanding explosion, 32x32.
static func explosion_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for f in 4:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var r := 4 + f * 4
		var t := f / 3.0
		var rim := Palette.RED_2 if f >= 2 else Palette.ORANGE_1
		var body := Palette.ORANGE_2 if f < 3 else Palette.RED_2
		var core := Palette.ORANGE_3 if f < 2 else Palette.ORANGE_2
		# ragged disc
		for a in 64:
			var ang := a * TAU / 64.0
			var rr := r * (0.75 + rng.randf() * 0.35)
			for step in int(rr):
				var col := core if step < rr * 0.4 else (body if step < rr * 0.8 else rim)
				if t > 0.6 and rng.randf() < t - 0.4:
					continue  # late frames go sparse/smoky
				_px(img, 16 + int(cos(ang) * step), 16 + int(sin(ang) * step), col)
		if f == 0:
			_rect(img, 14, 14, 4, 4, Palette.WHITE)
		frames.append(ImageTexture.create_from_image(img))
	return frames


## Build a billboarded Sprite3D configured for the chunky look.
static func make_sprite(tex: Texture2D, world_size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.pixel_size = world_size / float(tex.get_width())
	return s


# ---------- pixel helpers ----------

static func _px(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, color)


static func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for px in range(x, x + w):
		for py in range(y, y + h):
			_px(img, px, py, color)


static func _ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	for x in range(cx - rx, cx + rx + 1):
		for y in range(cy - ry, cy + ry + 1):
			var nx := (x - cx) / float(rx)
			var ny := (y - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				_px(img, x, y, color)
