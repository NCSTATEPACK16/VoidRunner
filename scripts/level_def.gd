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
