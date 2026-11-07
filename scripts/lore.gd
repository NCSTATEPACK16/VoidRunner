class_name Lore
## V2.2 story pass: every scrap of narrative text lives here — the briefing screen's
## story paragraph and the web loading overlay's rotating transmission lines — so the
## campaign arc reads as one voice and copy edits touch one file.
##
## The arc: the Rift tears open beside Starlight Station; a machine swarm — the Hive —
## pours through; the last Void Runner pilot fights inward past three signature-class
## guardians (sectors 3/6/9) and shuts the Rift from the inside.
##
## Sizing contract with overlays.gd: a story string must wrap to <= 3 lines in the
## briefing's 260-design-px band at font 8 (~125 chars). Load lines render in the HTML
## shell at small size — keep each <= ~44 chars. Index -1 = the Void Gauntlet; any
## other out-of-range index falls back to the sector-1 entry rather than "".
##
## v4d episodes: three of three sectors each (E1 L1-3, E2 L4-6, E3 L7-9). Sizing contract
## for the presentation panels: a subtitle is one line, <= 40 chars (<= 240 px at font 8's
## 6 px advance, inside the 320 px screen); an ending is <= 200 chars so it wraps to <= 5
## lines in a ~260 px band (~43 chars a line). sector_label() builds "E2 · L4 · REACTOR
## MAZE" (the · is in PixelFont's glyph table) and is <= ~34 chars for the current names.

const _GAUNTLET_STORY := "No map. No exit. The Void remembers every run and answers " \
	+ "with a longer tunnel. Fly until the dark blinks first."

const _STORIES: Array[String] = [
	"The Rift tore open at 0400. Starlight's outer ring went dark in minutes. You are the last Void Runner on the board.",
	"The main artery feeds every deck, and the swarm is using it as a highway. Take it back before the station starves.",
	"Something big is parked in the old docking bay — a Sentinel-class guardian, wearing our own hull plate as armor.",
	"The reactor galleries were carved straight into the rock. Tight turns, deep shadow, and the Hive nesting in the heat.",
	"This is where the swarm nests. The trench walls run red, and intel marks hidden supply spurs off the main line.",
	"The heart of the nest. Every drone you have scrapped was born here — and the Brood Mother is not happy to see you.",
	"Coolant conduits on the dark side, frozen over for years. The ice tricks your radar. The Hive does not feel the cold.",
	"The longest run of the campaign, straight into the anomaly. Whatever opened the Rift is waiting on the other side.",
	"The Maw holds the Rift open from the inside. Shut it, and every door the Hive walked through slams at once.",
]

const _GAUNTLET_LINES: Array[String] = [
	"NO MAP. NO EXIT.",
	"THE VOID REMEMBERS YOUR RUNS",
	"IT ANSWERS WITH A LONGER TUNNEL",
	"FLY UNTIL THE DARK BLINKS FIRST",
]

const _LOAD_LINES: Array = [
	[
		"OUTER RING: NO FRIENDLY BEACONS",
		"DRONE PATROLS ON THE APPROACH",
		"BULKHEADS SEALED SINCE THE BREACH",
		"MAKE EVERY SHOT COUNT, RUNNER",
	],
	[
		"CONVOY RACKS READ HALF-EMPTY",
		"THE HIVE IS STRIPPING US FOR PARTS",
		"FUEL CELLS PRIMED ALONG THE ROUTE",
		"SUPPLY ARTERY DEAD AHEAD",
	],
	[
		"HEAVY SIGNATURE IN THE DOCK",
		"IT IS WEARING OUR HULL PLATE",
		"DOCK CREWS EVACUATED — MOSTLY",
		"SENTINEL CONTACT IMMINENT",
	],
	[
		"REACTOR COOLANT RUNNING HOT",
		"HEAT SHIMMER ON ALL SCOPES",
		"NESTS IN THE COOLANT RUNS",
		"MIND YOUR HEAT GAUGE, RUNNER",
	],
	[
		"TRENCH SCAN: MOVEMENT EVERYWHERE",
		"SUPPLY SPURS MARKED ON INTEL",
		"THE SWARM DIGS WHERE LIGHT DIES",
		"WATCH THE WALLS FOR HATCHES",
	],
	[
		"BIO-SIGNAL OFF THE CHART",
		"EVERY DRONE WAS BORN SOMEWHERE",
		"THIS IS THAT SOMEWHERE",
		"END THE HEARTBEAT",
	],
	[
		"CONDUIT TEMP: FORTY BELOW",
		"ICE ON THE INSTRUMENTS",
		"THE HIVE DOES NOT FEEL THE COLD",
		"FLY THE FROZEN DARK",
	],
	[
		"RIFT PROXIMITY: INSTRUMENTS HUMMING",
		"GATE CORRIDOR HEAVILY HELD",
		"TURRETS ON THE APPROACH WALLS",
		"ALMOST THERE, RUNNER",
	],
	[
		"THE MAW HOLDS THE RIFT OPEN",
		"SHUT IT FROM THE INSIDE",
		"ONE PILOT. ONE RUN.",
		"FINISH IT",
	],
]


