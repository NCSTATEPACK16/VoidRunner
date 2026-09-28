class_name TextureGen
## Procedural world textures (PLAN.md C2, rebuilt for 3.0). Every texel is a
## Palette ramp entry; noise comes from FastNoiseLite's seamless images (native,
## fast) so every 64x64 tile wraps cleanly. Texture ALPHA is a lighting flag, not
## transparency: alpha 0 marks full-bright texels (light panels, screens, lava,
## runes) that sector.gdshader draws at full intensity regardless of light.
##
## Texture axes as WorldBuilder maps them: x runs ALONG the tunnel; y runs across
## a face — top-to-bottom on walls, side-to-side on floors/ceilings, across the
## chamfer strip on trims. The floor accent strip is the exception (y = along).
##
## A theme is a motif (how the tiles are painted) plus palette ramps and the
## lighting mood WorldBuilder bakes with. Sets are painted once per theme and
## cached — two levels sharing a theme share the textures.

const SIZE := 64

## Texture keys every theme provides. WorldBuilder builds one material per key.
const KEYS := ["wall_a", "wall_b", "wall_c", "wall_d", "floor", "floor_b", "ceil",
	"ceil_lamp", "trim", "strip", "door"]

## Zone themes (PLAN.md E6 -> 3.0). Keys:
##   motif     panel | rock | organic | ice | rune — which painter runs
##   base/trim/floor/ceil/glow/warn — Palette ramp ids the painter draws with
##   accent/accent2 — door glow and HUD tint; lamp/lamp2 — baked light colors
##   (ceiling fixtures / wall light panels); amb — baked ambient floor
##   fog_end   fog-to-black distance (shorter = more oppressive)
static var THEMES := {
	"tech": {
		"motif": "panel", "base": Palette.STEEL, "trim": Palette.STEEL,
		"floor": Palette.STEEL, "ceil": Palette.STEEL, "glow": Palette.CYAN,
		"warn": Palette.GOLD,
		"accent": Color("22c4d8"), "accent2": Color("f07818"),
		"lamp": Color(1.0, 0.92, 0.78), "lamp2": Color(0.45, 0.95, 1.0),
		"amb": Color(0.22, 0.24, 0.30), "fog_end": 130.0,
	},
	"navy": {
		"motif": "panel", "base": Palette.BLUE, "trim": Palette.BRASS,
		"floor": Palette.STEEL, "ceil": Palette.BLUE, "glow": Palette.GOLD,
		"warn": Palette.RED,
		"accent": Color("eac21a"), "accent2": Color("e8302a"),
		"lamp": Color(1.0, 0.85, 0.55), "lamp2": Color(1.0, 0.75, 0.30),
		"amb": Color(0.20, 0.21, 0.32), "fog_end": 120.0,
	},
	"rock": {
		"motif": "rock", "base": Palette.RUST, "trim": Palette.STEEL,
		"floor": Palette.RUST, "ceil": Palette.RUST, "glow": Palette.FIRE,
		"warn": Palette.GOLD,
		"accent": Color("f07818"), "accent2": Color("22c4d8"),
		"lamp": Color(1.0, 0.70, 0.40), "lamp2": Color(1.0, 0.45, 0.15),
		"amb": Color(0.22, 0.18, 0.15), "fog_end": 105.0,
	},
	"hive": {
		"motif": "organic", "base": Palette.FLESH, "trim": Palette.BRASS,
		"floor": Palette.MAGENTA, "ceil": Palette.FLESH, "glow": Palette.LIME,
		"warn": Palette.MAGENTA,
		"accent": Color("9ad62a"), "accent2": Color("e03cb0"),
		"lamp": Color(0.70, 1.0, 0.45), "lamp2": Color(1.0, 0.45, 0.85),
		"amb": Color(0.22, 0.15, 0.18), "fog_end": 95.0,
	},
	"void": {
		"motif": "rune", "base": Palette.VIOLET, "trim": Palette.STEEL,
		"floor": Palette.VIOLET, "ceil": Palette.VIOLET, "glow": Palette.MAGENTA,
		"warn": Palette.VIOLET,
		"accent": Color("e03cb0"), "accent2": Color("8a5ae8"),
		"lamp": Color(0.85, 0.55, 1.0), "lamp2": Color(1.0, 0.40, 0.80),
		"amb": Color(0.17, 0.14, 0.24), "fog_end": 100.0,
	},
	"ice": {
		"motif": "ice", "base": Palette.CYAN, "trim": Palette.STEEL,
		"floor": Palette.BLUE, "ceil": Palette.BLUE, "glow": Palette.CYAN,
		"warn": Palette.BLUE,
		"accent": Color("c8fcff"), "accent2": Color("f07818"),
		"lamp": Color(0.80, 0.95, 1.0), "lamp2": Color(0.55, 0.85, 1.0),
		"amb": Color(0.22, 0.27, 0.35), "fog_end": 140.0,
	},
}

