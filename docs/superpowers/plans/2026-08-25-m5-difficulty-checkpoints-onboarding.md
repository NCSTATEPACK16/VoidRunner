# M5: Difficulty, Checkpoints, Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give cold players (Reddit traffic, not John) three difficulty presets that scale fairly, a checkpoint system that survives a closed browser tab, and a first-90-seconds onboarding pass — closing M11 kill criterion #6 ("the first sixty seconds are not defensible to a cold player").

**Architecture:** Difficulty is a small multiplier table applied at the same points `LevelDef`'s existing per-level tuning is already applied (enemy fire rate, enemy speed already live as `LevelDef.enemy_fire`/`enemy_speed`; player shields already live as `GameState.max_shields()`) — so this is a scaling layer on top of existing systems, not a new one, matching V2.2's own `MARK_*`/`SHIP_CAPS` multiplier-table pattern already in `game_state.gd`. Checkpointing persists a small snapshot to the same `user://` ConfigFile mechanism `GameState.save_records()`/`load_records()` already use. Onboarding is content work inside `lore.gd` and `overlays.gd`'s existing briefing renderer — no new systems.

**Tech Stack:** GDScript (Godot 4.7), `ConfigFile` for persistence (matches `records.cfg`/`settings.cfg`'s existing pattern).

**Spec:** `../../../../PLAN.md` (parent `RadixRemix/PLAN.md`), Part Two §M5.

## Global Constraints

- Same hard rules as every other plan in this repo (no imported assets, never name the source game, MIT-only, child-friendly tone) — nothing here touches assets or text that risks any of them.
- **Difficulty presets must never change enemy count, level layout, or `level_seed`** — `PLAN.md`'s M5 spec is explicit about this ("Never enemy count, which would change a level's shape and make cross-player feedback incomparable"). Only fire rate, projectile speed, player shields, and checkpoint density move. Score/ranks stay available on every tier — do not gate scoring or rank computation behind difficulty.
- Checkpointing must degrade safely: a corrupt or missing checkpoint file must never crash the boot path — `load_records()`'s existing `if cfg.load(...) == OK:` guard is the model to copy.
- Gate discipline: headless `--import`, headless `tests/smoke_test.tscn` (zero `SCRIPT ERROR`), rendered `tests/screenshot_probe.tscn` eyeballed, clean `Web` export. Extend `smoke_test.gd`'s existing idiom (single scripted run, `assert()` calls) — do not introduce pytest or GUT.
- Commit per task. Update `PLAN.md`'s M5 row and `CLAUDE.md` §6 at session end.

---

## Task 1: Difficulty preset data + selection UI

**Files:**
- Modify: `scripts/game_state.gd`
- Modify: `scripts/overlays.gd` (`_build_start`, `_refresh_start`)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Produces: `GameState.difficulty: int` (0=Recruit, 1=Runner default, 2=Voidborne), persisted in `user://settings.cfg` key `"difficulty"`.
- Produces: `GameState.difficulty_names := ["RECRUIT", "RUNNER", "VOIDBORNE"]` (const), `GameState.enemy_fire_mult() -> float`, `GameState.enemy_speed_mult() -> float`, `GameState.shield_mult() -> float`, `GameState.checkpoint_density_mult() -> float` — four accessor functions other tasks/files read, following the exact shape of the existing `heat_mult()`/`hull_mult()`/`magnet_mult()` accessors already in this file (`game_state.gd:190-203`).

- [ ] **Step 1: Add the preset table and current-selection field**

In `scripts/game_state.gd`, near the existing `MARK_*`/`SHIP_CAPS`/`HEAT_MULTS` constant block (`game_state.gd:33-41`), add:

```gdscript
# --- M5: difficulty presets. Index: [Recruit, Runner, Voidborne]. Runner (1) is
# the default — matches the tuning every level/boss/K-phase number in this repo
# was already balanced against, so Runner must always resolve to 1.0 across the
# board (identity row) rather than being re-tuned to some new "normal."
const DIFF_NAMES := ["RECRUIT", "RUNNER", "VOIDBORNE"]
const DIFF_ENEMY_FIRE := [0.75, 1.0, 1.3]      # multiplies LevelDef.enemy_fire (seconds
                                                 # between shots — LOWER is faster, so
                                                 # Recruit gets a HIGHER interval)
const DIFF_ENEMY_SPEED := [0.85, 1.0, 1.2]      # multiplies enemy_speed and enemy shot velocity
const DIFF_SHIELD := [1.25, 1.0, 0.8]           # multiplies max_shields()
const DIFF_CHECKPOINT_DENSITY := [1.5, 1.0, 0.6] # multiplies checkpoint spacing frequency
                                                   # (Task 2) — higher = more checkpoints

var difficulty := 1   # Runner, default
```

Note the fire-interval inversion in the comment above: `LevelDef.enemy_fire` (`level_def.gd:15`) is *seconds between shots*, so "harder" means a *smaller* number, and the Recruit row must therefore be the largest multiplier, not the smallest — get this backwards and Recruit becomes the hardest preset. Verify this against `enemy_manager.gd`'s actual use of `enemy_fire` (search for where `LevelDef.enemy_fire` is read in `enemy_manager.gd` or `game.gd` before writing Step 2, to confirm the sign).

- [ ] **Step 2: Add the four accessor functions**

Next to `heat_mult()`/`missile_cap()`/`magnet_mult()`/`hull_mult()` (`game_state.gd:190-203`):

```gdscript
func enemy_fire_mult() -> float:
	return DIFF_ENEMY_FIRE[difficulty]


func enemy_speed_mult() -> float:
	return DIFF_ENEMY_SPEED[difficulty]


func shield_mult() -> float:
	return DIFF_SHIELD[difficulty]


func checkpoint_density_mult() -> float:
	return DIFF_CHECKPOINT_DENSITY[difficulty]
```

- [ ] **Step 3: Persist through the load/save triangle**

Add to `load_settings()`: `difficulty = cfg.get_value("settings", "difficulty", difficulty)`
Add to `_save_settings()`: `cfg.set_value("settings", "difficulty", difficulty)`
Clamp on load in case a future build shrinks the preset list: `difficulty = clampi(difficulty, 0, DIFF_NAMES.size() - 1)`.

- [ ] **Step 4: Start-screen selector**

`_build_start()`/`_refresh_start()` (`overlays.gd:198-232`, `93-105`) already has a sector `< >` selector pattern (`selected_sector()`, `_adjust_sector()`) — copy that exact pattern for difficulty rather than inventing a new widget shape:

```gdscript
func _adjust_difficulty(dir: int) -> void:
	GameState.difficulty = clampi(GameState.difficulty + dir, 0, GameState.DIFF_NAMES.size() - 1)
	GameState.apply_settings()
	_refresh_start()
```

Add `< DIFFICULTY: RUNNER >`-style row to `_build_start()`, positioned clear of the sector selector and the terminal-prompt CTA (read the current `_build_start()` body in full before placing it — this panel already had one collision bug logged in this project's history, verify against a real screenshot, not just arithmetic). `_refresh_start()` updates the label text from `GameState.DIFF_NAMES[GameState.difficulty]`.

- [ ] **Step 5: Mid-run change from pause (per PLAN.md M5 bullet 1: "changeable from pause mid-campaign")**

`overlays.gd`'s pause panel (`_build_pause()`, `overlays.gd:296-302`) currently has whatever buttons it has (read it before this step) — add the same `< DIFFICULTY: X >` row there, calling the same `_adjust_difficulty()`. Changing difficulty mid-run must NOT regenerate the current level's `PathGen` (that would violate "never enemy count / layout") — it only changes the multiplier the next `enemy_fire_mult()`/`enemy_speed_mult()`/`shield_mult()` read returns, which `enemy_manager.gd`/`player.gd` read live every frame or every spawn (Task 2 wires this), so no explicit "reload" step is needed — confirm this is actually true once Task 2 shows where these multipliers get read, and if any of them are cached at level-load instead of read live, note that as a real bug to fix, not something to work around.

- [ ] **Step 6: Extend the smoke test**

```gdscript
	assert(GameState.difficulty == 1)   # Runner default
	assert(is_equal_approx(GameState.enemy_fire_mult(), 1.0))
	assert(is_equal_approx(GameState.shield_mult(), 1.0))
	game.overlays._adjust_difficulty(1)
	assert(GameState.difficulty == 2)
	assert(is_equal_approx(GameState.shield_mult(), 0.8))
	game.overlays._adjust_difficulty(1)   # clamps at Voidborne, doesn't wrap
	assert(GameState.difficulty == 2)
	game.overlays._adjust_difficulty(-2)
	assert(GameState.difficulty == 0)     # clamps at Recruit
	GameState.difficulty = 1   # restore default before the rest of the test runs
```

- [ ] **Step 7: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/screenshot_probe.tscn
git add scripts/game_state.gd scripts/overlays.gd tests/smoke_test.gd
git commit -m "feat(difficulty): Recruit/Runner/Voidborne presets (M5, D5)"
```

---

## Task 2: Apply difficulty multipliers to enemies and shields

**Files:**
- Modify: `scripts/enemy_manager.gd` (spawn / fire-timer / speed reads)
- Modify: `scripts/game_state.gd` (`max_shields()`)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Consumes: `GameState.enemy_fire_mult()`, `GameState.enemy_speed_mult()`, `GameState.shield_mult()` (Task 1).

- [ ] **Step 1: Find every read of `LevelDef.enemy_fire`/`enemy_speed` in `enemy_manager.gd`**

Read `enemy_manager.gd`'s `spawn()` (`enemy_manager.gd:109-138`) and `update_enemies()` (`163-231`) in full — the outline shows `TYPES` already carries a per-enemy-type `fire_mul`/`speed_mul` (`enemy_manager.gd:33-38`), which is the exact pattern to extend: difficulty becomes a second multiplier composed with the existing per-type one, not a replacement for it.

- [ ] **Step 2: Compose the difficulty multiplier at the same point the type multiplier is applied**

Wherever `spawn()` currently computes an enemy's effective fire interval and speed from `level.enemy_fire * TYPES[type_id].fire_mul` (exact expression depends on what Step 1 finds — read it precisely before editing), change to:

```gdscript
	# M5: difficulty composes with the per-type multiplier already applied here.
	var fire_interval: float = level.enemy_fire * TYPES[type_id].fire_mul * GameState.enemy_fire_mult()
	var eff_speed: float = level.enemy_speed * TYPES[type_id].speed_mul * GameState.enemy_speed_mult()
```

Do this at spawn time (baked into the per-enemy dictionary entry), matching how the existing per-type multiplier is already baked in rather than read fresh every frame — **unless** Step 1's read shows the existing code re-reads `level.enemy_fire`/`enemy_speed` live every frame, in which case follow that same live-read pattern instead so a mid-run difficulty change (Task 1 Step 5) takes effect on enemies already spawned, not just newly spawned ones. This is the exact ambiguity flagged in Task 1 Step 5 — resolve it here by matching whatever the existing code already does, and note in the commit message which one it turned out to be.

- [ ] **Step 3: Boss fire timing** — `_update_boss()` (`enemy_manager.gd:238-292`) has its own phase-gated fire cadence separate from the regular per-type path (`BOSS_FIRE_RANGE`, `BOSS_SHOT_DMG` constants, `_boss_volley()`). Apply `GameState.enemy_fire_mult()` there too, at whatever timer/cadence value gates a volley — read `_update_boss()` in full before editing; do not touch `BOSS_SHOT_DMG`/`BOSS_CONTACT_DMG` (damage-per-hit) or `MAX_SUMMONS` (summon cap) — those are explicitly out of scope per the "never enemy count" rule, and boss damage-per-hit scaling isn't in the M5 spec's four axes (fire rate / projectile speed / shields / checkpoints).

- [ ] **Step 4: Player shield cap**

`max_shields()` (`game_state.gd:182-183`) currently reads `MAX_SHIELDS * hull_mult-equivalent-ship-rank` (read its actual body — the outline only shows the signature). Compose difficulty in:

```gdscript
func max_shields() -> float:
	return MAX_SHIELDS * SHIP_CAPS[ship_rank_index("shield")] / SHIP_CAPS[0] * GameState.shield_mult()
```

(the exact existing expression will differ — read the real body first and multiply the *existing return value* by `shield_mult()`, don't guess the whole formula from scratch.)

- [ ] **Step 5: Projectile speed** — PLAN.md's M5 axis list includes "projectile speed," which for enemy shots lives in `shot_manager.gd::fire_enemy()` (`shot_manager.gd:182-192`, `velocity` parameter) or wherever `enemy_manager.gd` computes the velocity it passes to `EnemyManager.enemy_fired` → `ShotManager.fire_enemy`. Apply `GameState.enemy_speed_mult()` to that velocity at the point it's constructed in `enemy_manager.gd`, not inside `shot_manager.gd` (which has no concept of difficulty and shouldn't need one — keep the multiplier applied at the single point closest to where difficulty already composes with the per-type speed multiplier from Step 2, so there's one place to read to understand the whole difficulty-scaling story).

- [ ] **Step 6: Extend the smoke test**

```gdscript
	# M5: difficulty actually changes what ships — Voidborne enemies fire faster
	# and have less player shield headroom than Recruit, at the same level/seed.
	GameState.difficulty = 0   # Recruit
	var recruit_shields := GameState.max_shields()
	GameState.difficulty = 2   # Voidborne
	var voidborne_shields := GameState.max_shields()
	assert(voidborne_shields < recruit_shields)
	GameState.difficulty = 1   # restore Runner before the rest of the test runs
```

Add a similar direct-comparison assertion for `enemy_fire_mult()`/`enemy_speed_mult()` if Step 2's resolution baked them into a spawned enemy's dictionary (assert the dictionary field differs across two spawns at different difficulty settings) — if it's a live read instead, the accessor-level assertions from Task 1 Step 6 already cover it and no further test is needed here.

- [ ] **Step 7: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/perf_probe.tscn   # difficulty must not change per-frame cost meaningfully
git add scripts/enemy_manager.gd scripts/game_state.gd tests/smoke_test.gd
git commit -m "feat(difficulty): apply presets to enemy fire/speed and player shields (M5)"
```

---

## Task 3: Checkpointing that survives a closed tab

**Files:**
- Modify: `scripts/game_state.gd` (new checkpoint save/load functions)
- Modify: `scripts/game.gd` (`_load_level_world`, `_on_player_died`, `_launch_level`)
- Modify: `scripts/overlays.gd` (start-screen "RESUME" affordance)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Produces: `GameState.save_checkpoint() -> void`, `GameState.load_checkpoint() -> bool` (returns whether one existed), `GameState.clear_checkpoint() -> void`, persisted to `user://checkpoint.cfg` (a separate file from `records.cfg`, so a checkpoint's presence/absence never risks corrupting best-score data).
- Consumes (Task 2): none. Independent of difficulty except that checkpoint *density* (Task 4) reads `GameState.checkpoint_density_mult()`.

- [ ] **Step 1: Design the checkpoint's shape — what does "surviving a closed tab" actually need to restore?**

A checkpoint must be enough to resume mid-level without re-deriving anything PathGen-dependent from scratch in a way that could desync from what the player actually saw. The safe, minimal shape (matching this project's existing preference for simple ConfigFile blobs over anything relational): `level_index`, `level_seed` (redundant with `level_index` today since seeds are static per `.tres`, but explicit — protects against a future per-run-random seed), `ring_idx` (nearest-ring position — `player.gd` already tracks this as `ring_idx`, updated every frame via `path.nearest_ring()`), `shields`, `energy`, `score`, `weapon_index`, `missiles`, `plasma_bombs`, `difficulty`. Explicitly NOT saved: enemy/prop/hazard live state (which enemies are already dead, which fuel cells are already destroyed) — restoring that precisely would require serializing far more state than this genre needs; instead, a checkpoint resume re-enters the level fresh (full `_load_level_world`) but starts the player at the checkpoint's ring position with the checkpoint's stats. This is "err more generous than a 1995 purist" (the spec's own words) applied honestly: a resumed run isn't byte-identical to where the player left off, but it never makes them repeat a fully-cleared level from ring 0 after a lost tab.

- [ ] **Step 2: Implement save/load/clear**

In `scripts/game_state.gd`, modeled directly on the existing `load_records()`/`save_records()` pair (`game_state.gd:258-283`):

```gdscript
# --- M5: checkpointing, survives a closed tab. Separate file from records.cfg
# so a missing/corrupt checkpoint can never affect best-score persistence.
func save_checkpoint(ring_idx: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cp", "level_index", level_index)
	cfg.set_value("cp", "ring_idx", ring_idx)
	cfg.set_value("cp", "shields", shields)
	cfg.set_value("cp", "energy", energy)
	cfg.set_value("cp", "score", score)
	cfg.set_value("cp", "weapon_index", weapon_index)
	cfg.set_value("cp", "missiles", missiles)
	cfg.set_value("cp", "plasma_bombs", plasma_bombs)
	cfg.set_value("cp", "difficulty", difficulty)
	cfg.save("user://checkpoint.cfg")


func has_checkpoint() -> bool:
	return FileAccess.file_exists("user://checkpoint.cfg")


func load_checkpoint() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load("user://checkpoint.cfg") != OK:
		return {}
	return {
		"level_index": cfg.get_value("cp", "level_index", 0),
		"ring_idx": cfg.get_value("cp", "ring_idx", 0),
		"shields": cfg.get_value("cp", "shields", MAX_SHIELDS),
		"energy": cfg.get_value("cp", "energy", MAX_ENERGY),
		"score": cfg.get_value("cp", "score", 0),
		"weapon_index": cfg.get_value("cp", "weapon_index", 0),
		"missiles": cfg.get_value("cp", "missiles", MISSILES_PER_LEVEL),
		"plasma_bombs": cfg.get_value("cp", "plasma_bombs", 1),
		"difficulty": cfg.get_value("cp", "difficulty", 1),
	}


func clear_checkpoint() -> void:
	if has_checkpoint():
		DirAccess.remove_absolute("user://checkpoint.cfg")
```

- [ ] **Step 3: Write a checkpoint periodically during play**

Read `game.gd::_process()` (`game.gd:869-921`) in full. Add a throttled call (checkpointing every frame would be wasted I/O — this project's own perf-probe discipline flags exactly this kind of thing):

```gdscript
	# M5: checkpoint roughly every 10s of flight, not every frame.
	_checkpoint_t += delta
	if _checkpoint_t > 10.0 and state == State.PLAYING:
		_checkpoint_t = 0.0
		GameState.save_checkpoint(player.ring_idx)
```

Declare `var _checkpoint_t := 0.0` near `game.gd`'s other per-frame timers (find where `WARM_FRAMES`/similar frame-scoped vars live and place it consistently).

- [ ] **Step 4: Clear the checkpoint on level clear and on a fresh campaign start**

`_level_complete()` (`game.gd:640-682`) and `_on_new_campaign()` (`game.gd:862-864`) should both call `GameState.clear_checkpoint()` — a cleared level has nothing to resume into, and a deliberate new campaign shouldn't silently resume the old one.

- [ ] **Step 5: Offer resume from the start screen**

`_build_start()`/`_refresh_start()` (`overlays.gd`) — add a `RESUME` button, shown only when `GameState.has_checkpoint()` is true, positioned near the sector-select row it complements. On press, emit a new `resume_requested` signal (declared alongside the existing `launch_requested`/`gauntlet_requested` signals at the top of `overlays.gd:9-14`).

- [ ] **Step 6: Wire resume in `game.gd`**

Add a handler mirroring `_on_launch()` (`game.gd:724-734`) and `_load_level_world()` (`game.gd:314-382`):

```gdscript
func _on_resume() -> void:
	var cp := GameState.load_checkpoint()
	if cp.is_empty():
		return
	GameState.level_index = cp.level_index
	GameState.difficulty = cp.difficulty
	_load_level_world(cp.level_index)
	_launch_level()
	player.snap_ring(cp.ring_idx)   # player.gd:316-317 already exists for exactly this
	GameState.shields = cp.shields
	GameState.energy = cp.energy
	GameState.score = cp.score
	GameState.weapon_index = cp.weapon_index
	GameState.missiles = cp.missiles
	GameState.plasma_bombs = cp.plasma_bombs
```

Connect `overlays.resume_requested.connect(_on_resume)` next to the existing overlay signal connections in `_ready()` (`game.gd:70-225` — find where `launch_requested.connect(_on_launch)` etc. already live).

- [ ] **Step 7: Extend the smoke test**

```gdscript
	# M5: checkpoint round-trips through user://checkpoint.cfg
	GameState.clear_checkpoint()
	assert(not GameState.has_checkpoint())
	GameState.score = 4200
	GameState.save_checkpoint(37)
	assert(GameState.has_checkpoint())
	var cp := GameState.load_checkpoint()
	assert(cp.ring_idx == 37)
	assert(cp.score == 4200)
	GameState.clear_checkpoint()
	assert(not GameState.has_checkpoint())
```

Also snapshot/restore `user://checkpoint.cfg` alongside the existing `records.cfg`/`settings.cfg` snapshot-restore block at the top of `_run()` (`tests/smoke_test.gd`'s existing `saved := {}` loop, per this project's own logged gotcha about test runs clobbering real player files — extend that same `for f in [...]` array to include `"user://checkpoint.cfg"`).

- [ ] **Step 8: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/screenshot_probe.tscn
git add scripts/game_state.gd scripts/game.gd scripts/overlays.gd tests/smoke_test.gd
git commit -m "feat(checkpoint): resume a run that survives a closed tab (M5)"
```

---

## Task 4: Checkpoint density scaling by difficulty

**Files:**
- Modify: `scripts/game.gd` (`_process` checkpoint-interval read from Task 3 Step 3)

**Interfaces:**
- Consumes: `GameState.checkpoint_density_mult()` (Task 1).

- [ ] **Step 1: Scale the checkpoint interval, not the trigger condition**

Task 3 Step 3's flat `10.0` second interval becomes:

```gdscript
	var interval := 10.0 / GameState.checkpoint_density_mult()
	if _checkpoint_t > interval and state == State.PLAYING:
```

Higher density (Recruit, 1.5×) → shorter interval (~6.7s, more frequent saves, less lost on a crash); lower density (Voidborne, 0.6×) → longer interval (~16.7s). This is intentionally a small effect (checkpoints are always "resume this level from roughly here," never a precision save-state) — the real difficulty lever is Task 2's combat multipliers, per the spec's own framing of checkpoint density as the lowest-weight of the four axes.

- [ ] **Step 2: Extend the smoke test**

```gdscript
	GameState.difficulty = 0
	assert(10.0 / GameState.checkpoint_density_mult() < 10.0)   # Recruit checkpoints MORE often
	GameState.difficulty = 2
	assert(10.0 / GameState.checkpoint_density_mult() > 10.0)   # Voidborne checkpoints LESS often
	GameState.difficulty = 1
```

- [ ] **Step 3: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
git add scripts/game.gd tests/smoke_test.gd
git commit -m "feat(checkpoint): scale save frequency by difficulty preset (M5)"
```

---

## Task 5: Sector-1 onboarding (diegetic, ~90 seconds, no added text)

**Files:**
- Modify: `scripts/lore.gd` (sector-1 lines only)
- Modify: `scripts/game.gd` or a new lightweight onboarding cue system, gated to `level_index == 0` on a fresh (non-resumed) run
- Test: `tests/smoke_test.gd`, manual playtest (this is a feel task — see note)

**Interfaces:** none new beyond what `lore.gd`/`overlays.gd` already expose (`Lore.story()`, `Lore.load_lines()`).

- [ ] **Step 1: Re-read the spec's constraint carefully**

`PLAN.md` M5 bullet 3 says onboarding teaches fire/boost/dodge "diegetically, without adding text." That rules out a tutorial overlay with instructional strings — the mechanism has to be the level's own geometry and enemy placement teaching the verbs through play, the way the original genre's "corridor that only opens once you shoot the thing in front of you" pacing works. This is **level-design work on `resources/levels/level_1.tres`**, not a new code system — read that resource file's actual current values (via `get_file_content` on `resources/levels/level_1.tres`, a `.tres` text-Resource file) before touching anything, since `LevelDef`'s fields (Task 1 established the full field list) already control spawn density (`spawn_tunnel`, `spawn_arena`) and enemy types (`enemy_types`) — teaching "fire" is a matter of guaranteeing the very first enemy encounter is unmissable and undodgeable-without-firing, teaching "boost" is a matter of a corridor stretch early on that rewards or requires it (a closing door/timing gate, or simply an early long straight where boost is the obviously-correct move), teaching "dodge" is a matter of an early attack pattern that's much easier to survive with a dodge than by tanking it.

- [ ] **Step 2: Concrete level_1.tres adjustments**

Based on Step 1's read of the actual current file, propose specific changes (exact numbers depend on what's actually there — do not invent numbers the file doesn't currently have context for): ensure the first `spawn_tunnel` enemy appears within the first ~15-20 rings (close enough that a new player fires almost immediately out of the briefing), ensure at least one arena in the first third of the level has an enemy attack pattern a dodge clearly answers (a wide/telegraphed shot a stationary player would eat), and confirm no crusher/hazard (`hazard_manager.gd`, K3) appears before roughly ring 40 — a new player's first hazard encounter should not be simultaneous with their first combat encounter.

- [ ] **Step 3: A single diegetic HUD cue, not instructional text**

The one piece of code this task plausibly needs: a first-few-seconds cue that's diegetic rather than an instruction string — e.g., the existing damage-direction arc system (`hud.gd`'s `_dmg_arcs`, confirmed already shipped per this project's M1/M2 session log) already teaches "you got hit, here's where from" without any added text; if `hud.gd` doesn't already pulse/highlight the weapon indicator on the player's first-ever shot fired (a "your gun just did something" affordance, using color/motion rather than words), that's the one small, justified code addition here — read `hud.gd`'s weapon-indicator drawing before deciding whether it's needed; if the existing muzzle flash + kick (`player.gd::add_kick`/`flash_muzzle`, already shipped) already reads clearly on a first shot, skip this step entirely rather than adding cue machinery the game doesn't need. Prefer "skip" — this project's own conventions (CLAUDE.md: "Don't add features... beyond what the task requires") argue against new HUD systems when existing feedback already covers the ground.

- [ ] **Step 4: Manual verification, not an automated test**

Onboarding quality is a feel judgment, not something `smoke_test.gd`'s assertions can meaningfully check (it can confirm the level still loads and completes, which the existing per-level smoke loop already does for free). Flag explicitly in the plan and in the session log: this task's real gate is John (or a genuinely first-time player) playing sector 1 cold and reporting whether fire/boost/dodge were clear without being told. Do not claim this task "done" on headless-green alone.

- [ ] **Step 5: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn   # confirms level_1.tres still loads/completes
git add resources/levels/level_1.tres scripts/lore.gd
git commit -m "content: sector-1 pacing pass for diegetic onboarding (M5)"
```

---

## Task 6: Briefing bands trimmed and skippable

**Files:**
- Modify: `scripts/overlays.gd` (`_build_briefing`, `set_briefing`)
- Test: `tests/smoke_test.gd`

**Interfaces:** none new.

- [ ] **Step 1: Read the current briefing implementation in full**

`_build_briefing()`/`set_briefing()` (`overlays.gd:268-293`, `112-124`) already implement the three-band layout from the story-pass session (Story/Objective/Body, non-overlapping, autowrapped) — read both in full before changing anything; "trimmed" here means confirming the per-level `.tres` `briefing`/`objective` text (already noted in the session log as "trimmed to their tactical halves" back when `lore.gd` was introduced) hasn't crept back up in length as levels were added/edited since, not building a new trimming mechanism.

- [ ] **Step 2: Add a skip affordance**

If `_build_briefing()` doesn't already have one, add a `SKIP` button (or confirm the existing LAUNCH button already doubles as skip — read first) that calls the same `launch_requested` emission path immediately, bypassing any auto-advance timer if one exists. Read the current LAUNCH button wiring before deciding whether this is new work or already covered.

- [ ] **Step 3: Extend the smoke test**

Confirm the existing band-geometry asserts (already present per the M1/M2 session log: "band-geometry asserts") still pass after any text-length trims — if Step 1 finds no trims are actually needed, this task may collapse to "verified, no change" (a legitimate outcome — note it as such in the commit rather than forcing a change).

- [ ] **Step 4: Gate + commit (or note no-op)**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/screenshot_probe.tscn
```

If Step 1/2 found real changes: `git add scripts/overlays.gd resources/levels/*.tres && git commit -m "polish: briefing trim + skip affordance (M5)"`. If not: no commit needed — record in the session log that this sub-task was verified already-satisfied.

---

## Self-Review

**Spec coverage:** M5 bullet 1 (three presets, four axes, never enemy count, score/ranks always available) → Tasks 1-2. M5 bullet 2 (checkpointing surviving a closed tab) → Tasks 3-4. M5 bullet 3 (sector-1 onboarding) → Task 5. M5 bullet 4 (briefing trim/skip) → Task 6. M5's gate ("all three presets playable end-to-end on sector 1; a mid-level difficulty change applies without a reload; a killed-and-resumed run restores at the checkpoint; smoke test extended to cover preset application") is covered by Tasks 1/2's smoke additions (preset application), Task 1 Step 5 + Task 2 Step 2's live-vs-baked resolution (mid-level change without reload), and Task 3's checkpoint round-trip test (resume).

**Placeholder scan:** Task 2 Step 2 and Task 5 Steps 1-3 both explicitly defer an exact value/decision to "read the actual file first" rather than inventing a number — this is directed investigation with a concrete resolution procedure, not a vague TODO; each names exactly what to look for and what to do with either outcome. Task 6 explicitly allows a "no-op, already satisfied" result as a valid outcome, per the skill's own guidance that a wrong-plan discovery should be stated, not silently worked around — this is the plan being honest that it doesn't know yet whether that work still needs doing.

**Type consistency:** `GameState.difficulty` (int, 0-2) is used identically across Tasks 1, 2, 3 (checkpoint stores/restores it), and 4. The checkpoint `Dictionary` shape defined in Task 3 Step 2 is consumed with matching keys in Task 3 Step 6. `enemy_fire_mult()`/`enemy_speed_mult()`/`shield_mult()`/`checkpoint_density_mult()` signatures (no args, `-> float`) match their Task 1 declarations everywhere they're called in Tasks 2 and 4.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-25-m5-difficulty-checkpoints-onboarding.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in one session using executing-plans, batch execution with checkpoints.

Task 5 (onboarding) specifically benefits from a human playtest between its code step and being marked "done" — flag this to whichever execution mode is chosen so it isn't rubber-stamped on headless-green alone.
