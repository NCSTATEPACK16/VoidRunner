extends Node
## GameState autoload — the single home for shared mutable run state.
## Mirrors the role state.js played in the v2.2 web build: player stats, campaign
## position, weapon selection, and run flags. Tuning values live in the
## Weapon/Level resources (resources/), not here.

signal shields_changed(value: float)
signal energy_changed(value: float)
signal heat_changed(value: float)
signal score_changed(value: int)
signal level_changed(index: int)
signal weapon_changed(index: int)
signal overheat_started
signal overheat_ended
signal player_died
signal level_completed

const MAX_SHIELDS := 100.0
const MAX_ENERGY := 100.0
const MAX_HEAT := 100.0

var shields := MAX_SHIELDS:
	set(value):
		shields = clampf(value, 0.0, MAX_SHIELDS)
		shields_changed.emit(shields)
		if shields <= 0.0 and not is_dead:
			is_dead = true
			player_died.emit()

var energy := MAX_ENERGY:
	set(value):
		energy = clampf(value, 0.0, MAX_ENERGY)
		energy_changed.emit(energy)

var heat := 0.0:
	set(value):
		heat = clampf(value, 0.0, MAX_HEAT)
		heat_changed.emit(heat)

var score := 0:
	set(value):
		score = maxi(value, 0)
		score_changed.emit(score)

## Score at the start of the current level — death retries the level at this score.
var level_start_score := 0

## 0-based index into the 5-level campaign.
var level_index := 0:
	set(value):
		level_index = value
		level_changed.emit(level_index)

var weapon_index := 0:
	set(value):
		weapon_index = value
		weapon_changed.emit(weapon_index)

var is_dead := false
var is_paused := false
var is_overheated := false
## Kill tracking for locked arenas (Phase E): -1 target means no lock active.
var arena_kills := 0
var arena_kill_target := -1


func reset_level() -> void:
	## Back to the state the current level started with (death retry).
	shields = MAX_SHIELDS
	energy = MAX_ENERGY
	heat = 0.0
	score = level_start_score
	weapon_index = 0
	is_dead = false
	is_overheated = false
	arena_kills = 0
	arena_kill_target = -1


func reset_run() -> void:
	## Fresh campaign.
	level_index = 0
	level_start_score = 0
	reset_level()
