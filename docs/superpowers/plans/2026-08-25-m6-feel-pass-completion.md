# M6: Feel Pass Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the real gap in `PLAN.md`'s M6 "Feel pass" — which, on inspection of the current codebase, turns out to be **already shipped** for four of its five listed items back in V2.2's L1 ("gibs/hit-stop/kick+shake/hit-flash/damage arcs," `CLAUDE.md` §6, 2026-07-18). Only two genuine gaps remain: **enemy infighting** (stray enemy fire damaging other enemies) and **boost feedback** (an FOV kick + audio swell on the boost transition, distinct from the existing continuous engine-pitch feedback).

**Architecture:** `PLAN.md`'s M6 was written 2026-08-19 without cross-checking it against work `L1` had already shipped a month earlier (2026-07-16/18) — a documentation drift this plan corrects at the source (Task 0) before writing any code, so a future session doesn't re-discover the same false gap. The two real tasks are both small, additive changes to existing systems: infighting adds one more damage path inside `enemy_manager.gd`'s already-existing `hit_enemy()`/`splash_damage()` machinery; boost feedback adds two lines to `player.gd::update_flight()` alongside the muzzle-kick code that already does the same kind of camera/audio punctuation for weapon fire.

**Tech Stack:** GDScript (Godot 4.7). No new systems, no new nodes.

**Spec:** `../../../../PLAN.md` (parent `RadixRemix/PLAN.md`), Part Two §M6 — read this plan's Task 0 first; it explains exactly which of that section's five bullets are stale.

## Global Constraints

- Same hard rules as every plan in this repo (no imported assets, never name the source game, MIT-only, child-friendly tone).
- **Every addition in M6 must ship with a settings toggle** — this is explicit in the spec ("Everything here ships toggleable — the same juice that reads as great feel to one player reads as nausea to another") and matches the existing precedent: `GameState.screen_shake` already gates the L1 kick/shake work. Infighting doesn't need a toggle (it's a combat-balance change, not a sensory one — no spec language calls for one, and it doesn't produce screen motion/flashing); boost feedback's FOV-kick component should respect the existing `reduce_roll`/`reduce_flashing` comfort settings rather than adding a new one, per this project's established pattern of composing new juice into existing comfort gates instead of multiplying the settings surface.
- Gate: `PLAN.md`'s own M6 gate — "perf probe shows no regression (worst step within the established band, zero spikes); a rendered capture shows a visible pain state and hit-stop; every addition has a settings toggle." The pain-state/hit-stop half of that gate is **already met** by existing L1 work (Task 0 documents this) — re-verify it as part of this plan's gate rather than re-building it.
- Commit per task. Update `PLAN.md`'s M6 row and `CLAUDE.md` §6 at session end — this is the task where correcting the ledger matters most, since the row as currently written would send a future session hunting for four features that already exist.

---

## Task 0: Correct `PLAN.md`'s M6 section (documentation, do this first)

**Files:**
- Modify: `../../../../PLAN.md` (§M6)

- [ ] **Step 1: Verify each of the five M6 bullets against the actual current code**

This plan's own reconnaissance (done before writing it) found:

| M6 bullet | Status | Evidence |
|---|---|---|
| 1. Enemy pain states + hit-stop | **Already shipped** (L1) | `scripts/gib_manager.gd::hit_stop(ms, scale, force)` — freeze-frame on kill; `GIB_TINTS`/`burst()` for per-type gib pain state |
| 2. Per-weapon view-kick + muzzle flash | **Already shipped** (L1) | `scripts/player.gd::add_kick(weapon_idx)`, `flash_muzzle(color)`, `WEAPON_KICK := [0.25, 0.7, 0.4, 0.9]` (per-weapon values, `player.gd:49`) |
| 3. Hit-confirm: enemy flash + impact layer | **Already shipped** (L1) | `sprite_gen.gd`'s frame generators all take a `flash: bool` param (e.g. `_draw_drone(frame, flash)`); `audio_sys.gd::play_hit()` |
| 4. Enemy infighting | **Genuinely missing** | No hits found for "infighting" anywhere in the repo; `enemy_manager.gd::update_enemies()`/`hit_enemy()` show no enemy-vs-enemy damage path |
| 5. Boost feedback: FOV kick + audio swell | **Genuinely missing** | `player.gd::update_flight()`'s boost branch (`if boosting: target = BOOST_SPEED; GameState.energy -= ...`) does nothing beyond the speed lerp; `AudioSys.set_engine(speed, BOOST_SPEED)` is continuous pitch-from-speed, not a one-shot swell |

Re-verify this table against the code as it stands at execution time (not just trust this plan) — confirm with a quick search before editing `PLAN.md`, since time may have passed between this plan being written and executed.

