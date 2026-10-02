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


# --- Re-audit Step 3 (M5b): difficulty presets + assists. Presets change how hard
# the void pushes (enemy clocks, shot speed, damage taken, warning time, pickup
# value) and never enemy count, HP, layout or seed, so scores stay comparable.
# Every value is read where it's used, so a change from pause lands at once.
const DIFFICULTY_NAMES := ["RECRUIT", "RUNNER", "VOIDBORNE"]
const DIFFICULTY_BLURBS := [
	"Softer hits and slower fire. Learn the void.",
	"The intended ride.",
	"Faster fire, harder hits. The era's way.",
]
const DIFF_TEMPO := [0.74, 1.0, 1.25]       # enemy fire/pattern clocks run this fast
const DIFF_SHOT_SPEED := [0.8, 1.0, 1.15]
const DIFF_DAMAGE := [0.6, 1.0, 1.3]
const DIFF_WARN := [1.4, 1.0, 0.8]          # stinger wind-up, mine fuse
const DIFF_PICKUP := [1.5, 1.0, 0.75]       # shield + energy pickups
## Assists (Celeste-style, independent of the preset): steps of damage taken and
## game speed. Both are plain accessibility aids and never touch scoring.
const ASSIST_DAMAGE := [1.0, 0.75, 0.5]
const ASSIST_SPEED := [1.0, 0.85, 0.7]

var difficulty := 1        # RUNNER: the tuning every level was built around
var assist_damage := 0
var assist_speed := 0
## What Engine.time_scale returns to after a hit-stop or the automap. game.gd sets it
## to flight_time_scale() while flying and back to 1.0 everywhere else.
var time_scale_base := 1.0


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func enemy_tempo() -> float:
	return DIFF_TEMPO[difficulty]


func enemy_shot_speed() -> float:
	return DIFF_SHOT_SPEED[difficulty]


func warn_mult() -> float:
	return DIFF_WARN[difficulty]


func pickup_mult() -> float:
	return DIFF_PICKUP[difficulty]


func damage_taken_mult() -> float:
	return DIFF_DAMAGE[difficulty] * ASSIST_DAMAGE[assist_damage]


func flight_time_scale() -> float:
	return ASSIST_SPEED[assist_speed]


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


# --- 3.0 phase 5: timed power-ups. Each pickup starts (or refills) its own
# clock; game._process ticks them only while PLAYING, like the combo window.
signal power_changed(kind: String, t: float)   # t = seconds left (0 = ended)

const POWER_TIME := {"overdrive": 10.0, "phase": 8.0, "powercore": 12.0}
var power_t := {"overdrive": 0.0, "phase": 0.0, "powercore": 0.0}


func power_on(kind: String) -> bool:
	return power_t.get(kind, 0.0) > 0.0


func grant_power(kind: String) -> void:
	power_t[kind] = POWER_TIME[kind]
	power_changed.emit(kind, power_t[kind])


func tick_powers(delta: float) -> void:
	for kind in power_t:
		if power_t[kind] > 0.0:
			power_t[kind] = maxf(0.0, power_t[kind] - delta)
			if power_t[kind] <= 0.0:
				power_changed.emit(kind, 0.0)


func clear_powers() -> void:
	for kind in power_t:
		if power_t[kind] > 0.0:
			power_t[kind] = 0.0
			power_changed.emit(kind, 0.0)


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
	clear_powers()   # 3.0: power-ups never carry into the next level


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


# --- Re-audit Step 4 (M5c): checkpoints. One small snapshot of the run, saved at
# sector start and at each cleared bulkhead (RECRUIT and RUNNER), to user:// and, on
# web, to localStorage too: Godot copies user:// into IndexedDB asynchronously, so a
# tab closed just after a save could lose it, while localStorage writes are
# synchronous. Loading takes the newer copy, and anything malformed is ignored.
const CHECKPOINT_PATH := "user://checkpoint.cfg"
const CHECKPOINT_KEY := "vr_checkpoint"
const CHECKPOINT_VERSION := 1
const CHECKPOINT_FIELDS := ["v", "level_index", "level_start_score", "score", "weapon_marks",
	"plasma_bombs", "missiles", "weapon_index", "shields", "energy", "salvage_run", "stats",
	"elapsed", "ring", "cleared_arenas", "saved_at"]