static var _cache := {}


## All of a theme's textures, keyed by KEYS. Painted on first request, cached.
static func theme_textures(theme_id: String) -> Dictionary:
	if _cache.has(theme_id):
		return _cache[theme_id]
	var t: Dictionary = THEMES[theme_id]
	var s: int = hash(theme_id) & 0xffff
	var imgs := {}
	match t.motif:
		"rock":
			_paint_rock(t, s, imgs)
		"organic":
			_paint_organic(t, s, imgs)
		"ice":
			_paint_ice(t, s, imgs)
		"rune":
			_paint_rune(t, s, imgs)
		_:
			_paint_panel(t, s, imgs)
	imgs["strip"] = _strip(t)
	imgs["door"] = _door(t, s)
	var out := {}
	for key in KEYS:
		var img: Image = imgs[key]
		img.generate_mipmaps()
		out[key] = ImageTexture.create_from_image(img)
	_cache[theme_id] = out
	return out


# =====================================================================
# motif painters — each fills wall_a..d, floor, floor_b, ceil, ceil_lamp, trim
# =====================================================================

## Space-station plating: bevelled panels, running lights, fixtures, consoles.
static func _paint_panel(t: Dictionary, s: int, out: Dictionary) -> void:
	var b: int = t.base
	var g: int = t.glow
	var grain := _noise(s + 1, 0.11, FastNoiseLite.TYPE_VALUE, 2)
	# --- wall_a: upper band / main panels / kick plate, with running lights ---
	var a := _img()
	_fill_noise(a, grain, b, 6, 8)
	_panel(a, 0, 0, 32, 18, b, 8, grain)
	_panel(a, 32, 0, 32, 18, b, 8, grain)
	_panel(a, 0, 18, 32, 28, b, 7, grain)
	_panel(a, 32, 18, 32, 28, b, 7, grain)
	_panel(a, 0, 46, 64, 18, b, 5, grain)
	for x in range(3, 64, 8):
		_glow_rect(a, x, 17, 3, 1, Palette.ramp(g, 12))
	for x in [4, 36]:
		_rivet(a, x, 3, b, 8)
		_rivet(a, x + 23, 3, b, 8)
		_rivet(a, x, 49, b, 5)
		_rivet(a, x + 23, 49, b, 5)
	_slots(a, 6, 52, 52, b, 5)
	out["wall_a"] = a
	# --- wall_b: the same wall with a fluorescent light box in the main band ---
	var lb := a.duplicate() as Image
	_bevel_box(lb, 5, 21, 54, 22, Palette.ramp(b, 2), Palette.ramp(b, 10))
	for y in range(23, 41):
		var mid := 1.0 - absf(y - 31.5) / 9.0
		var c := Palette.ramp(g, 11 + roundi(mid * 4.0))
		for x in range(7, 57):
			var diff := (x % 6 == 0) or (y % 5 == 0)
			_glow_px(lb, x, y, Palette.ramp(g, 10) if diff else c)
	out["wall_b"] = lb
	# --- wall_c: control console — scrolling-text screen and a lamp grid ---
	var cc := a.duplicate() as Image
	_bevel_box(cc, 4, 20, 30, 24, Palette.ramp(b, 3), Palette.ramp(b, 10))
	_rect(cc, 5, 21, 28, 22, Palette.ramp(Palette.GREY, 1))
	var rng := _rng(s + 7)
	for row in range(23, 42, 3):
		var x := 7
		while x < 30:
			var run := rng.randi_range(1, 5)
			if rng.randf() < 0.75:
				for k in run:
					if x + k < 31:
						_glow_px(cc, x + k, row, Palette.ramp(g, rng.randi_range(9, 14)))
			x += run + 1
	_bevel_box(cc, 37, 20, 23, 24, Palette.ramp(b, 3), Palette.ramp(b, 10))
	var lamp_ramps := [Palette.RED, Palette.GREEN, Palette.GOLD]
	for gy in 3:
		for gx in 3:
			var lr: int = lamp_ramps[(gx + gy * 2) % 3]
			if rng.randf() < 0.7:
				_glow_rect(cc, 40 + gx * 7, 23 + gy * 7, 4, 3, Palette.ramp(lr, 12))
			else:
				_rect(cc, 40 + gx * 7, 23 + gy * 7, 4, 3, Palette.ramp(lr, 3))
	out["wall_c"] = cc
	# --- wall_d: intake grille over a hazard-striped kick plate ---
	var d := a.duplicate() as Image
	_bevel_box(d, 4, 20, 56, 24, Palette.ramp(b, 3), Palette.ramp(b, 10))
	_grille(d, 5, 21, 54, 22, b, 6)
	_hazard(d, 0, 50, 64, 8, t.warn, Palette.GREY)
	out["wall_d"] = d
	# --- floor: tread plate; floor_b: open grating over a lit sump ---
	var fl := _img()
	var fgrain := _noise(s + 3, 0.2, FastNoiseLite.TYPE_VALUE, 1)
	_fill_noise(fl, fgrain, t.floor, 4, 6)
	for cy in range(0, 64, 8):
		for cx in range(0, 64, 8):
			var ox := 2 if (cy / 8) % 2 == 0 else 6
			_px(fl, cx + ox, cy + 2, Palette.ramp(t.floor, 9))
			_px(fl, cx + ox + 1, cy + 3, Palette.ramp(t.floor, 8))
			_px(fl, cx + ox + 1, cy + 2, Palette.ramp(t.floor, 2))
	_line_h(fl, 0, Palette.ramp(t.floor, 1))
	_line_h(fl, 32, Palette.ramp(t.floor, 1))
	_line_h(fl, 1, Palette.ramp(t.floor, 8))
	_line_h(fl, 33, Palette.ramp(t.floor, 8))
	out["floor"] = fl
	var gr := _img()
	_rect(gr, 0, 0, 64, 64, Palette.ramp(t.floor, 1))
	for y in 64:
		for x in 64:
			if y % 4 < 2 or x % 8 < 2:
				var hi := (y % 4 == 0) or (x % 8 == 0)
				_px(gr, x, y, Palette.ramp(t.floor, 9 if hi else 6))
			elif (x / 8 + y / 4) % 7 == 0:
				_glow_px(gr, x, y, Palette.ramp(g, 5))   # faint light welling up
	out["floor_b"] = gr
	# --- ceiling panels and the lamp fixture ---
	var ce := _img()
	_fill_noise(ce, grain, t.ceil, 4, 6)
	_panel(ce, 0, 0, 32, 32, t.ceil, 5, grain)
	_panel(ce, 32, 0, 32, 32, t.ceil, 6, grain)
	_panel(ce, 0, 32, 32, 32, t.ceil, 6, grain)
	_panel(ce, 32, 32, 32, 32, t.ceil, 5, grain)
	_slots(ce, 38, 8, 20, t.ceil, 4)
	out["ceil"] = ce
	out["ceil_lamp"] = _lamp_fixture(ce, t.ceil, g)
	out["trim"] = _pipes(t.trim, t.base, g, grain)


