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
## V2.0 plasma bomb: rare pickup, carried across levels within a run, hard cap.
const PLASMA_MAX := 3

# --- V2.2 L3: salvage economy — per-run weapon marks, persistent ship ranks.
# Declared ABOVE the stat vars: their setters clamp against max_shields()/
# missile_cap(), which read this state during member initialization.
signal salvage_changed(total: int)

# Mark tables indexed [weapon][mark 0..2] — NEUTRON / SCATTER / BOLT / MISSILE.
const MARK_DAMAGE := [[1.0, 1.35, 1.75], [1.0, 1.30, 1.60], [1.0, 1.35, 1.75], [1.0, 1.0, 1.0]]
const MARK_INTERVAL := [[1.0, 0.92, 0.85], [1.0, 1.0, 1.0], [1.0, 1.0, 1.0], [1.0, 1.0, 1.0]]
const MARK_SPEED := [[1.0, 1.0, 1.0], [1.0, 1.0, 1.0], [1.0, 1.15, 1.30], [1.0, 1.0, 1.0]]
const MARK_SPLASH := [[1.0, 1.0, 1.0], [1.0, 1.0, 1.0], [1.0, 1.0, 1.0], [1.0, 1.15, 1.25]]
const MARK_PELLETS := [[0, 0, 0], [0, 1, 2], [0, 0, 0], [0, 0, 0]]
const MARK_AMMO := [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 3, 5]]
const SHIP_CAPS := [100.0, 120.0, 140.0]      # shield/energy by rank
const HEAT_MULTS := [1.0, 0.88, 0.78]
const RACK_ADD := [0, 5, 10]

var salvage_run := 0        # this level's haul — banked at the tally, lost on death
var salvage_bank := 0       # persistent across runs (records.cfg)
var weapon_marks := [0, 0, 0, 0]   # per-run MK I..III (0..2)
var ship_ranks := {"shield": 0, "heat": 0, "energy": 0, "rack": 0, "magnet": 0, "hull": 0}

var shields := MAX_SHIELDS:
	set(value):
		shields = clampf(value, 0.0, max_shields())
		shields_changed.emit(shields)
		if shields <= 0.0 and not is_dead:
			is_dead = true
			player_died.emit()

var energy := MAX_ENERGY:
	set(value):
		energy = clampf(value, 0.0, max_energy())
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
		missiles = clampi(value, 0, missile_cap())
		missiles_changed.emit(missiles)

var plasma_bombs := 1:
	set(value):
		plasma_bombs = clampi(value, 0, PLASMA_MAX)

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
signal style_changed(grade: int)   # V2.2 L2c: fires on grade transitions only

const COMBO_WINDOW := 4.0   # seconds between kills before the streak drops
# V2.2 L2c: style grades ride the streak — names indexed by style_grade()
const STYLE_NAMES := ["", "RAD", "STELLAR", "COSMIC", "VOID LEGEND"]

var combo := 0
var combo_t := 0.0
var peak_style := 0         # V2.2 L2c: best grade this level, pays at the tally
var level_shots := 0        # projectiles fired this level (SCATTER counts 3)
var level_hits := 0         # projectiles that connected
var level_kills := 0
var level_props := 0        # K3: fuel cells destroyed this level
var level_props_total := 0  # K3: set at world build; all destroyed = secondary bonus
var level_secrets := 0        # V2.0: phantom-wall caches found this level
var level_secrets_total := 0  # set at world build
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


# --- V2.2 L3: salvage + upgrade accessors — every consumer routes through these ---

func salvage_total() -> int:
	return salvage_run + salvage_bank


## Spends from the level's unbanked haul first, then the bank. False if short.
func spend_salvage(cost: int) -> bool:
	if salvage_total() < cost:
		return false
	var from_run := mini(cost, salvage_run)
	salvage_run -= from_run
	salvage_bank -= cost - from_run
	salvage_changed.emit(salvage_total())
	return true


func bank_salvage() -> void:
	salvage_bank += salvage_run
	salvage_run = 0
	save_records()
	salvage_changed.emit(salvage_total())