var _asked_persist := false


## Stamps and writes a snapshot; returns the stamped copy (what a load gives back).
func save_checkpoint(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	d["v"] = CHECKPOINT_VERSION
	d["saved_at"] = Time.get_unix_time_from_system()
	d["build"] = BuildInfo.ID
	var cfg := ConfigFile.new()
	cfg.set_value("checkpoint", "data", d)
	cfg.save(CHECKPOINT_PATH)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem(%s, %s); } catch (e) {}" % [
			JSON.stringify(CHECKPOINT_KEY), JSON.stringify(JSON.stringify(d))], true)
		if not _asked_persist:
			# ask the browser to exempt this site's storage from eviction (Safari
			# otherwise clears it after 7 days of use without a visit)
			_asked_persist = true
			JavaScriptBridge.eval("try { if (navigator.storage && navigator.storage.persist)"
				+ " { navigator.storage.persist(); } } catch (e) {}", true)
	return d


## The newest valid checkpoint for a campaign of `level_count` sectors, or {}.
func load_checkpoint(level_count: int) -> Dictionary:
	var from_file := {}
	var cfg := ConfigFile.new()
	if cfg.load(CHECKPOINT_PATH) == OK:
		var v: Variant = cfg.get_value("checkpoint", "data", {})
		if v is Dictionary:
			from_file = v
	var from_web := {}
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("(function () { try { return "
			+ "localStorage.getItem(%s) || ''; } catch (e) { return ''; } })()"
			% JSON.stringify(CHECKPOINT_KEY), true)
		if raw is String and raw != "":
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				from_web = parsed
	return pick_checkpoint(normalize_checkpoint(from_file, level_count),
		normalize_checkpoint(from_web, level_count))


func clear_checkpoint() -> void:
	if FileAccess.file_exists(CHECKPOINT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECKPOINT_PATH))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.removeItem(%s); } catch (e) {}"
			% JSON.stringify(CHECKPOINT_KEY), true)