## Carved reactor galleries: embossed rock, glowing magma veins, steel girders.
static func _paint_rock(t: Dictionary, s: int, out: Dictionary) -> void:
	var b: int = t.base
	var h := _noise(s + 1, 0.06, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4)
	var cells := _cell_edges(s + 2, 0.07)
	var a := _img()
	_emboss(a, h, b, 3, 10)
	for i in SIZE * SIZE:
		if cells[i] < 18:
			_px(a, i % SIZE, i / SIZE, Palette.ramp(b, 1))
	out["wall_a"] = a
	var lava := a.duplicate() as Image
	for i in SIZE * SIZE:
		if cells[i] < 12:
			_glow_px(lava, i % SIZE, i / SIZE, Palette.ramp(t.glow, 13 - cells[i] / 3))
		elif cells[i] < 22:
			_px(lava, i % SIZE, i / SIZE, Palette.ramp(t.glow, 4))
	out["wall_b"] = lava
	var cr := a.duplicate() as Image
	var rng := _rng(s + 5)
	for k in 5:
		_crystal(cr, rng.randi_range(4, 59), rng.randi_range(6, 57), rng.randi_range(3, 5),
			Palette.CYAN)
	out["wall_c"] = cr
	var gd := a.duplicate() as Image
	_girder(gd, 24, t.trim)
	_hazard(gd, 0, 56, 64, 5, t.warn, Palette.GREY)
	out["wall_d"] = gd
	var fl := _img()
	var gravel := _noise(s + 3, 0.25, FastNoiseLite.TYPE_VALUE, 2)
	_fill_noise(fl, gravel, b, 2, 7)
	out["floor"] = fl
	var walk := _img()
	_fill_noise(walk, gravel, b, 2, 5)
	_panel(walk, 8, 0, 48, 64, t.trim, 6, gravel)
	for y in range(0, 64, 4):
		_rect(walk, 10, y, 44, 1, Palette.ramp(t.trim, 3))
	out["floor_b"] = walk
	var ce := _img()
	_emboss(ce, h, b, 1, 6)
	out["ceil"] = ce
	out["ceil_lamp"] = _cage_lamp(ce, t.trim, Palette.ORANGE)
	var tr := _img()
	var rough := _noise(s + 9, 0.12, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	_emboss(tr, rough, b, 2, 8)
	_pipe_band(tr, 26, 12, Palette.GREY, 3)
	for x in range(6, 64, 16):
		_glow_rect(tr, x, 30, 2, 2, Palette.ramp(Palette.GOLD, 13))
	out["trim"] = tr


## Hive tissue: warped flesh, dark veins, glowing pustules, bone ribs.
static func _paint_organic(t: Dictionary, s: int, out: Dictionary) -> void:
	var b: int = t.base
	var flesh := _noise(s + 1, 0.05, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var vein := _noise(s + 2, 0.09, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	var a := _img()
	_emboss(a, flesh, b, 4, 11)
	for i in SIZE * SIZE:
		var v := absi(vein[i] - 128)
		if v < 6:
			_px(a, i % SIZE, i / SIZE, Palette.ramp(Palette.MAGENTA, 3))
		elif v < 10:
			_px(a, i % SIZE, i / SIZE, Palette.ramp(Palette.MAGENTA, 6))
	out["wall_a"] = a
	var pus := a.duplicate() as Image
	var rng := _rng(s + 4)
	for k in 6:
		_orb(pus, rng.randi_range(6, 57), rng.randi_range(6, 57), rng.randi_range(3, 6),
			t.glow, true)
	out["wall_b"] = pus
	var rib := a.duplicate() as Image
	for x0 in [6, 30, 54]:
		for y in 64:
			for dx in 7:
				var shade := 12 - absi(dx - 2) * 2 - (1 if y % 9 == 0 else 0)
				_px(rib, x0 + dx, y, Palette.ramp(t.trim, clampi(shade, 3, 13)))
	out["wall_c"] = rib
	var pit := a.duplicate() as Image
	for y in 64:
		for x in 64:
			var r := Vector2(x - 31.5, y - 31.5).length()
			if r < 18.0:
				var ring := int(r) % 4
				_px(pit, x, y, Palette.ramp(Palette.MAGENTA, 1 + ring + int(r / 6.0)))
	_orb(pit, 32, 32, 4, Palette.RED, true)
	out["wall_d"] = pit
	var fl := _img()
	_emboss(fl, flesh, t.floor, 2, 7)
	for i in SIZE * SIZE:
		if vein[i] > 200:
			_px(fl, i % SIZE, i / SIZE, Palette.ramp(t.floor, 10))
	out["floor"] = fl
	var bone := _img()
	_emboss(bone, flesh, b, 2, 5)
	for y in range(0, 64, 16):
		_panel(bone, 4, y + 2, 56, 12, t.trim, 9, flesh)
	out["floor_b"] = bone
	var ce := _img()
	_emboss(ce, vein, b, 2, 7)
	out["ceil"] = ce
	var sac := ce.duplicate() as Image
	_orb(sac, 32, 32, 14, t.glow, true)
	out["ceil_lamp"] = sac
	var tr := _img()
	_emboss(tr, flesh, b, 3, 8)
	for x in range(0, 64, 16):
		_orb(tr, x + 8, 32, 7, t.trim, false)
	out["trim"] = tr


## Glacial conduits: faceted ice, frost, cold light.
static func _paint_ice(t: Dictionary, s: int, out: Dictionary) -> void:
	var b: int = t.base
	var facets := _cell_values(s + 1, 0.09)
	var edges := _cell_edges(s + 1, 0.09)
	var rng := _rng(s + 3)
	var a := _img()
	for i in SIZE * SIZE:
		var x := i % SIZE
		var y := i / SIZE
		var shade := 7 + facets[i] * 5 / 255
		if edges[i] < 10:
			shade = 13
		_px(a, x, y, Palette.ramp(b, shade))
		if rng.randf() < 0.03:
			_px(a, x, y, Palette.ramp(Palette.GREY, 15))
	out["wall_a"] = a
	var lit := a.duplicate() as Image
	for i in SIZE * SIZE:
		var x := i % SIZE
		var y := i / SIZE
		if Vector2(x - 32, (y - 32) * 1.6).length() < 20.0:
			_glow_px(lit, x, y, Palette.ramp(t.glow, 11 + (3 if edges[i] < 12 else 0)))
	out["wall_b"] = lit
	var fm := _img()
	var grain := _noise(s + 5, 0.11, FastNoiseLite.TYPE_VALUE, 2)
	_fill_noise(fm, grain, t.trim, 6, 8)
	_panel(fm, 0, 0, 32, 64, t.trim, 7, grain)
	_panel(fm, 32, 0, 32, 64, t.trim, 7, grain)
	for y in 64:
		var frost := absf(y - 31.5) / 32.0
		for x in 64:
			if rng.randf() < frost * frost * 0.8:
				_px(fm, x, y, Palette.ramp(Palette.CYAN, rng.randi_range(12, 15)))
	out["wall_c"] = fm
	var ic := a.duplicate() as Image
	for k in 14:
		var x0 := rng.randi_range(0, 63)
		var ln := rng.randi_range(10, 34)
		for y in ln:
			var w := 2 if y < ln * 0.4 else 1
			for dx in w:
				_px(ic, x0 + dx, y, Palette.ramp(Palette.CYAN, 15 - y * 5 / ln))
	out["wall_d"] = ic
	var fl := _img()
	for i in SIZE * SIZE:
		_px(fl, i % SIZE, i / SIZE, Palette.ramp(t.floor, 8 + facets[i] * 3 / 255))
	for k in 10:
		var y0 := rng.randi_range(0, 63)
		var x0 := rng.randi_range(0, 63)
		for d in rng.randi_range(6, 18):
			_px(fl, x0 + d, y0 + d / 3, Palette.ramp(t.floor, 13))
	out["floor"] = fl
	var fg := _img()
	_rect(fg, 0, 0, 64, 64, Palette.ramp(t.floor, 2))
	for y in 64:
		for x in 64:
			if y % 4 < 2 or x % 8 < 2:
				_px(fg, x, y, Palette.ramp(Palette.CYAN, 13 if rng.randf() < 0.3 else 9))
	out["floor_b"] = fg
	var ce := _img()
	for i in SIZE * SIZE:
		_px(ce, i % SIZE, i / SIZE, Palette.ramp(t.ceil, 5 + facets[i] * 4 / 255))
	out["ceil"] = ce
	out["ceil_lamp"] = _lamp_fixture(ce, t.ceil, Palette.CYAN)
	out["trim"] = _pipes(t.trim, Palette.CYAN, Palette.CYAN, grain)


## Beyond the Rift: dark violet plating shot through with glowing circuitry.
static func _paint_rune(t: Dictionary, s: int, out: Dictionary) -> void:
	var b: int = t.base
	var g: int = t.glow
	var grain := _noise(s + 1, 0.13, FastNoiseLite.TYPE_VALUE, 2)
	var rng := _rng(s + 2)
	var a := _img()
	_fill_noise(a, grain, b, 2, 4)
	_panel(a, 0, 0, 32, 32, b, 4, grain)
	_panel(a, 32, 0, 32, 32, b, 3, grain)
	_panel(a, 0, 32, 32, 32, b, 3, grain)
	_panel(a, 32, 32, 32, 32, b, 4, grain)
	_circuits(a, rng, g, 7)
	out["wall_a"] = a
	var rune := a.duplicate() as Image
	_rune(rune, 32, 32, g)
	out["wall_b"] = rune
	var win := a.duplicate() as Image
	_bevel_box(win, 6, 8, 52, 48, Palette.ramp(b, 6), Palette.ramp(b, 1))
	_rect(win, 7, 9, 50, 46, Palette.ramp(Palette.GREY, 0))
	for k in 40:
		var sx := rng.randi_range(8, 55)
		var sy := rng.randi_range(10, 53)
		var star := Palette.ramp(Palette.VIOLET if rng.randf() < 0.4 else Palette.GREY,
			rng.randi_range(9, 15))
		_glow_px(win, sx, sy, star)
	_orb(win, 22, 26, 5, Palette.MAGENTA, true)   # something far away, watching
	out["wall_c"] = win
	var rb := _img()
	_fill_noise(rb, grain, b, 1, 3)
	for x in range(0, 64, 8):
		for y in 64:
			_px(rb, x + 1, y, Palette.ramp(b, 6))
			_px(rb, x + 2, y, Palette.ramp(b, 5))
			_px(rb, x + 3, y, Palette.ramp(b, 2))
	_circuits(rb, rng, g, 3)
	out["wall_d"] = rb
	var fl := _img()
	_fill_noise(fl, grain, t.floor, 1, 3)
	for i in 64:
		_glow_px(fl, i, 0, Palette.ramp(g, 7))
		_glow_px(fl, 0, i, Palette.ramp(g, 7))
		_glow_px(fl, i, 32, Palette.ramp(g, 5))
		_glow_px(fl, 32, i, Palette.ramp(g, 5))
	out["floor"] = fl
	var fb := fl.duplicate() as Image
	for c in [Vector2i(0, 0), Vector2i(32, 32), Vector2i(0, 32), Vector2i(32, 0)]:
		_orb(fb, c.x, c.y, 3, g, true)
	out["floor_b"] = fb
	var ce := _img()
	_fill_noise(ce, grain, t.ceil, 1, 3)
	for k in 12:
		_glow_px(ce, rng.randi_range(0, 63), rng.randi_range(0, 63), Palette.ramp(g, 9))
	out["ceil"] = ce
	var orb := ce.duplicate() as Image
	_orb(orb, 32, 32, 12, Palette.VIOLET, true)
	_orb(orb, 32, 32, 6, Palette.MAGENTA, true)
	out["ceil_lamp"] = orb
	var tr := _img()
	_fill_noise(tr, grain, t.trim, 2, 4)
	_pipe_band(tr, 8, 12, t.trim, 7)
	_pipe_band(tr, 44, 12, t.trim, 7)
	for x in 64:
		for y in range(26, 38):
			var mid := 1.0 - absf(y - 31.5) / 6.0
			_glow_px(tr, x, y, Palette.ramp(g, 8 + roundi(mid * 6.0)))
	out["trim"] = tr


# =====================================================================
# shared tiles
# =====================================================================

## Floor accent strip: two rails and bright chevrons pointing down the tunnel.
## y runs ALONG the tunnel here; WorldBuilder scrolls v so the chevrons march.
static func _strip(t: Dictionary) -> Image:
	var img := _img()
	var g: int = t.glow
	_rect(img, 0, 0, 64, 64, Palette.ramp(Palette.GREY, 1))
	for y in 64:
		_px(img, 2, y, Palette.ramp(t.trim, 7))
		_px(img, 61, y, Palette.ramp(t.trim, 7))
		_px(img, 3, y, Palette.ramp(t.trim, 3))
		_px(img, 60, y, Palette.ramp(t.trim, 3))
	for base_y in [0, 32]:
		for row in 12:
			var half := 22 - row * 2
			for dx in range(-half, half + 1):
				if absi(dx) > half - 6:
					var shade := 14 - row / 3 - (absi(dx) - (half - 6)) / 3
					_glow_px(img, 32 + dx, base_y + row + absi(dx) / 3, Palette.ramp(g, clampi(shade, 6, 15)))
	return img


## Bulkhead door: heavy plate, hazard chevrons, bolts, a red lock lamp. Split
## down the middle (x = 31|32) — WorldBuilder slides the halves apart.
static func _door(t: Dictionary, s: int) -> Image:
	var img := _img()
	var grain := _noise(s + 11, 0.15, FastNoiseLite.TYPE_VALUE, 2)
	var plate: int = t.trim
	_fill_noise(img, grain, plate, 6, 8)
	_panel(img, 2, 2, 28, 60, plate, 7, grain)
	_panel(img, 34, 2, 28, 60, plate, 7, grain)
	_rect(img, 31, 0, 2, 64, Palette.ramp(Palette.GREY, 0))
	for y in range(0, 64):
		for x in range(4, 60):
			if y >= 26 and y < 38 and ((x + y) / 4) % 2 == 0:
				_px(img, x, y, Palette.ramp(t.warn, 11))
			elif y >= 26 and y < 38:
				_px(img, x, y, Palette.ramp(Palette.GREY, 2))
	for bx in [6, 25, 38, 57]:
		for by in [6, 20, 44, 58]:
			_rivet(img, bx, by, plate, 9)
	_orb(img, 16, 13, 3, Palette.RED, true)
	_orb(img, 47, 13, 3, Palette.RED, true)
	return img


## Horizontal pipe bundle for chamfer trims: big pipe, small pipe, big pipe,
## glowing conduit, brackets every 16 px.
static func _pipes(pipe_ramp: int, pipe2_ramp: int, glow_ramp: int,
		grain: PackedByteArray) -> Image:
	var img := _img()
	_fill_noise(img, grain, Palette.STEEL, 2, 4)
	_pipe_band(img, 4, 14, pipe_ramp, 8)
	_pipe_band(img, 21, 8, pipe2_ramp, 9)
	_pipe_band(img, 32, 14, pipe_ramp, 7)
	for x in 64:
		for y in range(50, 56):
			var mid := 1.0 - absf(y - 52.5) / 3.0
			_glow_px(img, x, y, Palette.ramp(glow_ramp, 9 + roundi(mid * 5.0)))
	for x in range(6, 64, 16):
		_rect(img, x, 2, 3, 46, Palette.ramp(Palette.STEEL, 3))
		_rect(img, x, 2, 1, 46, Palette.ramp(Palette.STEEL, 7))
	return img


## Big recessed ceiling fixture on top of a copy of the ceiling tile.
static func _lamp_fixture(ceil_img: Image, frame_ramp: int, glow_ramp: int) -> Image:
	var img := ceil_img.duplicate() as Image
	_bevel_box(img, 12, 12, 40, 40, Palette.ramp(frame_ramp, 2), Palette.ramp(frame_ramp, 10))
	_rect(img, 13, 13, 38, 38, Palette.ramp(frame_ramp, 3))
	for y in range(16, 48):
		for x in range(16, 48):
			var d := maxf(absf(x - 31.5), absf(y - 31.5)) / 16.0
			var c := Palette.ramp(glow_ramp, 15 - roundi(d * 4.0))
			if x == 31 or x == 32 or y == 31 or y == 32:
				c = Palette.ramp(glow_ramp, 9)
			_glow_px(img, x, y, c)
	return img


## Mining work-lamp: a bulb behind cage bars.
static func _cage_lamp(ceil_img: Image, frame_ramp: int, glow_ramp: int) -> Image:
	var img := ceil_img.duplicate() as Image
	_orb(img, 32, 32, 12, glow_ramp, true)
	for x in range(20, 45, 5):
		for y in range(19, 46):
			if Vector2(x - 32, y - 32).length() < 13.5:
				_px(img, x, y, Palette.ramp(frame_ramp, 4))
	return img


# =====================================================================
# drawing primitives (all coordinates wrap, so tiles stay seamless)
# =====================================================================

static func _img() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	return img


static func _rng(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


## Seamless 64x64 noise as raw bytes 0..255.
static func _noise(s: int, freq: float, ntype := FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
		octaves := 3) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = ntype
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = maxi(octaves, 1)
	var img := n.get_seamless_image(SIZE, SIZE)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


## Voronoi edge distance (small = near a cell border) — cracks, veins, facets.
static func _cell_edges(s: int, freq: float) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var img := n.get_seamless_image(SIZE, SIZE)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


## Voronoi cell value (flat per cell) — ice facets.
static func _cell_values(s: int, freq: float) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var img := n.get_seamless_image(SIZE, SIZE)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(posmod(x, SIZE), posmod(y, SIZE), Color(c.r, c.g, c.b, 1.0))


## Full-bright texel: alpha 0 tells sector.gdshader to skip lighting here.
static func _glow_px(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(posmod(x, SIZE), posmod(y, SIZE), Color(c.r, c.g, c.b, 0.0))


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			_px(img, px, py, c)


static func _glow_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			_glow_px(img, px, py, c)


static func _line_h(img: Image, y: int, c: Color) -> void:
	_rect(img, 0, y, SIZE, 1, c)


## Map noise bytes into a ramp between two shades.
static func _fill_noise(img: Image, n: PackedByteArray, r: int, lo: int, hi: int) -> void:
	for i in SIZE * SIZE:
		_px(img, i % SIZE, i / SIZE, Palette.ramp(r, lo + n[i] * (hi - lo + 1) / 256))


## Height-field lighting: shade = height, plus a top-left light from the slope.
static func _emboss(img: Image, h: PackedByteArray, r: int, lo: int, hi: int) -> void:
	for y in SIZE:
		for x in SIZE:
			var c: int = h[y * SIZE + x]
			var ul: int = h[posmod(y - 1, SIZE) * SIZE + posmod(x - 1, SIZE)]
			var v := float(c) / 255.0 + float(c - ul) / 64.0
			_px(img, x, y, Palette.ramp(r, clampi(lo + roundi(v * (hi - lo)), 0, 15)))


static func _bevel_box(img: Image, x: int, y: int, w: int, h: int, dark: Color,
		light: Color) -> void:
	_rect(img, x, y, w, 1, dark)
	_rect(img, x, y, 1, h, dark)
	_rect(img, x, y + h - 1, w, 1, light)
	_rect(img, x + w - 1, y, 1, h, light)


## Raised plate: grain-varied face, lit top/left edge, shadowed bottom/right.
static func _panel(img: Image, x: int, y: int, w: int, h: int, r: int, shade: int,
		grain: PackedByteArray) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			var n: int = grain[posmod(py, SIZE) * SIZE + posmod(px, SIZE)]
			var sh := shade + (1 if n > 190 else (-1 if n < 60 else 0))
			# a soft top-lit gradient down the plate
			if py - y > h * 0.66:
				sh -= 1
			_px(img, px, py, Palette.ramp(r, clampi(sh, 0, 15)))
	_rect(img, x, y, w, 1, Palette.ramp(r, clampi(shade + 3, 0, 15)))
	_rect(img, x, y, 1, h, Palette.ramp(r, clampi(shade + 2, 0, 15)))
	_rect(img, x, y + h - 1, w, 1, Palette.ramp(r, clampi(shade - 4, 0, 15)))
	_rect(img, x + w - 1, y, 1, h, Palette.ramp(r, clampi(shade - 3, 0, 15)))


static func _rivet(img: Image, x: int, y: int, r: int, shade: int) -> void:
	_px(img, x, y, Palette.ramp(r, clampi(shade + 5, 0, 15)))
	_px(img, x + 1, y, Palette.ramp(r, clampi(shade + 2, 0, 15)))
	_px(img, x, y + 1, Palette.ramp(r, clampi(shade + 2, 0, 15)))
	_px(img, x + 1, y + 1, Palette.ramp(r, clampi(shade - 3, 0, 15)))


## A row of short dark vent slots.
static func _slots(img: Image, x: int, y: int, w: int, r: int, shade: int) -> void:
	for sx in range(x, x + w, 6):
		_rect(img, sx, y, 4, 2, Palette.ramp(r, clampi(shade - 4, 0, 15)))
		_rect(img, sx, y + 2, 4, 1, Palette.ramp(r, clampi(shade + 2, 0, 15)))


## Horizontal louvres: each slat lit on top, shadowed below.
static func _grille(img: Image, x: int, y: int, w: int, h: int, r: int, shade: int) -> void:
	for py in range(y, y + h):
		var k := (py - y) % 4
		var sh := shade + 3 if k == 0 else (shade if k == 1 else (shade - 3 if k == 2 else 0))
		_rect(img, x, py, w, 1, Palette.ramp(r, clampi(sh, 0, 15)))


## Diagonal warning stripes.
static func _hazard(img: Image, x: int, y: int, w: int, h: int, ra: int, rb: int) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			var on := ((px + py) / 4) % 2 == 0
			_px(img, px, py, Palette.ramp(ra, 11) if on else Palette.ramp(rb, 2))
	_rect(img, x, y, w, 1, Palette.ramp(rb, 8))
	_rect(img, x, y + h - 1, w, 1, Palette.ramp(rb, 1))


## One cylinder running along x: shaded across its height, with a specular line.
static func _pipe_band(img: Image, y: int, h: int, r: int, shade: int) -> void:
	for py in range(y, y + h):
		var t := (py - y + 0.5) / h
		var lit := sin(t * PI)
		var sh := shade - 4 + roundi(lit * 6.0)
		if absf(t - 0.3) < 0.5 / h:
			sh = 14
		_rect(img, 0, py, SIZE, 1, Palette.ramp(r, clampi(sh, 0, 15)))


## Vertical I-beam support with rivets.
static func _girder(img: Image, x: int, r: int) -> void:
	_rect(img, x, 0, 16, 64, Palette.ramp(r, 6))
	_rect(img, x, 0, 2, 64, Palette.ramp(r, 10))
	_rect(img, x + 14, 0, 2, 64, Palette.ramp(r, 3))
	_rect(img, x + 6, 0, 4, 64, Palette.ramp(r, 4))
	for y in range(4, 64, 10):
		_rivet(img, x + 3, y, r, 7)
		_rivet(img, x + 11, y, r, 7)


## Round nodule / lamp / eye: radial ramp, optionally full-bright.
static func _orb(img: Image, cx: int, cy: int, rad: int, r: int, glow: bool) -> void:
	for y in range(cy - rad, cy + rad + 1):
		for x in range(cx - rad, cx + rad + 1):
			var d := Vector2(x - cx + 0.5 * signf(x - cx), y - cy).length() / float(rad)
			if d <= 1.0:
				var off := Vector2(x - cx + rad * 0.35, y - cy + rad * 0.35).length() / rad
				var sh := clampi(15 - roundi(off * 6.0) - roundi(d * 3.0), 3, 15)
				if glow:
					_glow_px(img, x, y, Palette.ramp(r, sh))
				else:
					_px(img, x, y, Palette.ramp(r, sh))


## Small glowing crystal cluster (diamond shapes).
static func _crystal(img: Image, cx: int, cy: int, size: int, r: int) -> void:
	for y in range(-size * 2, size * 2 + 1):
		var w := size - absi(y) / 2
		for x in range(-w, w + 1):
			var sh := 14 - absi(x) * 2 - (1 if y > 0 else 0)
			_glow_px(img, cx + x, cy + y, Palette.ramp(r, clampi(sh, 8, 15)))


## Right-angle circuit traces with node pads, full-bright.
static func _circuits(img: Image, rng: RandomNumberGenerator, r: int, count: int) -> void:
	for k in count:
		var x := rng.randi_range(0, 63)
		var y := rng.randi_range(0, 63)
		var dir := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		for seg in 3:
			var ln := rng.randi_range(5, 16)
			for i in ln:
				_glow_px(img, x, y, Palette.ramp(r, 11))
				x += dir.x
				y += dir.y
			dir = Vector2i(dir.y, dir.x) * (1 if rng.randf() < 0.5 else -1)
		_glow_rect(img, x - 1, y - 1, 3, 3, Palette.ramp(r, 14))


## An abstract glowing glyph: ring, cross-bar and spokes.
static func _rune(img: Image, cx: int, cy: int, r: int) -> void:
	for y in 64:
		for x in 64:
			var v := Vector2(x - cx + 0.5, y - cy + 0.5)
			var d := v.length()
			var a := atan2(v.y, v.x)
			var on := absf(d - 20.0) < 1.5
			on = on or (absf(d - 11.0) < 1.0 and fmod(a + TAU, TAU / 3.0) < TAU / 5.0)
			on = on or (absi(x - cx) < 1 and d < 20.0) or (absi(y - cy) < 1 and d < 8.0)
			if on:
				_glow_px(img, x, y, Palette.ramp(r, 13 if d < 12.0 else 11))
