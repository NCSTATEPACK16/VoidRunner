class_name Palette
## The single source of color truth (PLAN.md C1). 3.0: a full 256-color "VGA"
## palette — 16 hue ramps x 16 shades, built the way mid-90s DOS art palettes
## were: every ramp runs near-black -> pure hue -> near-white, hue-shifted
## (shadows lean cool, highlights lean warm) so lighting stays colorful all the
## way down instead of greying out. The final frame is quantized to exactly
## these 256 entries (shaders/palette_dither.gdshader via PaletteLUT).
##
## The named constants below predate the 256-color palette; HUD and the headless
## fallback sprites still use them, and the quantizer snaps them to the nearest
## ramp entry anyway, so they stay valid colors to paint with.

const VOID_0 := Color("020308")
const VOID_1 := Color("05070c")
const GREY_0 := Color("0a0a0f")
const GREY_1 := Color("14161d")
const GREY_2 := Color("1f242e")
const GREY_3 := Color("2c3440")
const GREY_4 := Color("3c4654")
const GREY_5 := Color("57647a")
const GREY_6 := Color("7d8ba0")
const GREY_7 := Color("b0b4c0")
const NAVY_0 := Color("000040")
const NAVY_1 := Color("000080")
const NAVY_2 := Color("2030a0")
const BLUE_0 := Color("3858c8")
const BLUE_1 := Color("4a90d8")
const BLUE_2 := Color("7fb8ff")
const ROCK_0 := Color("1a140c")
const ROCK_1 := Color("2e2412")
const ROCK_2 := Color("4a3a1a")
const ROCK_3 := Color("665026")
const ROCK_4 := Color("8a6d34")
const ROCK_5 := Color("a8894a")
const ROCK_6 := Color("c4a866")
const RED_0 := Color("400808")
const RED_1 := Color("800000")
const RED_2 := Color("c01818")
const RED_3 := Color("ff3838")
const RED_4 := Color("ff7050")
const ORANGE_0 := Color("803c10")
const ORANGE_1 := Color("c06018")
const ORANGE_2 := Color("ff9a30")
const ORANGE_3 := Color("ffd34d")
const CYAN_0 := Color("0d3344")
const CYAN_1 := Color("1a7a6a")
const CYAN_2 := Color("28d8c0")
const CYAN_3 := Color("55ffee")
const GREEN_0 := Color("0a2a14")
const GREEN_1 := Color("2a7a3a")
const GREEN_2 := Color("37ff9a")
const WHITE := Color("e8ecf4")

# --- 3.0: the 256-color ramp palette ---
const RAMP_LEN := 16
## Ramp ids (index into RAMP_STOPS). Paint with Palette.ramp(Palette.STEEL, 9).
enum { STEEL, GREY, BRASS, BLUE, CYAN, GREEN, LIME, GOLD, ORANGE, RED, MAGENTA,
	VIOLET, FLESH, RUST, OLIVE, FIRE }
## Four key stops per ramp, at shades 0 / 5 / 10 / 15; shades between are linear.
## Shade 0 is near-black but keeps its hue, so fogged and unlit surfaces still
## read as the right material. GREY starts at pure black (the fog color) and ends
## at pure white.
const RAMP_STOPS := [
	["07080d", "3a4458", "8290ad", "e6ecf8"],   # STEEL — cool blue-grey metal
	["000000", "4a4a4a", "9c9c9c", "ffffff"],   # GREY — neutral, black to white
	["0e0904", "5a3e1c", "b58a45", "fff0b8"],   # BRASS — warm metal / bronze
	["03041a", "1c2c8c", "4c7ce8", "c8e0ff"],   # BLUE — navy to sky
	["021018", "0b5a70", "22c4d8", "c8fcff"],   # CYAN
	["021208", "0e6a34", "2ed070", "d0ffe0"],   # GREEN — emerald
	["0a1002", "3e6a0a", "9ad62a", "f4ffc0"],   # LIME
	["140c00", "7a5a06", "eac21a", "fffcd0"],   # GOLD
	["160600", "883006", "f07818", "ffe0b0"],   # ORANGE
	["160204", "800c10", "e8302a", "ffc8b8"],   # RED
	["14020e", "7a0c5a", "e03cb0", "ffd0f4"],   # MAGENTA
	["08031a", "3c1886", "8a5ae8", "e8d8ff"],   # VIOLET
	["120608", "6a2e30", "d08070", "ffe4d4"],   # FLESH — organic hive tissue
	["0c0604", "4c2a16", "9a6038", "eccaa0"],   # RUST — rock and earth
	["0a0a04", "3e4220", "8a9050", "e8ecc0"],   # OLIVE — moss / khaki
	["100000", "a01000", "ff9010", "fffff0"],   # FIRE — ember to white-hot
]

## Full palette array — 256 entries, ramp-major (index = ramp * 16 + shade).
## The GPU lookup table (PaletteLUT) and nearest() both iterate this.
static var ALL: Array[Color] = _build_all()


static func _build_all() -> Array[Color]:
	var out: Array[Color] = []
	for r in RAMP_STOPS.size():
		for sh in RAMP_LEN:
			out.append(_ramp_color(r, sh))
	return out


static func _ramp_color(r: int, shade: int) -> Color:
	var stops: Array = RAMP_STOPS[r]
	var sh := clampi(shade, 0, RAMP_LEN - 1)
	var seg := mini(sh / 5, 2)
	var t := (sh - seg * 5) / 5.0
	return Color(stops[seg]).lerp(Color(stops[seg + 1]), t)


## One palette entry: ramp id (STEEL, RED, ...) and shade 0 (dark) .. 15 (bright).
static func ramp(r: int, shade: int) -> Color:
	return ALL[clampi(r, 0, RAMP_STOPS.size() - 1) * RAMP_LEN + clampi(shade, 0, RAMP_LEN - 1)]


## Shade picked by a 0..1 brightness value — the texture painters' main entry.
static func ramp_f(r: int, t: float) -> Color:
	return ramp(r, roundi(clampf(t, 0.0, 1.0) * (RAMP_LEN - 1)))


static func nearest(color: Color) -> Color:
	var best := ALL[0]
	var best_d := INF
	for c in ALL:
		var d := (c.r - color.r) ** 2 + (c.g - color.g) ** 2 + (c.b - color.b) ** 2
		if d < best_d:
			best_d = d
			best = c
	return best