## The newer of two normalized checkpoints ({} when neither is valid).
static func pick_checkpoint(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty():
		return b
	if b.is_empty():
		return a
	return a if float(a.saved_at) >= float(b.saved_at) else b


## Type-checks a raw snapshot and normalizes it (ConfigFile keeps ints, JSON turns
## them into floats). Returns {} for anything that isn't a sane v1 checkpoint.
static func normalize_checkpoint(raw: Dictionary, level_count: int) -> Dictionary:
	if raw.is_empty():
		return {}
	for k in CHECKPOINT_FIELDS:
		if not raw.has(k):
			return {}
	if int(raw.v) != CHECKPOINT_VERSION:
		return {}
	var li := int(raw.level_index)
	if li < 0 or li >= level_count:
		return {}
	if not (raw.weapon_marks is Array and raw.stats is Array and raw.cleared_arenas is Array):
		return {}
	if (raw.weapon_marks as Array).size() != 4 or (raw.stats as Array).size() != 7:
		return {}
	var marks := []
	for m in raw.weapon_marks:
		marks.append(clampi(int(m), 0, MARK_DAMAGE[0].size() - 1))
	var stats := []
	for s in raw.stats:
		stats.append(maxi(0, int(s)))
	var cleared := []
	for c in raw.cleared_arenas:
		cleared.append(int(c))
	return {
		"v": CHECKPOINT_VERSION, "level_index": li,
		"level_start_score": maxi(0, int(raw.level_start_score)),
		"score": maxi(0, int(raw.score)),
		"weapon_marks": marks,
		"plasma_bombs": clampi(int(raw.plasma_bombs), 0, PLASMA_MAX),
		"missiles": maxi(0, int(raw.missiles)),
		"weapon_index": clampi(int(raw.weapon_index), 0, 3),
		"shields": maxf(0.0, float(raw.shields)),
		"energy": maxf(0.0, float(raw.energy)),
		"salvage_run": maxi(0, int(raw.salvage_run)),
		"stats": stats,
		"elapsed": maxf(0.0, float(raw.elapsed)),
		"ring": maxi(1, int(raw.ring)),
		"cleared_arenas": cleared,
		"difficulty": clampi(int(raw.get("difficulty", 1)), 0, DIFFICULTY_NAMES.size() - 1),
		"saved_at": float(raw.saved_at),
		"build": str(raw.get("build", "")),
	}


## Restores a checkpoint's run state (CONTINUE / RETRY FROM CHECKPOINT). Shields
## come back to at least half: a checkpoint should never leave you nearly dead.
func apply_checkpoint(cp: Dictionary) -> void:
	level_index = cp.level_index
	weapon_marks = (cp.weapon_marks as Array).duplicate()
	is_dead = false
	is_overheated = false
	heat = 0.0
	shields = maxf(float(cp.shields), max_shields() * 0.5)
	energy = cp.energy
	plasma_bombs = cp.plasma_bombs
	apply_checkpoint_level_state(cp)


## The part of a checkpoint that _launch_level's level-start resets would wipe, so
## it is applied again after them.
func apply_checkpoint_level_state(cp: Dictionary) -> void:
	level_start_score = cp.level_start_score
	score = cp.score
	missiles = cp.missiles
	weapon_index = cp.weapon_index
	salvage_run = cp.salvage_run
	var s: Array = cp.stats
	level_kills = s[0]
	level_shots = s[1]
	level_hits = s[2]
	level_props = s[3]
	level_secrets = s[4]
	peak_style = s[5]


# --- Phase H: player settings, persisted to user://settings.cfg ---
signal dither_toggled(on: bool)
signal amber_toggled(on: bool)   # V2.0: amber "terminal" view mode
signal crt_changed(mode: int)    # 3.0: CRT filter mode

var master_volume := 0.8
var mouse_sens_mult := 1.0
var dither_enabled := true
var gamepad_enabled := false   # K6: opt-in, never default
var amber_mode := false        # amber-monochrome terminal look (via the dither shader)
var screen_shake := true       # V2.2 L1: camera kick/shake master switch (accessibility)
## 3.0: post filter over the whole window — 0 off, 1 scanlines, 2 full CRT
## (scanlines + aperture mask + curvature + vignette). Scanlines by default: they
## read as "a 1995 monitor" without bending anything.
var crt_mode := 1
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
## M4c: small additive fine-aim nudge from device tilt, on top of stick/D-pad
## steering. Opt-in — iOS requires an explicit permission gesture (the settings
## toggle fires it) and a constant background nudge is disorienting for anyone
## who doesn't want it.
var gyro_aim_enabled := false
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
	crt_changed.emit(crt_mode)
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
		gyro_aim_enabled = cfg.get_value("settings", "gyro", gyro_aim_enabled)
		seen_warning = cfg.get_value("settings", "seen_warning", seen_warning)
		crt_mode = clampi(int(cfg.get_value("settings", "crt", crt_mode)), 0, 2)
		difficulty = clampi(int(cfg.get_value("settings", "difficulty", difficulty)),
			0, DIFFICULTY_NAMES.size() - 1)
		assist_damage = clampi(int(cfg.get_value("settings", "assist_dmg", assist_damage)),
			0, ASSIST_DAMAGE.size() - 1)
		assist_speed = clampi(int(cfg.get_value("settings", "assist_spd", assist_speed)),
			0, ASSIST_SPEED.size() - 1)


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
	cfg.set_value("settings", "gyro", gyro_aim_enabled)
	cfg.set_value("settings", "seen_warning", seen_warning)
	cfg.set_value("settings", "crt", crt_mode)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("settings", "assist_dmg", assist_damage)
	cfg.set_value("settings", "assist_spd", assist_speed)
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