func weapon_mult(widx: int, field: String) -> float:
	var mk: int = weapon_marks[widx]
	match field:
		"damage": return MARK_DAMAGE[widx][mk]
		"interval": return MARK_INTERVAL[widx][mk]
		"speed": return MARK_SPEED[widx][mk]
		"splash": return MARK_SPLASH[widx][mk]
	return 1.0


func weapon_add(widx: int, field: String) -> int:
	var mk: int = weapon_marks[widx]
	match field:
		"pellets": return MARK_PELLETS[widx][mk]
		"ammo": return MARK_AMMO[widx][mk]
	return 0


func max_shields() -> float:
	return SHIP_CAPS[ship_ranks.shield]


func max_energy() -> float:
	return SHIP_CAPS[ship_ranks.energy]


func heat_mult() -> float:
	return HEAT_MULTS[ship_ranks.heat]


func missile_cap() -> int:
	return MISSILES_PER_LEVEL + weapon_add(3, "ammo") + RACK_ADD[ship_ranks.rack]


func magnet_mult() -> float:
	return 1.5 if ship_ranks.magnet > 0 else 1.0


func hull_mult() -> float:   # wall-bounce damage
	return 0.7 if ship_ranks.hull > 0 else 1.0


## V2.2 L2c: streak length → style grade (0 none … 4 VOID LEGEND).
func style_grade() -> int:
	if combo >= 15:
		return 4
	if combo >= 10:
		return 3
	if combo >= 6:
		return 2
	if combo >= 3:
		return 1
	return 0


## Every scored kill routes through here so streaks multiply the base value.
func register_kill(base: int) -> void:
	var grade_was := style_grade()
	combo += 1
	combo_t = COMBO_WINDOW
	level_kills += 1
	score += base * combo_mult()
	combo_changed.emit(combo, combo_mult())
	var grade_now := style_grade()
	if grade_now != grade_was:
		peak_style = maxi(peak_style, grade_now)
		style_changed.emit(grade_now)


## Called from game._process only while PLAYING, so pausing never eats a streak.
func tick_combo(delta: float) -> void:
	if combo_t > 0.0:
		combo_t -= delta
		if combo_t <= 0.0 and combo > 0:
			var had_style := style_grade() > 0
			combo = 0
			combo_changed.emit(0, 1)
			if had_style:
				style_changed.emit(0)   # streak lapsed — clear the meter


func reset_level_stats() -> void:
	combo = 0
	combo_t = 0.0
	peak_style = 0
	salvage_run = 0   # V2.2 L3: unbanked haul rides on the level, not the run
	level_shots = 0
	level_hits = 0
	level_kills = 0
	level_props = 0   # level_props_total is owned by game._place_props at world build
	level_secrets = 0   # level_secrets_total is owned by game._place_secrets
	combo_changed.emit(0, 1)


func load_records() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://records.cfg") == OK:
		high_score = cfg.get_value("records", "high_score", 0)
		best_ranks = cfg.get_value("records", "ranks", [])
		unlocked_level = cfg.get_value("records", "unlocked", 0)
		gauntlet_best_dist = cfg.get_value("records", "gauntlet_dist", 0)
		gauntlet_best_score = cfg.get_value("records", "gauntlet_score", 0)
		salvage_bank = cfg.get_value("records", "salvage", 0)   # V2.2 L3
		var ranks_in: Dictionary = cfg.get_value("records", "ship_ranks", {})
		for k in ship_ranks:
			ship_ranks[k] = clampi(int(ranks_in.get(k, 0)), 0, SHIP_CAPS.size() - 1)


func save_records() -> void:
	# saved at every level end / game over — frequent enough that the browser's
	# async IndexedDB flush can't lose much to a sudden tab close
	var cfg := ConfigFile.new()
	cfg.set_value("records", "high_score", high_score)
	cfg.set_value("records", "ranks", best_ranks)
	cfg.set_value("records", "unlocked", unlocked_level)
	cfg.set_value("records", "gauntlet_dist", gauntlet_best_dist)
	cfg.set_value("records", "gauntlet_score", gauntlet_best_score)
	cfg.set_value("records", "salvage", salvage_bank)   # V2.2 L3
	cfg.set_value("records", "ship_ranks", ship_ranks.duplicate())
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
signal amber_toggled(on: bool)   # V2.0: amber "terminal" view mode