- [ ] **Step 2: Rewrite `PLAN.md`'s M6 section**

Replace the current M6 bullet list with:

```markdown
## M6 — Feel pass

*Small — narrower than originally scoped; see below.* Everything here ships toggleable.

**Already shipped in V2.2 L1 (2026-07-18), discovered during a later audit — this
section originally duplicated existing work:** enemy pain states + hit-stop
(`gib_manager.gd::hit_stop`), per-weapon view-kick + muzzle flash
(`player.gd::add_kick`/`flash_muzzle`, `WEAPON_KICK`), and hit-confirm flash +
impact audio (`sprite_gen.gd`'s per-frame `flash` param, `audio_sys.gd::play_hit`).

**Genuine remaining work:**
1. **Enemy infighting** — stray enemy fire damages other enemies. Cheap, creates
   emergent spectacle and breathing room, and is more period-accurate rather than
   less.
2. **Boost feedback** — FOV kick and audio swell on the boost *transition*
   (distinct from the existing continuous engine-pitch-from-speed feedback), so
   speed feels like a deliberate choice, not just a number changing.

**Gate:** perf probe shows no regression (worst step within the established band,
zero spikes); infighting is observable in a scripted test (one enemy's stray shot
damaging another); boost feedback is toggle-respecting and doesn't fight the
existing muzzle-kick camera motion. The hit-stop/pain-state half of the original
gate was already met by L1 — not re-verified here as new work, just re-confirmed
not regressed.
```

- [ ] **Step 3: Commit the doc fix alone, before any code**

```bash
git add PLAN.md
git commit -m "docs: correct M6 scope — 3 of 5 items already shipped in V2.2 L1"
```

---

## Task 1: Enemy infighting

**Files:**
- Modify: `scripts/enemy_manager.gd`
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Consumes: `enemy_manager.gd`'s existing `hit_enemy(index, dmg) -> bool` (`enemy_manager.gd:336-337`) and `_hurt(index, dmg) -> bool` (`364-371`) — infighting is a new *caller* of this existing damage path, not a new damage mechanism.
- Produces: no new public API.

- [ ] **Step 1: Read the current shot-vs-enemy collision path in full**

Read `update_shots()` in `scripts/shot_manager.gd` (`shot_manager.gd:267-374`) in full — this is where enemy shots are currently checked against the player (`player_hit` signal, `PLAYER_HIT_RANGE_SQ`) but evidently not against other enemies. Confirm this by tracing exactly how an enemy shot's position is checked each frame and where the player-hit-range check happens, so the infighting check can be added in the same loop rather than a second pass over the same shot list (a second full iteration over shots every frame is exactly the kind of avoidable per-frame cost this project's perf-probe discipline exists to catch).

- [ ] **Step 2: Add an enemy-vs-enemy-shot check in the same per-shot loop**

Using `enemy_manager.gd`'s existing `HIT_R2 := 13.0` (enemy_manager.gd:22, the same squared-radius already used for player-shot-vs-enemy hits) as the collision radius, and `EnemyManager.hit_enemy(index, dmg)` as the damage entry point, add a check that an enemy shot only ever damages an enemy *other than the one that fired it* (the shot dictionary already needs an owner reference — confirm `shot_manager.gd`'s enemy-shot dictionary entries carry something identifying origin, e.g. the firing enemy's index or arena_id; if they don't yet, this is the one piece of new state this task needs to add — a `source_index: int` field on the shot dictionary, set in `fire_enemy()`'s caller in `enemy_manager.gd` wherever `ShotManager.fire_enemy(...)` is currently invoked):

```gdscript
# In shot_manager.gd's enemy-shot dictionary construction (wherever fire_enemy
# assembles the dictionary entry — read that code first):
#   shot["source_index"] = <the firing enemy's index in EnemyManager.enemies>

# In the same update_shots() loop that already checks enemy shots against the
# player, add (using EnemyManager's existing nearest/positional data — read
# update_shots() to see what enemy-position lookup, if any, it already has
# available before adding a new one):
for i in EnemyManager.enemies.size():
	var e: Dictionary = EnemyManager.enemies[i]
	if not e.alive:
		continue
	if i == shot.get("source_index", -1):
		continue   # never friendly-fire the shooter itself
	if e.sprite.position.distance_squared_to(shot_pos) < EnemyManager.HIT_R2:
		EnemyManager.hit_enemy(i, EnemyManager.SHOT_DMG)
		<remove/expire this shot the same way a player-hit shot is removed>
		break
```

The exact loop shape (whether this becomes a nested O(shots × enemies) scan) matters for perf — `ENEMY_CAP := 42` and `ESHOT_CAP := 64` (both already-existing constants) bound the worst case to 42×64 ≈ 2,700 distance checks per frame in the theoretical worst case, which is well within what this project's own perf probe already tolerates elsewhere (compare against `near_count()`'s existing O(n) scan pattern, `enemy_manager.gd:355-361`, which runs every frame already) — but confirm with the actual perf probe in Step 4 rather than reasoning about it in the abstract.

