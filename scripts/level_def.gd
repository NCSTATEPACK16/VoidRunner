class_name LevelDef
extends Resource
## One campaign level's tuning (PLAN.md E1). Values ship in resources/levels/*.tres —
## ranges taken from PROJECT.md §5's LEVELS table, plus the Phase E additions
## (zone theme, mission briefing).

@export var display_name := "L1 · STARLIGHT APPROACH"
@export_multiline var briefing := ""
@export var objective := "REACH THE EXIT GATE"
@export var rings := 110
@export var spawn_tunnel := 0.06
@export var spawn_arena := 0.30
@export var enemy_hp := 2
@export var enemy_speed := 6.0
@export var enemy_fire := 2.8   # seconds between enemy shots (scaled ±)
@export var theme_id := "tech"
@export var level_seed := 101   # deterministic layout per level
## Phase I3: weighted spawn pool — both tunnel and arena spawns pick a type from
## here (repeat an id to weight it). L1 is drone-only; later levels mix in variants.
@export var enemy_types := PackedStringArray(["drone"])

# --- Phase J: boss levels + score ranking ---
## "tunnel" = the classic winding run; "boss" = short entry tunnel into one large
## straight room holding a single boss whose death activates the exit portal.
@export var kind := "tunnel"
@export var boss_name := ""
@export var boss_hp := 0              # absolute HP — bosses skip the mul/add formula
@export var boss_size := 16.0         # billboard world-size (drones are 4.2)
@export var boss_tint := Color(1, 1, 1)
## Par time in seconds for the end-of-level rank; 0 derives it from ring count.
@export var par_time := 0.0
