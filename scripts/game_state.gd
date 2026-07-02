extends Node
## GameState autoload — the single home for shared mutable run state.
## Mirrors the role state.js played in the v2.2 web build: player stats, campaign
## position, weapon selection, and run flags. Tuning values live in the
## Weapon/Level resources (resources/), not here.

signal shields_changed(value: float)
signal energy_changed(value: float)
signal heat_changed(value: float)
signal score_changed(value: int)
signal missiles_changed(value: int)
signal level_changed(index: int)
signal weapon_changed(index: int)
signal overheat_started
signal overheat_ended
signal player_died
signal level_completed

const MAX_SHIELDS := 100.0
const MAX_ENERGY := 100.0
const MAX_HEAT := 100.0
## Phase I2: MISSILE is ammo-class — this many per level, no regen.
const MISSILES_PER_LEVEL := 20

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

var missiles := MISSILES_PER_LEVEL:
	set(value):
		missiles = clampi(value, 0, MISSILES_PER_LEVEL)
		missiles_changed.emit(missiles)

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


# --- Phase H: player settings, persisted to user://settings.cfg ---
signal dither_toggled(on: bool)

var master_volume := 0.8
var mouse_sens_mult := 1.0
var dither_enabled := true


## Push current settings to the engine (audio bus + dither layer via signal) and save.
func apply_settings() -> void:
	var db := linear_to_db(master_volume) if master_volume > 0.001 else -80.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)
	dither_toggled.emit(dither_enabled)
	_save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		master_volume = cfg.get_value("settings", "volume", master_volume)
		mouse_sens_mult = cfg.get_value("settings", "sens", mouse_sens_mult)
		dither_enabled = cfg.get_value("settings", "dither", dither_enabled)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "volume", master_volume)
	cfg.set_value("settings", "sens", mouse_sens_mult)
	cfg.set_value("settings", "dither", dither_enabled)
	cfg.save("user://settings.cfg")


func reset_level() -> void:
	## Back to the state the current level started with (death retry).
	shields = MAX_SHIELDS
	energy = MAX_ENERGY
	heat = 0.0
	score = level_start_score
	missiles = MISSILES_PER_LEVEL
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