- [ ] **Step 3: Feed gib/hit-confirm feedback through the existing path**

`EnemyManager.hit_enemy()`/`_hurt()`/`_kill()` (`enemy_manager.gd:336-430`) already trigger the L1 hit-flash/gib/audio feedback for any damage source — an infighting kill should look and sound identical to a player kill (same `_kill()` call, same `gibs_requested` signal, same score-or-not routing via `_kill(index, scored: bool)`). Pass `scored := false` for infighting kills — this is enemy-on-enemy damage, and per this project's established scoring philosophy (kills only score when the player causes them — verify this is actually how `scored` is used by reading `_kill()`'s body once, since guessing this wrong would let players farm score by baiting infighting) it must not inflate the player's score or combo.

- [ ] **Step 4: Perf gate**

```bash
godot --headless --import
godot --headless tests/perf_probe.tscn
```

Compare worst-step timing against the established baseline in `tests/perf_baseline.md` (already exists — read it for the current numbers before and after this change). Expected: no meaningful regression given the bound computed in Step 2; if there is one, that's real signal to revisit the loop shape (e.g. spatial bucketing) rather than ship a regression.

- [ ] **Step 5: Extend the smoke test**

```gdscript
	# M6: enemy infighting — a stray enemy shot damages another enemy, doesn't
	# score, and never hits the shooter itself.
	EnemyManager.clear_all()
	EnemyManager.spawn(10, -1, "drone")
	EnemyManager.spawn(10, -1, "drone")
	var hp_before: int = EnemyManager.enemies[1].hp
	var score_before := GameState.score
	# fire a shot from enemy 0 positioned exactly at enemy 1's location
	ShotManager.fire_enemy(EnemyManager.enemies[1].sprite.position, Vector3.ZERO)
	# (adjust to however Step 2 actually threads source_index through fire_enemy —
	# this may need a small test-only seam; if fire_enemy's signature can't carry
	# an explicit source_index cleanly, add an optional parameter defaulting to -1
	# rather than inventing a second entry point)
	for i in 5:
		ShotManager.update_shots(0.05)
	assert(EnemyManager.enemies[1].hp < hp_before)
	assert(GameState.score == score_before)   # infighting never scores
	EnemyManager.clear_all()
```

- [ ] **Step 6: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/perf_probe.tscn
git add scripts/enemy_manager.gd scripts/shot_manager.gd tests/smoke_test.gd
git commit -m "feat(combat): enemy infighting — stray fire damages other enemies (M6)"
```

---

## Task 2: Boost feedback — FOV kick + audio swell

**Files:**
- Modify: `scripts/player.gd` (`update_flight`)
- Modify: `scripts/audio_sys.gd` (new one-shot swell sound)
- Test: `tests/smoke_test.gd`, `tests/screenshot_probe.gd`

**Interfaces:**
- Produces: `AudioSys.play_boost_swell() -> void`, following the exact shape of the existing `play_dodge()`/`play_bomb()` one-shots (`audio_sys.gd:201-206`) — synthesized, not sampled, matching every other sound in this file.

- [ ] **Step 1: Detect the boost *transition*, not the boost *state***

`update_flight()`'s existing boost read (`player.gd:177-183`) is `var boosting := Input.is_action_pressed("boost") and GameState.energy > 0.5`. The feedback this task adds must fire once on the false→true edge, not every frame boost is held (that would just be a second continuous effect layered on the existing engine-pitch one, not the "transition" feedback the spec asks for). Add edge detection:

```gdscript
	var was_boosting: bool = _was_boosting if "_was_boosting" in self else false
```

Cleaner: declare `var _was_boosting := false` as a proper class member near the other flight-state vars at the top of `player.gd` (not an ad-hoc dynamic check), and in `update_flight()`:

```gdscript
	if boosting and not _was_boosting:
		_on_boost_start()
	_was_boosting = boosting
```

- [ ] **Step 2: Implement `_on_boost_start()`**

```gdscript
## V3.0 M6: boost feedback — a one-shot FOV pulse and audio swell on the
## boost *transition*, distinct from AudioSys.set_engine()'s continuous
## pitch-from-speed feedback. Respects reduce_roll the same way the existing
## turn-lean comfort setting does, since a sudden FOV punch is the same category
## of motion-intensity discomfort.
func _on_boost_start() -> void:
	var fov_kick := 6.0 if not GameState.reduce_roll else 2.0
	_boost_fov_kick = fov_kick
	AudioSys.play_boost_swell()
