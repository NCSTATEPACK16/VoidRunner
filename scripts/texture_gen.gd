class_name TextureGen
## Procedural wall/floor/ceiling textures (PLAN.md C2) — the Godot port of the web
## build's makeTexture/speckle canvas painters. Everything samples Palette colors only.
## A zone "theme" is a Dictionary of palette colors: base, dark, mid, light, accent, accent2.

const SIZE := 64

## Zone themes (PLAN.md E6): each campaign level picks one so the sectors read differently.
static var THEMES := {
	"tech": {
		"base": Palette.GREY_2, "dark": Palette.GREY_0, "mid": Palette.GREY_3,
		"light": Palette.GREY_5, "accent": Palette.CYAN_2, "accent2": Palette.ORANGE_2,
	},
	"navy": {
		"base": Palette.NAVY_1, "dark": Palette.NAVY_0, "mid": Palette.NAVY_2,
		"light": Palette.BLUE_1, "accent": Palette.CYAN_3, "accent2": Palette.RED_3,
	},
	"rock": {
		"base": Palette.ROCK_1, "dark": Palette.ROCK_0, "mid": Palette.ROCK_2,
		"light": Palette.ROCK_4, "accent": Palette.ORANGE_2, "accent2": Palette.CYAN_2,
	},
	"hive": {
		"base": Palette.RED_0, "dark": Palette.VOID_1, "mid": Palette.GREY_2,
		"light": Palette.RED_1, "accent": Palette.RED_3, "accent2": Palette.ORANGE_2,
	},
	"void": {
		"base": Palette.GREY_1, "dark": Palette.VOID_0, "mid": Palette.NAVY_1,
		"light": Palette.GREY_4, "accent": Palette.CYAN_3, "accent2": Palette.RED_3,
	},
}


static func theme_set(theme_id: String, seed_base: int = 1) -> Dictionary:
	var t: Dictionary = THEMES[theme_id]
	return {
		"wall": material(wall(t, seed_base)),
		"floor": material(floor_tex(t, seed_base + 1)),
		"ceil": material(ceil_tex(t, seed_base + 2)),
	}


static func material(tex: ImageTexture) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_repeat = true
	return m


static func wall(t: Dictionary, tex_seed: int) -> ImageTexture:
	var img := _base(t.base)
	var rng := _rng(tex_seed)
	_speckle(img, rng, 500, t.dark)
	_speckle(img, rng, 260, t.light)
	# panel grid every 16 px
	for i in range(0, SIZE, 16):
		_vline(img, i, t.dark)
		_hline(img, i, t.dark)
	# rivets
	for x in range(0, SIZE, 16):
		for y in range(0, SIZE, 16):
			_rect(img, x + 2, y + 2, 2, 2, t.mid)
			_rect(img, x + 12, y + 12, 2, 2, t.mid)
	# accent conduit line
	_rect(img, 0, 30, SIZE, 2, t.accent)
	# hazard dashes
	for hx in range(0, SIZE, 8):
		_rect(img, hx, 46, 4, 3, t.accent2)
	return ImageTexture.create_from_image(img)


static func floor_tex(t: Dictionary, tex_seed: int) -> ImageTexture:
	var img := _base(t.dark)
	var rng := _rng(tex_seed)
	_speckle(img, rng, 420, Palette.VOID_0)
	for i in range(4, SIZE, 8):
		_hline(img, i, t.mid)
	for j in range(4, SIZE, 16):
		_vline(img, j, t.base)
	_speckle(img, rng, 120, t.light)
	return ImageTexture.create_from_image(img)


static func ceil_tex(t: Dictionary, tex_seed: int) -> ImageTexture:
	var img := _base(t.dark)
	var rng := _rng(tex_seed)
	for i in range(0, SIZE, 32):
		_vline(img, i, Palette.VOID_0)
		_hline(img, i, Palette.VOID_0)
	_speckle(img, rng, 300, t.mid)
	# two recessed light fixtures
	_rect(img, 12, 14, 8, 4, t.accent)
	_rect(img, 44, 46, 8, 4, t.light)
	return ImageTexture.create_from_image(img)


# ---------- pixel helpers ----------

static func _rng(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


static func _base(color: Color) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	img.fill(color)
	return img


static func _speckle(img: Image, rng: RandomNumberGenerator, count: int, color: Color) -> void:
	for i in count:
		img.set_pixel(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1), color)


static func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for px in range(maxi(0, x), mini(SIZE, x + w)):
		for py in range(maxi(0, y), mini(SIZE, y + h)):
			img.set_pixel(px, py, color)


static func _vline(img: Image, x: int, color: Color) -> void:
	if x >= SIZE:
		return
	for y in SIZE:
		img.set_pixel(x, y, color)


static func _hline(img: Image, y: int, color: Color) -> void:
	if y >= SIZE:
		return
	for x in SIZE:
		img.set_pixel(x, y, color)
