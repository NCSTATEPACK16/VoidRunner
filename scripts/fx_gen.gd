class_name FxGen
## 3.0 Phase 3: procedural effect sprites, painted on the CPU at boot — fire,
## plasma and smoke read better as hand-shaded noise than as 3D models. Every
## color comes from a Palette ramp, so effects palettize cleanly. All sets are
## cached; ShotManager and GibManager pull them once.
##
##   fireball_frames()  10-frame explosion: white flash -> fire -> rolling smoke
##   shockwave_frames() expanding ring for big blasts
##   orb_frames(ramp)   2-frame shimmering plasma bolt in a weapon's ramp
##   plasma_frames()    2-frame spiky enemy plasma
##   smoke_frames()     4-frame dissolving puff (missile trails, blast aftermath)

static var _cache := {}


static func fireball_frames() -> Array[ImageTexture]:
	if _cache.has("fireball"):
		return _cache.fireball
	var out: Array[ImageTexture] = []
	var size := 48
	var n := FastNoiseLite.new()
	n.seed = 1995
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.14
	n.fractal_octaves = 3
	var count := 10
	for f in count:
		var t := f / float(count - 1)                 # 0 .. 1 over the blast
		var radius := size * 0.5 * (0.3 + 0.62 * sqrt(t))
		var heat := 1.15 - t * 0.9                    # core cools as it grows
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var dx := x - size * 0.5 + 0.5
				var dy := y - size * 0.5 + 0.5
				var d := sqrt(dx * dx + dy * dy) / radius
				var nz := n.get_noise_3d(x * 1.0, y * 1.0, f * 7.0) * 0.5 + 0.5
				var edge := d + (nz - 0.5) * 0.6
				if edge > 1.0:
					continue
				var v := (1.0 - edge) * heat + nz * 0.3
				# the last frames break up into a dark smoke cloud with a few
				# embers still glowing in it, thinning out a little more each frame
				if t > 0.6:
					if nz < (t - 0.6) * 1.9:
						continue
					if nz > 0.64 and d < 0.65:
						img.set_pixel(x, y, Palette.ramp(Palette.FIRE, clampi(5 + roundi((nz - 0.64) * 20.0), 5, 9)))
					elif (x + y) % 2 == 0:
						# stipple translucency: smoke on a checkerboard, the way
						# software renderers faked alpha — a blast next to the
						# camera never becomes an opaque wall
						img.set_pixel(x, y, Palette.ramp(Palette.GREY, clampi(1 + roundi(nz * 4.0), 1, 4)))
					continue
				img.set_pixel(x, y, Palette.ramp_f(Palette.FIRE, clampf(v * 1.1 + 0.18, 0.3, 1.0)))
		out.append(ImageTexture.create_from_image(img))
	_cache["fireball"] = out
	return out


static func shockwave_frames() -> Array[ImageTexture]:
	if _cache.has("shock"):
		return _cache.shock
	var out: Array[ImageTexture] = []
	var size := 48
	for f in 5:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var r := 6.0 + f * 4.4
		var w := 2.2 - f * 0.3
		for y in size:
			for x in size:
				var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length()
				var k := absf(d - r)
				if k < w:
					img.set_pixel(x, y, Palette.ramp(Palette.GOLD, clampi(15 - f * 2 - roundi(k * 2.0), 6, 15)))
		out.append(ImageTexture.create_from_image(img))
	_cache["shock"] = out
	return out


## A weapon's bolt: white core, a halo in `ramp`, a soft dithered rim. Frame 1 is
## the shimmer (core pulses a pixel wider, rim pixels shuffle).
static func orb_frames(ramp: int, size := 16) -> Array[ImageTexture]:
	var key := "orb%d_%d" % [ramp, size]
	if _cache.has(key):
		return _cache[key]
	var out: Array[ImageTexture] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = ramp * 31 + size
	for f in 2:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var half := size * 0.5
		for y in size:
			for x in size:
				var d := Vector2(x - half + 0.5, y - half + 0.5).length() / half
				if d > 1.0:
					continue
				var core := 0.34 + f * 0.08
				var c: Color
				if d < core:
					c = Palette.ramp(Palette.GREY, 15)
				elif d < 0.62:
					c = Palette.ramp(ramp, 13 - roundi((d - core) * 8.0))
				elif rng.randf() < (1.0 - d) * 2.2:   # dithered outer glow
					c = Palette.ramp(ramp, 8)
				else:
					continue
				img.set_pixel(x, y, c)
		out.append(ImageTexture.create_from_image(img))
	_cache[key] = out
	return out


## Enemy plasma: a hot six-point star, spikes counter-rotating between frames.
static func plasma_frames(size := 16) -> Array[ImageTexture]:
	var key := "plasma%d" % size
	if _cache.has(key):
		return _cache[key]
	var out: Array[ImageTexture] = []
	var half := size * 0.5
	for f in 2:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var v := Vector2(x - half + 0.5, y - half + 0.5)
				var d := v.length() / half
				var a := atan2(v.y, v.x) + f * PI / 6.0
				var spike := pow(absf(cos(a * 3.0)), 6.0)
				var reach := 0.42 + spike * 0.55
				if d > reach:
					continue
				var c: Color
				if d < 0.26:
					c = Palette.ramp(Palette.GOLD, 15)
				elif d < 0.45:
					c = Palette.ramp(Palette.ORANGE, 12)
				else:
					c = Palette.ramp(Palette.RED, clampi(12 - roundi(d * 6.0), 6, 12))
				img.set_pixel(x, y, c)
		out.append(ImageTexture.create_from_image(img))
	_cache[key] = out
	return out


static func smoke_frames(size := 16) -> Array[ImageTexture]:
	var key := "smoke%d" % size
	if _cache.has(key):
		return _cache[key]
	var out: Array[ImageTexture] = []
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.25
	var half := size * 0.5
	for f in 4:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var r := 0.55 + f * 0.14
		for y in size:
			for x in size:
				var d := Vector2(x - half + 0.5, y - half + 0.5).length() / half
				var nz := n.get_noise_3d(x * 1.0, y * 1.0, f * 5.0) * 0.5 + 0.5
				if d + (nz - 0.5) * 0.5 > r or nz < f * 0.16:
					continue
				if f >= 2 and (x + y) % 2 == 1:
					continue   # stipple: thinning puffs go see-through
				img.set_pixel(x, y, Palette.ramp(Palette.GREY, clampi(8 - f - roundi(d * 3.0), 2, 9)))
		out.append(ImageTexture.create_from_image(img))
	_cache[key] = out
	return out


## Palette ramp that best matches a weapon's tint (bolts are drawn in-ramp).
static func ramp_for(color: Color) -> int:
	var best := Palette.CYAN
	var best_d := INF
	for r in [Palette.CYAN, Palette.GREEN, Palette.LIME, Palette.ORANGE, Palette.RED,
			Palette.MAGENTA, Palette.VIOLET, Palette.BLUE, Palette.GOLD]:
		var c := Palette.ramp(r, 11)
		var d := (c.r - color.r) ** 2 + (c.g - color.g) ** 2 + (c.b - color.b) ** 2
		if d < best_d:
			best_d = d
			best = r
	return best
