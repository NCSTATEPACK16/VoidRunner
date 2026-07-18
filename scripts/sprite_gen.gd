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


## 32x32 wall turret (V2.0, the original's missile-wall homage): riveted octagonal
## wall plate, recessed gun ring, stubby barrel with a red targeting eye. Reads as
## "part of the wall, but armed." Frames: 2 idle (eye pulse) + 1 hit-flash.
static func turret_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for f in 2:
		frames.append(ImageTexture.create_from_image(_draw_turret(f, false)))
	frames.append(ImageTexture.create_from_image(_draw_turret(0, true)))
	return frames


static func _draw_turret(frame: int, flash: bool) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var plate := Palette.WHITE if flash else Palette.GREY_3
	var plate_dk := Palette.GREY_7 if flash else Palette.GREY_1
	var edge := Palette.WHITE if flash else Palette.GREY_5
	# octagonal wall plate
	_rect(img, 6, 6, 20, 20, plate_dk)
	_rect(img, 8, 4, 16, 24, plate_dk)
	_rect(img, 4, 8, 24, 16, plate_dk)
	_rect(img, 9, 7, 14, 18, plate)
	_rect(img, 7, 9, 18, 14, plate)
	# corner rivets
	for rv in [Vector2i(8, 8), Vector2i(23, 8), Vector2i(8, 23), Vector2i(23, 23)]:
		_px(img, rv.x, rv.y, edge)
	# recessed gun ring + barrel mouth
	_ellipse(img, 16, 16, 7, 7, plate_dk)
	_ellipse(img, 16, 16, 5, 5, Palette.GREY_2 if not flash else Palette.WHITE)
	_ellipse(img, 16, 16, 3, 3, Palette.VOID_0)
	# targeting eye pulses between frames
	var eye := Palette.RED_4 if frame == 0 else Palette.RED_2
	_rect(img, 15, 15, 2, 2, eye if not flash else Palette.WHITE)
	# hazard ticks on the plate rim
	for hx in [10, 16, 22]:
		_px(img, hx, 5, Palette.ORANGE_2 if not flash else Palette.WHITE)
		_px(img, hx, 26, Palette.ORANGE_2 if not flash else Palette.WHITE)
	return img


## 64x64 boss: Sentinel-class guardian (Phase J) — broad layered warship hull,
## wide red eye bank, mantis-claw side pylons, orange belly vents that pulse
## between idle frames. Same 3-frame contract as every enemy (2 idle + hit
## flash); per-boss identity comes from Sprite3D.modulate (level.boss_tint).
static func boss_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for f in 2:
		frames.append(ImageTexture.create_from_image(_draw_boss(f, false)))
	frames.append(ImageTexture.create_from_image(_draw_boss(0, true)))
	return frames


static func _draw_boss(frame: int, flash: bool) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var plate := Palette.WHITE if flash else Palette.GREY_5
	var plate_dk := Palette.GREY_7 if flash else Palette.GREY_3
	var hull_dk := Palette.GREY_7 if flash else Palette.GREY_1
	var under := Palette.GREY_6 if flash else Palette.NAVY_1
	var trim := Palette.WHITE if flash else Palette.GREY_6
	var eye := Palette.WHITE if flash else Palette.RED_3
	var eye_hot := Palette.WHITE if flash else Palette.RED_4
	var vent_a := Palette.ORANGE_2 if frame == 0 else Palette.ORANGE_3
	var vent_b := Palette.ORANGE_3 if frame == 0 else Palette.ORANGE_2
	# under-hull shadow mass
	_ellipse(img, 32, 36, 26, 14, under)
	# main hull: wide armored wedge, layered plates
	_rect(img, 12, 22, 40, 18, plate_dk)
	_rect(img, 16, 18, 32, 10, plate)
	_rect(img, 8, 26, 48, 8, plate)
	_rect(img, 8, 26, 48, 2, trim)
	# top spine + command dome + antenna
	_ellipse(img, 32, 16, 10, 6, plate_dk)
	_ellipse(img, 32, 14, 6, 3, plate)
	_rect(img, 31, 6, 2, 6, hull_dk)
	_px(img, 31, 5, eye_hot)
	_px(img, 32, 5, eye_hot)
	# mantis-claw side pylons, drooping forward (tip glow bobs 1 px between frames)
	for s in [-1, 1]:
		var cx: int = 32 + s * 26
		_rect(img, cx - 2, 24, 4, 16, plate_dk)
		_rect(img, cx - 2, 38, 4, 6, hull_dk)
		_rect(img, (cx - 3) if s < 0 else (cx - 1), 44, 4, 4, hull_dk)
		_px(img, cx, 46 + frame, vent_b)
	# wide eye bank across the brow
	_rect(img, 18, 28, 28, 4, Palette.GREY_7 if flash else Palette.RED_1)
	_rect(img, 20, 29, 24, 2, eye)
	for ex in [24, 32, 40]:
		_px(img, ex, 29, eye_hot)
		_px(img, ex, 30, eye_hot)
	# armored jaw + intake grill
	_rect(img, 22, 34, 20, 4, hull_dk)
	for gx in range(24, 40, 3):
		_rect(img, gx, 35, 1, 2, plate_dk)
	# belly thruster vents (pulse between frames)
	for i in 4:
		_rect(img, 20 + i * 7, 42, 4, 3, vent_a if i % 2 == 0 else vent_b)
	# plate rivets
	for rx in range(12, 52, 8):
		_px(img, rx, 26, hull_dk)
		_px(img, rx, 33, hull_dk)
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