const EPISODE_COUNT := 3

const _EPISODES: Array[Dictionary] = [
	{
		"id": "E1", "name": "THE OUTER LANES", "first": 0, "last": 2,
		"subtitle": "Starlight Station needs a hero",
		"ending": "The Sentinel powers down and the station's lights flicker back on. "
			+ "The outer lanes are safe again. But the swarm is still out there, "
			+ "deeper in the dark.",
	},
	{
		"id": "E2", "name": "THE HIVE", "first": 3, "last": 5,
		"subtitle": "Follow the swarm home",
		"ending": "The Brood Mother goes quiet and the whole nest calms down. "
			+ "The Hive is not buzzing anymore. Just one thing is left: "
			+ "the glowing Rift.",
	},
	{
		"id": "E3", "name": "THE RIFT", "first": 6, "last": 8,
		"subtitle": "One last run into the light",
		"ending": "The Maw closes and the Rift folds shut like a book. "
			+ "Stars shine over Starlight Station again. "
			+ "Thank you, Runner. You brought everyone home.",
	},
]


static func episode_of(level_index: int) -> int:
	for e in EPISODE_COUNT:
		if level_index >= int(_EPISODES[e]["first"]) and level_index <= int(_EPISODES[e]["last"]):
			return e
	return -1


static func _ep(e: int) -> Dictionary:
	return _EPISODES[clampi(e, 0, EPISODE_COUNT - 1)]


static func episode_id(e: int) -> String:
	return _ep(e)["id"]


static func episode_name(e: int) -> String:
	return _ep(e)["name"]


static func episode_subtitle(e: int) -> String:
	return _ep(e)["subtitle"]


static func episode_ending(e: int) -> String:
	return _ep(e)["ending"]


static func is_episode_start(level_index: int) -> bool:
	var e: int = episode_of(level_index)
	return e >= 0 and level_index == int(_EPISODES[e]["first"])


static func is_episode_end(level_index: int) -> bool:
	var e: int = episode_of(level_index)
	return e >= 0 and level_index == int(_EPISODES[e]["last"])


## "E2 · L4 · REACTOR MAZE"; the gauntlet (and anything out of range) keeps its plain name.
static func sector_label(level_index: int, level_name: String) -> String:
	var e: int = episode_of(level_index)
	if e < 0:
		return level_name
	return "%s · L%d · %s" % [_EPISODES[e]["id"], level_index + 1, level_name.to_upper()]


static func story(level_index: int) -> String:
	if level_index == -1:
		return _GAUNTLET_STORY
	if level_index < 0 or level_index >= _STORIES.size():
		return _STORIES[0]
	return _STORIES[level_index]


static func load_lines(level_index: int) -> PackedStringArray:
	if level_index == -1:
		return PackedStringArray(_GAUNTLET_LINES)
	if level_index < 0 or level_index >= _LOAD_LINES.size():
		return PackedStringArray(_LOAD_LINES[0])
	return PackedStringArray(_LOAD_LINES[level_index])
