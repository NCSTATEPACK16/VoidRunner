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

## 0-based index into the campaign (level count = however many level_N.tres exist).
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


# --- Phase J: kill-streak combo, per-level stats, persistent records ---
signal combo_changed(count: int, mult: int)

const COMBO_WINDOW := 4.0   # seconds between kills before the streak drops

var combo := 0
var combo_t := 0.0
var level_shots := 0        # projectiles fired this level (SCATTER counts 3)
var level_hits := 0         # projectiles that connected
var level_kills := 0
var level_props := 0        # K3: fuel cells destroyed this level
var level_props_total := 0  # K3: set at world build; all destroyed = secondary bonus
var high_score := 0
var best_ranks: Array = []  # best rank letter per level index ("" = unranked)
var unlocked_level := 0     # highest 0-based level reached — feeds sector select

# --- K5 Void Gauntlet: endless survival mode, records separate from the campaign ---
var gauntlet_mode := false
var gauntlet_best_dist := 0
var gauntlet_best_score := 0


func combo_mult() -> int:
	if combo >= 12:
		return 4
	if combo >= 8:
		return 3
	if combo >= 4:
		return 2
	return 1


## Every scored kill routes through here so streaks multiply the base value.
func register_kill(base: int) -> void:
	combo += 1
	combo_t = COMBO_WINDOW
	level_kills += 1
	score += base * combo_mult()
	combo_changed.emit(combo, combo_mult())


## Called from game._process only while PLAYING, so pausing never eats a streak.
func tick_combo(delta: float) -> void:
	if combo_t > 0.0:
		combo_t -= delta
		if combo_t <= 0.0 and combo > 0:
			combo = 0
			combo_changed.emit(0, 1)


func reset_level_stats() -> void:
	combo = 0
	combo_t = 0.0
	level_shots = 0
	level_hits = 0
	level_kills = 0
	level_props = 0   # level_props_total is owned by game._place_props at world build
	combo_changed.emit(0, 1)


func load_records() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://records.cfg") == OK:
		high_score = cfg.get_value("records", "high_score", 0)
		best_ranks = cfg.get_value("records", "ranks", [])
		unlocked_level = cfg.get_value("records", "unlocked", 0)
		gauntlet_best_dist = cfg.get_value("records", "gauntlet_dist", 0)
		gauntlet_best_score = cfg.get_value("records", "gauntlet_score", 0)


func save_records() -> void:
	# saved at every level end / game over — frequent enough that the browser's
	# async IndexedDB flush can't lose much to a sudden tab close
	var cfg := ConfigFile.new()
	cfg.set_value("records", "high_score", high_score)
	cfg.set_value("records", "ranks", best_ranks)
	cfg.set_value("records", "unlocked", unlocked_level)
	cfg.set_value("records", "gauntlet_dist", gauntlet_best_dist)
	cfg.set_value("records", "gauntlet_score", gauntlet_best_score)
	cfg.save("user://records.cfg")


const RANK_ORDER := {"": -1, "C": 0, "B": 1, "A": 2, "S": 3}


## Fold the current score (and optionally this level's rank) into the records.
## Returns true when the score set a new high.
func record_progress(rank := "") -> bool:
	var new_record := score > high_score
	if new_record:
		high_score = score
	if rank != "":
		while best_ranks.size() <= level_index:
			best_ranks.append("")
		if RANK_ORDER.get(rank, -1) > RANK_ORDER.get(str(best_ranks[level_index]), -1):
			best_ranks[level_index] = rank
	save_records()
	return new_record


## K5: fold a finished gauntlet run into the records (kept separate from the
## campaign high score — an endless run would swamp it). Returns true on a new best.
func record_gauntlet(dist: int) -> bool:
	var new_best := dist > gauntlet_best_dist or score > gauntlet_best_score
	gauntlet_best_dist = maxi(gauntlet_best_dist, dist)
	gauntlet_best_score = maxi(gauntlet_best_score, score)
	save_records()
	return new_best


# --- Phase H: player settings, persisted to user://settings.cfg ---
signal dither_toggled(on: bool)

var master_volume := 0.8
var mouse_sens_mult := 1.0
var dither_enabled := true
var gamepad_enabled := false   # K6: opt-in, never default


## Push current settings to the engine (audio bus + dither layer via signal) and save.
func apply_settings() -> void:
	var db := linear_to_db(master_volume) if master_volume > 0.001 else -80.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)
	dither_toggled.emit(dither_enabled)
	InputSetup.set_gamepad(gamepad_enabled)
	_save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		master_volume = cfg.get_value("settings", "volume", master_volume)
		mouse_sens_mult = cfg.get_value("settings", "sens", mouse_sens_mult)
		dither_enabled = cfg.get_value("settings", "dither", dither_enabled)
		gamepad_enabled = cfg.get_value("settings", "gamepad", gamepad_enabled)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "volume", master_volume)
	cfg.set_value("settings", "sens", mouse_sens_mult)
	cfg.set_value("settings", "dither", dither_enabled)
	cfg.set_value("settings", "gamepad", gamepad_enabled)
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
	reset_level_stats()


func reset_run() -> void:
	## Fresh campaign.
	level_index = 0
	level_start_score = 0
	reset_level()