## 16x16 pickup icons (Phase J): shield = green cross, energy = cyan bolt,
## missile = grey dart — each on a dark disc so it reads against any wall.
static func pickup_texture(kind: String) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	match kind:
		"shield":
			_ellipse(img, 8, 8, 7, 7, Palette.GREEN_0)
			_ellipse(img, 8, 8, 6, 6, Palette.GREEN_1)
			_rect(img, 6, 3, 4, 10, Palette.GREEN_2)
			_rect(img, 3, 6, 10, 4, Palette.GREEN_2)
			_rect(img, 7, 7, 2, 2, Palette.WHITE)
		"energy":
			_ellipse(img, 8, 8, 7, 7, Palette.CYAN_0)
			_ellipse(img, 8, 8, 6, 6, Palette.CYAN_1)
			for i in 5:  # zigzag bolt
				_px(img, 9 - i, 3 + i, Palette.CYAN_3)
				_px(img, 10 - i, 3 + i, Palette.CYAN_3)
			for i in 5:
				_px(img, 8 - i + 3, 8 + i, Palette.CYAN_3)
				_px(img, 9 - i + 3, 8 + i, Palette.CYAN_3)
			_rect(img, 6, 7, 5, 2, Palette.WHITE)
		"missile":
			_ellipse(img, 8, 8, 7, 7, Palette.GREY_1)
			_ellipse(img, 8, 8, 6, 6, Palette.GREY_3)
			_rect(img, 6, 4, 4, 7, Palette.GREY_6)
			_rect(img, 7, 2, 2, 3, Palette.RED_3)
			_rect(img, 5, 10, 2, 2, Palette.GREY_5)
			_rect(img, 9, 10, 2, 2, Palette.GREY_5)
			_rect(img, 7, 11, 2, 2, Palette.ORANGE_2)
		"bomb":   # V2.0 plasma bomb: hot orb with four spark arms
			_ellipse(img, 8, 8, 7, 7, Palette.RED_0)
			_ellipse(img, 8, 8, 6, 6, Palette.RED_1)
			_ellipse(img, 8, 8, 4, 4, Palette.ORANGE_2)
			_ellipse(img, 8, 8, 2, 2, Palette.ORANGE_3)
			_rect(img, 7, 7, 2, 2, Palette.WHITE)
			for arm in [Vector2i(8, 2), Vector2i(8, 14), Vector2i(2, 8), Vector2i(14, 8)]:
				_px(img, arm.x, arm.y, Palette.ORANGE_3)
		"salvage":   # V2.2 L3: scrap nugget — chunky gold ingot with a glint
			_ellipse(img, 8, 9, 6, 5, Palette.ORANGE_0)
			_rect(img, 4, 6, 8, 6, Palette.ORANGE_1)
			_rect(img, 5, 5, 6, 5, Palette.ORANGE_2)
			_rect(img, 6, 4, 3, 3, Palette.ORANGE_3)
			_px(img, 7, 5, Palette.WHITE)
	return ImageTexture.create_from_image(img)


## 16x16 fuel cell (K3 destructible prop): squat grey canister with hazard
## stripes and a hot core window — reads as "this explodes" at tunnel distance.
static func prop_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	_rect(img, 4, 2, 8, 12, Palette.GREY_1)      # body shadow/outline
	_rect(img, 5, 2, 6, 12, Palette.GREY_3)      # body
	_rect(img, 5, 1, 6, 1, Palette.GREY_5)       # top cap
	_rect(img, 5, 14, 6, 1, Palette.GREY_0)      # base
	_rect(img, 4, 4, 8, 2, Palette.ORANGE_2)     # hazard band
	_rect(img, 4, 10, 8, 2, Palette.ORANGE_2)
	for hx in range(4, 12, 3):                   # dashes in the bands
		_px(img, hx, 4, Palette.VOID_0)
		_px(img, hx + 1, 11, Palette.VOID_0)
	_rect(img, 7, 7, 3, 2, Palette.RED_3)        # core window
	_px(img, 7, 7, Palette.ORANGE_3)             # hot glint
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


## V2.2 L1: 4 small jagged debris chunks in bright greys — tinted per enemy at
## spawn via Sprite3D.modulate, so one texture set serves every archetype.
static var _gib_cache: Array[ImageTexture] = []


static func gib_frames() -> Array[ImageTexture]:
	if not _gib_cache.is_empty():
		return _gib_cache
	var rng := RandomNumberGenerator.new()
	for i in 4:
		rng.seed = 7700 + i
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		for y in 10:
			for x in 10:
				var d := Vector2(x - 5, y - 5).length() / 4.0
				if d < 0.55 + rng.randf() * 0.45:
					var v := 0.62 + rng.randf() * 0.38
					_px(img, x, y, Color(v, v, v))
		_gib_cache.append(ImageTexture.create_from_image(img))
	return _gib_cache


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
