class_name Palette
## The single source of color truth (PLAN.md C1). Every texture, sprite, and HUD
## element samples ONLY from these colors — that restraint is the "VGA feel."
## Families: grey metal, navy/blue, olive/brown rock, red, orange, cyan, green, void.

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

## Full palette array — the dither/quantize shader (Phase G) and any "snap to
## palette" helper iterate this.
const ALL: Array[Color] = [
	VOID_0, VOID_1,
	GREY_0, GREY_1, GREY_2, GREY_3, GREY_4, GREY_5, GREY_6, GREY_7,
	NAVY_0, NAVY_1, NAVY_2, BLUE_0, BLUE_1, BLUE_2,
	ROCK_0, ROCK_1, ROCK_2, ROCK_3, ROCK_4, ROCK_5, ROCK_6,
	RED_0, RED_1, RED_2, RED_3, RED_4,
	ORANGE_0, ORANGE_1, ORANGE_2, ORANGE_3,
	CYAN_0, CYAN_1, CYAN_2, CYAN_3,
	GREEN_0, GREEN_1, GREEN_2,
	WHITE,
]


static func nearest(color: Color) -> Color:
	var best := ALL[0]
	var best_d := INF
	for c in ALL:
		var d := (c.r - color.r) ** 2 + (c.g - color.g) ** 2 + (c.b - color.b) ** 2
		if d < best_d:
			best_d = d
			best = c
	return best