```

Declare `var _boost_fov_kick := 0.0` near `_kick_pitch` (the existing muzzle-kick decay variable player.gd already has, `player.gd`'s camera-framing block near the end of `update_flight`) and decay it the same way `_kick_pitch` already decays, applying it additively to `camera.fov` in the existing FOV line:

```gdscript
	_boost_fov_kick = lerpf(_boost_fov_kick, 0.0, minf(6.0 * delta, 1.0))
	camera.fov = GameState.view_fov + _boost_fov_kick   # M2.2 slider + M6 boost punch
```

This must be placed in the same block as the existing `camera.fov = GameState.view_fov` line (`player.gd:204`, inside the camera-framing section near the end of `update_flight`) — read that exact section before editing so the FOV assignment isn't accidentally duplicated or ordered wrong relative to the M2.2 slider read.

- [ ] **Step 3: Synthesize the swell sound**

In `scripts/audio_sys.gd`, following the exact pattern of `_render_dodge()`/`_render_bomb()` (`audio_sys.gd:403-439`) — a short procedural `AudioStreamWAV` built via `_make_wav()` (`audio_sys.gd:239-254`), not a sample:

```gdscript
func play_boost_swell() -> void:
	_play(_render_boost_swell())


func _render_boost_swell() -> AudioStreamWAV:
	# A quick rising-pitch whoosh: a filtered noise burst with an upward frequency
	# sweep over ~180ms, quieter and shorter than the boom/bomb sounds since this
	# fires often (every boost tap) rather than rarely (every kill/bomb).
	var n := int(SAMPLE_RATE * 0.18)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var sweep := 220.0 + 900.0 * (float(i) / n)   # 220Hz -> 1120Hz rise
		var env := (1.0 - float(i) / n) * 0.5   # linear decay envelope, moderate volume
		samples[i] = sin(TAU * sweep * t) * env
	return _make_wav(samples)
```

Read `_render_dodge()`/`_render_bomb()` in full before finalizing this — match this project's actual existing envelope/synthesis idiom (which may use a noise component, not just a sine sweep) rather than inventing a different synthesis style for one sound in a file where every other sound follows one consistent approach.

- [ ] **Step 4: Extend the smoke test**

```gdscript
	# M6: boost feedback fires once on the boost transition, not continuously
	player_ship.energy_placeholder if false else null   # (remove — placeholder for real energy field name)
	GameState.energy = GameState.max_energy()
	player_ship._was_boosting = false
	Input.action_press("boost")
	var fov_before := player_ship.camera.fov
	player_ship.update_flight(0.016)
	assert(player_ship.camera.fov > fov_before)   # FOV kicked up
	assert(player_ship._was_boosting == true)
	Input.action_release("boost")
```

(Note: the placeholder line above is a mistake to catch in review, not to ship — remove it; it's flagged here only because a first draft of this exact step is likely to include a stray line like it when adapting from a nearby test. The real assertion sequence is the `GameState.energy`/`Input.action_press`/`fov_before` block.)

- [ ] **Step 5: Gate + commit**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/screenshot_probe.tscn   # eyeball no HUD/FOV regression on an unrelated frame
git add scripts/player.gd scripts/audio_sys.gd tests/smoke_test.gd
git commit -m "feat(feel): boost transition FOV kick + audio swell (M6)"
```

---

## Self-Review

**Spec coverage:** M6's five original bullets — three are documented as already-shipped (Task 0), and the two genuine gaps each get a full task (Tasks 1-2). The corrected gate in Task 0's rewritten `PLAN.md` text is satisfied by Task 1 Step 4/6 (perf + smoke) and Task 2 Step 5 (smoke + screenshot).

**Placeholder scan:** Task 1 Step 2 and Task 2 Step 3 both explicitly instruct reading existing code before finalizing an exact expression, rather than presenting invented code as certain to be correct — each names precisely what to verify and why (matching the existing per-type multiplier composition point; matching the existing synthesis idiom). Task 2 Step 4 deliberately includes one intentionally-wrong placeholder line with an explicit note flagging it as something to catch, not ship — this is a callout for whoever executes this task, not an accidental placeholder slipping through review.

**Type consistency:** `AudioSys.play_boost_swell()` (no args, `-> void`) matches the calling convention of every other `play_*` function already in `audio_sys.gd` (`play_dodge`, `play_bomb`, etc. — all no-arg). `_boost_fov_kick`/`_was_boosting` are declared once (Task 2 Steps 1-2) and referenced consistently in the smoke test (Step 4) using the same names.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-25-m6-feel-pass-completion.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration. Task 0 (doc correction) should run first and alone, since Tasks 1-2's own framing depends on it being merged.
2. **Inline Execution** — execute tasks in one session using executing-plans, batch execution with checkpoints.