var master_volume := 0.8
var mouse_sens_mult := 1.0
var dither_enabled := true
var gamepad_enabled := false   # K6: opt-in, never default
var amber_mode := false        # amber-monochrome terminal look (via the dither shader)
var screen_shake := true       # V2.2 L1: camera kick/shake master switch (accessibility)
# --- M1/M2 beta-readiness accessibility + comfort settings ---
## M1.2: suppresses the plasma-bomb white-out and freezes strobing/flickering
## arena lights. The strobe runs at ~1.1 Hz and the flicker is a smooth energy
## modulation, so the bomb white-out is the real photosensitivity risk — this
## kills it outright rather than dimming it.
var reduce_flashing := false
## M2.1: damps the camera lean applied when turning and when dodge-rolling.
## Spatial disorientation is this genre's central comfort problem.
var reduce_roll := false
## M2.2: inverts the pitch axis for mouse look and the arrow keys alike.
var invert_y := false
## M2.2: vertical FOV in degrees; player.gd reads this every frame.
var view_fov := 78.0
## M4c: swaps the floating steering stick for a fixed D-pad. Off by default —
## the stick is what a first-time touch player meets (D9); this is the opt-in alt.
var touch_dpad_enabled := false
## M1.2: set once the photosensitivity warning has been acknowledged.
var seen_warning := false
# V2.2 L2b: combat-state flags game.gd maintains for the music intensity engine
var arena_locked := false
var boss_active := false


## Push current settings to the engine (audio bus + dither layer via signal) and save.
func apply_settings() -> void:
	var db := linear_to_db(master_volume) if master_volume > 0.001 else -80.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)
	dither_toggled.emit(dither_enabled)
	amber_toggled.emit(amber_mode)
	InputSetup.set_gamepad(gamepad_enabled)
	_save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		master_volume = cfg.get_value("settings", "volume", master_volume)
		mouse_sens_mult = cfg.get_value("settings", "sens", mouse_sens_mult)
		dither_enabled = cfg.get_value("settings", "dither", dither_enabled)
		gamepad_enabled = cfg.get_value("settings", "gamepad", gamepad_enabled)
		amber_mode = cfg.get_value("settings", "amber", amber_mode)
		screen_shake = cfg.get_value("settings", "shake", screen_shake)
		reduce_flashing = cfg.get_value("settings", "reduce_flash", reduce_flashing)
		reduce_roll = cfg.get_value("settings", "reduce_roll", reduce_roll)
		invert_y = cfg.get_value("settings", "invert_y", invert_y)
		view_fov = cfg.get_value("settings", "fov", view_fov)
		touch_dpad_enabled = cfg.get_value("settings", "dpad", touch_dpad_enabled)
		seen_warning = cfg.get_value("settings", "seen_warning", seen_warning)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "volume", master_volume)
	cfg.set_value("settings", "sens", mouse_sens_mult)
	cfg.set_value("settings", "dither", dither_enabled)
	cfg.set_value("settings", "gamepad", gamepad_enabled)
	cfg.set_value("settings", "amber", amber_mode)
	cfg.set_value("settings", "shake", screen_shake)
	cfg.set_value("settings", "reduce_flash", reduce_flashing)
	cfg.set_value("settings", "reduce_roll", reduce_roll)
	cfg.set_value("settings", "invert_y", invert_y)
	cfg.set_value("settings", "fov", view_fov)
	cfg.set_value("settings", "dpad", touch_dpad_enabled)
	cfg.set_value("settings", "seen_warning", seen_warning)
	cfg.save("user://settings.cfg")


func reset_level() -> void:
	## Back to the state the current level started with (death retry).
	shields = max_shields()   # V2.2 L3: full = the upgraded cap
	energy = max_energy()
	heat = 0.0
	score = level_start_score
	missiles = missile_cap()
	plasma_bombs = maxi(plasma_bombs, 1)   # a retry always has one bomb in the rack
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
	weapon_marks = [0, 0, 0, 0]   # V2.2 L3: marks are per-run; ranks persist
	reset_level()
	plasma_bombs = 1
