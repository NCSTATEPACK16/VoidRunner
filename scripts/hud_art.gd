class_name HudArt
## 3.0 Phase 4: cockpit art for the HUD, painted once at boot in Palette ramps —
## the console plate (brushed steel, rivets, bevelled recessed display wells).
## Everything the HUD animates (digits, LED gauges, lamps, radar) draws on top of
## it at runtime.

## Recessed display wells on the console plate, in console-local coordinates
## (the plate is 320 x 36 and sits at the bottom of the 320 x 200 view).
const WELLS := [
	Rect2i(4, 4, 98, 28),     # weapons: four slots, missile count, weapon name
	Rect2i(106, 4, 34, 28),   # mission clock
	Rect2i(144, 3, 32, 30),   # radar (round scope, bezel painted on top)
	Rect2i(180, 4, 30, 28),   # evade lamp
	Rect2i(214, 4, 102, 28),  # shield / energy / heat gauges
]

## Side of the seamless brushed-steel tile the canopy struts repeat.
const TILE := 32

static var _tile: ImageTexture


static func console(w := 320, h := 36) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.9
	n.noise_type = FastNoiseLite.TYPE_VALUE
	# brushed steel: horizontal grain (noise stretched along x)
	for y in h:
		for x in w:
			var g := n.get_noise_2d(x * 0.12, y * 1.0) * 0.5 + 0.5
			img.set_pixel(x, y, Palette.ramp(Palette.STEEL, 4 + roundi(g * 2.0)))
	# bevelled top rim + a dark groove under it
	for x in w:
		img.set_pixel(x, 0, Palette.ramp(Palette.STEEL, 11))
		img.set_pixel(x, 1, Palette.ramp(Palette.STEEL, 8))
		img.set_pixel(x, h - 1, Palette.ramp(Palette.STEEL, 1))
	# rivets along the rim, between the wells
	for rx in [2, 104, 142, 178, 212, 317]:
		_rivet(img, rx, 3)
		_rivet(img, rx, h - 5)
	# the wells: dark glass, lit bottom-right lip, shadowed top-left lip
	for r: Rect2i in WELLS:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var edge_tl := x == r.position.x or y == r.position.y
				var edge_br := x == r.end.x - 1 or y == r.end.y - 1
				var c: Color
				if edge_tl:
					c = Palette.ramp(Palette.STEEL, 1)
				elif edge_br:
					c = Palette.ramp(Palette.STEEL, 9)
				else:
					# faint scan-glass sheen: a slightly lighter band across the top
					var sheen := 1 if y < r.position.y + 3 else 0
					c = Palette.ramp(Palette.BLUE, 1 + sheen)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _rivet(img: Image, x: int, y: int) -> void:
	if x < 0 or x + 1 >= img.get_width():
		return
	img.set_pixel(x, y, Palette.ramp(Palette.STEEL, 12))
	img.set_pixel(x + 1, y, Palette.ramp(Palette.STEEL, 8))
	img.set_pixel(x, y + 1, Palette.ramp(Palette.STEEL, 8))
	img.set_pixel(x + 1, y + 1, Palette.ramp(Palette.STEEL, 2))


## Seamless brushed steel for the canopy struts, a shade darker than the console
## so the frame recedes. Streaks run along x as whole-period sines and every row
## is independent, so the tile repeats cleanly both ways.
static func steel_tile() -> ImageTexture:
	if _tile:
		return _tile
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1995
	for y in TILE:
		var phase := rng.randf() * TAU
		var base := rng.randf_range(-0.2, 0.2)
		var k := float(rng.randi_range(1, 3))
		for x in TILE:
			var g := 0.5 + base + 0.22 * sin(TAU * k * x / TILE + phase) \
				+ rng.randf_range(-0.12, 0.12)
			img.set_pixel(x, y, Palette.ramp(Palette.STEEL, 3 + clampi(roundi(g * 2.0), 0, 2)))
	_tile = ImageTexture.create_from_image(img)
	return _tile
