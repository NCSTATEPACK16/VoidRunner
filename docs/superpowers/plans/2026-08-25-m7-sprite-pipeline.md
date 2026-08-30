# M7: Baked Sprite Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the procedurally-drawn player ship, then the three bosses, then (only if needed) the hulk and turret, with Blender-modeled, MCP-scripted, multi-angle-baked sprites — run in priority order per `PLAN.md`'s M7, each subject shipping only if it demonstrably reads better than its procedural equivalent at fog distance, in-engine.

**Architecture:** Every enemy/boss sprite in this project already funnels through one narrow interface: a `static func X_frames() -> Array[ImageTexture]` in `scripts/sprite_gen.gd` that `EnemyManager`/`ShotManager` calls once at warm-up and caches (`enemy_manager.gd::warmup_textures()`, `shot_manager.gd::warmup_textures()`). A baked sprite is a drop-in replacement at exactly that seam: a new loader function with the identical `-> Array[ImageTexture]` signature, reading a pre-baked, palette-quantized spritesheet resource instead of drawing pixels at runtime. Nothing above that seam (billboarding via `make_sprite()`, animation frame indexing, hit detection, HP-gated boss phases) changes. Each subject's *generation* (Blender + MCP) happens once, offline, and its *output* (a committed spritesheet + the loader function) is what ships — the Blender scripts themselves are committed too, per M0.2, so the pipeline is reproducible.

**Tech Stack:** GDScript (Godot 4.7) for the loader/integration side; Blender + `mcp__blender__*` MCP tools, scripted rather than hand-modeled, for the generation side; an external image model (Gemini or equivalent) for look-development concept art only — never for shippable pixels.

**Spec:** `../../../../PLAN.md` (parent `RadixRemix/PLAN.md`), Part Two §M0.1 (the hard-rule-#1 wording change, gating this entire plan), §M0.2 (the six-step pipeline), and §M7 (priority order + gate).

## Global Constraints

- **M0.1's rule change must land in the same commit as the first baked sprite** — not before. Three files change together: `void-runner-godot/CLAUDE.md` hard rule #1, the parent `../../../../CLAUDE.md` §4 constraint 1, and the README's licence/asset note. The exact replacement text is already written in `PLAN.md` §M0.1 — copy it verbatim, don't rephrase it. Until Task 1's first commit, the *old* rule is still literally true and must not be violated by anything committed earlier in this plan (concept art, Blender scripts, and turnaround renders can exist as local/uncommitted working files during development — see Task 1 Step 1's note on this).
- **Never "in the style of" the specific source game** in any concept prompt, Blender script comment, or asset filename — hard rule #2, unchanged and absolute. Concept prompts target *era and genre traits* (chunky low-res, hard flat lighting, limited palette, billboard-safe symmetry), never a named work.
- **A bake only ships if it reads better than the procedural version at fog distance, in-engine** — this is M7's own gate, repeated per-subject in this plan. A subject that doesn't clear this bar stays procedural; that's a legitimate, expected outcome for some subjects (the spec itself says "if their silhouettes don't read at fog distance" for the hulk/turret, implying they might already be fine).
- **Export size discipline**: M7's gate caps the total export size increase at under 1 MB. Track `dist/` size before and after each subject; a quantized, palette-indexed sheet at sprite resolution should cost single-digit kilobytes per subject (the spec's own estimate) — if any subject's sheet is disproportionately large, that's a compression/format problem to fix before shipping it, not a budget to spend.
- **Design intent (John, per PLAN.md M0.2):** imitate the era, land somewhere distinct — one or two deliberate departures per subject (silhouette language, a signature color, a structural motif), not maximum period fidelity.
- Gate discipline (same as every other plan in this repo): headless `--import`, headless `tests/smoke_test.tscn` (zero `SCRIPT ERROR`), rendered `tests/screenshot_probe.tscn` eyeballed at fog distance specifically, clean `Web` export with a size diff check.
- Commit per subject (not per micro-step — a Blender bake-and-verify cycle is one coherent unit of work, unlike the code-only plans in this batch). Update `PLAN.md`'s M7 row and `CLAUDE.md` §6 after each subject ships or is rejected.

---

## Task 1: Player ship — the pipeline's first run, priority #1 per M0.2

**Files:**
- Create: `blender/gen_player_ship.py` (Blender MCP script, committed)
- Create: `assets/baked/player_ship.png` (quantized spritesheet, committed)
- Create: `scripts/sprite_gen_baked.gd` (new file — see Step 5 for why this is separate from `sprite_gen.gd` rather than added inline)
- Modify: `scripts/sprite_gen.gd` (only the one call site that currently draws the player ship, if one exists — read first, see Step 6)
- Modify: `void-runner-godot/CLAUDE.md`, `../../../../CLAUDE.md`, `README.md` (M0.1's rule change, this commit only)
- Test: `tests/smoke_test.tscn`, `tests/screenshot_probe.tscn`

- [ ] **Step 1: Confirm the player ship is actually procedurally drawn today, and find where**

`sprite_gen.gd`'s outline (already surveyed for this plan's reconnaissance) lists `drone_frames`, `weaver_frames`, `hulk_frames`, `turret_frames`, `boss_frames`, plus non-enemy textures (`star_texture`, `bolt_texture`, `missile_texture`, `pickup_texture`, `prop_texture`, `explosion_frames`, `gib_frames`) — **no `player_ship` or `cockpit` function**. Before writing any Blender script, search the codebase for how the player's own visual presence is currently rendered: this is a first-person flight game (per `PLAN.md` Phase G4, the "cockpit/console" is a 2D HUD overlay, not a 3D-modeled ship the camera sees from outside) — confirm whether "the player ship" for M7's purposes means (a) a genuinely unmodeled entity because the camera is first-person and there's nothing to bake, or (b) the cockpit console's HUD art (currently `Control`-drawn StyleBoxes/Labels per `hud.gd`, not a sprite), or (c) something visible in third-person contexts this project doesn't currently have. **This is a real open question this plan cannot resolve from static analysis alone — resolve it before writing Step 2**, and if the answer is (a), redirect this task's priority-#1 slot to whichever subject the resolved scope actually implies (most likely: promote the three bosses to priority #1, since M7's own text lists them as priority #2 specifically because the player ship was assumed to need it more — re-read `PLAN.md` M7's exact wording once this is resolved and update the ledger accordingly rather than silently reordering).

- [ ] **Step 2: Concept prompt (once Step 1 resolves what's actually being modeled)**

Write a concept prompt targeting era/genre traits only, per M0.2's rule: chunky low-resolution silhouette, hard flat lighting (no soft global illumination — this era didn't have it), a limited palette matching `scripts/palette.gd`'s existing `ALL` array (already the single source of truth for every color in this project — the concept art should be judged against it, not a freely-chosen palette), and a silhouette that reads at billboard/fog distance. Include the one-or-two deliberate departures John's design intent calls for. Generate concept art via an image model for human look-development judgment only — this step produces nothing that ships.

- [ ] **Step 3: Model in Blender via MCP, scripted**

Use the `mcp__blender__*` tools to build the model programmatically (not hand-modeled in the Blender UI) so the result is reproducible as committed Python rather than a binary `.blend`. Save the script as `blender/gen_player_ship.py`. Keep the polycount and material count low — this is a billboard sprite source, not a real-time 3D asset; detail beyond what a 32×32 or 64×64 render can resolve is wasted modeling time.

- [ ] **Step 4: Render the 16-angle turnaround + pain/death frames**

Render at the target sprite resolution (match `sprite_gen.gd`'s existing convention — enemies are 32×32, the boss is 64×64; pick based on how large this subject appears on-screen relative to those) across 16 evenly-spaced yaw angles (matching how Sprite3D billboarding needs to look correct from any camera angle the player can approach from), plus the pain/hit-flash and death/explosion frame variants the existing `flash: bool` parameter convention already expects other sprite functions to provide (see `_draw_drone(frame, flash)` etc. in `sprite_gen.gd` for the exact frame-variant contract to match).

- [ ] **Step 5: Quantize to `palette.gd` and pack the sheet**

Post-process every rendered frame through `Palette.nearest(color)` (`scripts/palette.gd:62-70`, already exists — this is the exact function every procedural sprite already implicitly respects by construction, since they're hand-drawn with `ALL` colors directly) so the baked art can't introduce off-palette colors that would break the DOS-VGA-feel discipline the rest of the project maintains. Pack the quantized frames into one `assets/baked/player_ship.png` spritesheet (a grid, e.g. 16 columns × N rows for angle × frame-variant) plus a small companion `.tres` or hardcoded frame-rect table.

Create `scripts/sprite_gen_baked.gd` as a **separate file** from `sprite_gen.gd` (not added inline) because it has a fundamentally different loading mechanism — procedural functions in `sprite_gen.gd` draw pixels at call time; baked loaders in this new file slice a pre-existing `Image` loaded from `res://assets/baked/*.png`. Keeping them apart means a reader can tell at a glance which sprites are procedural and which are baked without reading every function body — this follows this project's own "follow established patterns... split by responsibility" convention, and `sprite_gen.gd` is already a large multi-subject file where adding a structurally different loading mechanism inline would blur that boundary.

```gdscript
class_name SpriteGenBaked
extends RefCounted
## M7: baked-sprite loaders. Same Array[ImageTexture] contract as sprite_gen.gd's
## procedural functions — this is a drop-in swap at the warmup_textures() call
## site, nothing downstream (billboarding, hit detection, boss phases) changes.
## Every subject here started as a Blender MCP script (blender/gen_*.py, committed)
## baked to assets/baked/*.png and quantized to palette.gd's ALL array.

const PLAYER_SHEET := preload("res://assets/baked/player_ship.png")
const PLAYER_FRAME_SIZE := 64   # match Step 4's chosen resolution
const PLAYER_ANGLES := 16


static func player_ship_frames() -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	var img := PLAYER_SHEET.get_image()
	for col in PLAYER_ANGLES:
		var frame := img.get_region(Rect2i(col * PLAYER_FRAME_SIZE, 0, PLAYER_FRAME_SIZE, PLAYER_FRAME_SIZE))
		frames.append(ImageTexture.create_from_image(frame))
	return frames
```

(Adjust the sheet layout constants to whatever Step 4/5 actually produced — this is a template for the loading pattern, not a guess at final numbers.)

- [ ] **Step 6: Wire the swap at the warmup call site**

Find wherever `sprite_gen.gd`'s frame functions are currently called from `enemy_manager.gd::warmup_textures()`/`spawn()` or the equivalent player-ship render path resolved in Step 1, and swap the call from `SpriteGen.X_frames()` to `SpriteGenBaked.player_ship_frames()`. This should be a one-line change per call site if the seam is as narrow as the Architecture section claims — if it isn't (e.g. if angle selection logic is currently baked into billboard rotation rather than a discrete frame array), that's a real finding to note rather than paper over, since it changes how many frames this bake actually needs.

- [ ] **Step 7: M0.1's rule change — same commit as this first bake**

Update all three files verbatim per `PLAN.md` §M0.1:

`void-runner-godot/CLAUDE.md` hard rule #1, from *"Everything shipped is procedurally generated by code in this repo. No imported assets, ever."* to:

```
Everything shipped is generated from code in this repo — procedurally at runtime,
or baked from a committed generator script. No third-party assets, ever, and
nothing derived from any original 1995 game.
```

Same replacement in the parent `../../../../CLAUDE.md` §4 constraint 1, and an equivalent update to the README's licence/asset note (read the README's current wording first — match its style rather than pasting the CLAUDE.md phrasing verbatim if the README's section reads differently).

- [ ] **Step 8: In-engine fog-distance comparison — the actual ship/no-ship gate**

Before committing, run the game (rendered, not headless) and place the baked subject at the same fog distance the procedural version is normally first visible at (read `game.gd::_build_environment()`'s fog-distance constant, K1/G3 work, to find this value). Screenshot both versions side by side. If the bake doesn't read better, **do not ship it** — revert to the procedural call and note the rejection (with the screenshot comparison) in the commit message and `CLAUDE.md` §6, exactly as M7's gate requires. This is a real possible outcome, not a formality.

- [ ] **Step 9: Gate + commit (only if Step 8 passed)**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/screenshot_probe.tscn
godot --headless --export-release "Web" dist/index.html
du -sh dist/   # confirm the size increase is well under the 1MB total M7 budget
git add blender/gen_player_ship.py assets/baked/player_ship.png scripts/sprite_gen_baked.gd \
  scripts/sprite_gen.gd void-runner-godot/CLAUDE.md ../../../../CLAUDE.md README.md
git commit -m "feat(sprites): bake the player ship via Blender MCP (M7, M0.1 rule change)"
```

---

## Task 2: The three bosses (priority #2)

**Files:**
- Create: `blender/gen_boss_<name>.py` ×3
- Create: `assets/baked/boss_<name>.png` ×3
- Modify: `scripts/sprite_gen_baked.gd` (add `boss_<name>_frames()` per boss)
- Modify: wherever `sprite_gen.gd::boss_frames()` is currently called (`enemy_manager.gd::spawn_boss()`, per its outline)
- Test: `tests/smoke_test.tscn` (boss-room invariants already exist — extend, don't replace), `tests/screenshot_probe.tscn`

- [ ] **Step 1: Confirm today's boss tinting scheme and whether it survives a bake**

`sprite_gen.gd::boss_frames()`'s doc comment (from this plan's reconnaissance) describes "Sentinel-class guardian... broad layered warship hull," and `LevelDef.boss_tint` (`level_def.gd`, `@export var boss_tint := Color(1,1,1)`) suggests the *same* procedural boss geometry is currently tinted differently per boss level (3/6/9) rather than three genuinely distinct models. Confirm this by reading `enemy_manager.gd::spawn_boss()` in full: does it call one `boss_frames()` and apply `boss_tint` as a shader/modulate tint, or does it already select among distinct art per level? This materially changes scope — **if today's three bosses are one model with three tints, M7's "three bosses" priority might mean modeling three genuinely distinct Blender subjects for the first time** (a bigger task than baking an existing distinction), or it might mean this task should ask John whether the tint-only distinction is intentional and should be preserved in the baked version too (bake one model, keep the tint system) rather than assumed to need three separate bakes. **Resolve this before writing Step 2** and note the resolution in the first commit's message.

- [ ] **Step 2: Per-boss concept + Blender + turnaround + quantize + wire**

Repeat Task 1's Steps 2-6 per boss, at 64×64 (matching the existing procedural boss's resolution, `sprite_gen.gd::boss_frames()`), including the phase-gated visual variants if `_update_boss()`'s three HP-gated phases (`enemy_manager.gd:238-292`, already documented in this plan's reconnaissance as "aimed heavy shots → 5-shot fans → 7-shot frenzy + drone summons") currently have any per-phase visual tell in the procedural art (a color shift, an added detail) — if they do, the bake needs matching per-phase frame variants; if the phases are currently gameplay-only with no visual differentiation, that's out of scope for this task (it would be new scope, not a bake of existing behavior) — flag it as a possible separate `PLAN.md` backlog item rather than adding it here unasked.

- [ ] **Step 3: In-engine fog/boss-room-distance comparison per boss**

Same gate as Task 1 Step 8, run in an actual boss room (levels 3/6/9) at the room's real engagement distance (`BOSS_ENGAGE := 200.0`, `enemy_manager.gd:25` — already the constant that governs when the boss actually becomes active/visible in play) rather than the tunnel-enemy fog distance Task 1 used, since boss rooms are lit/staged differently (K1's per-zone lighting mood work).

- [ ] **Step 4: Extend the boss-room smoke invariants**

`tests/smoke_test.gd`'s existing boss-room probe loop (already documented in this plan's reconnaissance: `is_boss` branch asserting `path.arenas.size() == 1`, `level.boss_hp > 0`, etc.) and `tests/boss_path_probe.gd` (a dedicated file already in `tests/`) are the right places to add a frame-count/texture-load assertion per boss if the bake changes how many frames `spawn_boss()` expects to find — read both files before deciding whether new assertions are needed or whether the existing structural checks already cover a baked swap for free (likely: they check PathGen/room geometry, not sprite content, so a new assertion confirming `SpriteGenBaked.boss_X_frames().size() > 0` for each boss level's `boss_name` is probably the actual gap).

- [ ] **Step 5: Gate + commit (per boss, or all three together if Step 1's resolution makes them one unit of work)**

```bash
godot --headless --import
godot --headless tests/smoke_test.tscn
godot --headless tests/screenshot_probe.tscn
godot --headless --export-release "Web" dist/index.html
git add blender/gen_boss_*.py assets/baked/boss_*.png scripts/sprite_gen_baked.gd scripts/enemy_manager.gd tests/smoke_test.gd
git commit -m "feat(sprites): bake the three bosses via Blender MCP (M7)"
```

---

## Task 3: Hulk and turret — only if their procedural silhouettes don't already read at fog distance

**Files:** same shape as Tasks 1-2, subjects `hulk` and `turret`.

- [ ] **Step 1: Judge the existing procedural versions first, before generating anything**

`PLAN.md`'s own M7 text gates this task on "if their silhouettes don't read at fog distance" — meaning the correct first action is a rendered, in-engine, fog-distance screenshot comparison of the *current procedural* `hulk_frames()`/`turret_frames()` against a legibility bar (can a player at first-encounter distance tell hulk from drone from weaver from turret at a glance?), not an assumption that baking is needed. If both already read clearly, **this task is done with zero Blender work** — record that verdict (with the screenshot) in `CLAUDE.md` §6 and skip to nothing. This is the cheapest possible outcome and a legitimate one.

- [ ] **Step 2 (only if Step 1 finds a real legibility problem): repeat Task 1's Steps 2-9 per subject that failed**

Same pipeline, same gate, same in-engine fog-distance ship/no-ship decision per subject.

- [ ] **Step 3: Gate + commit, or record the no-op verdict**

If Step 1 passed both subjects: `git commit --allow-empty -m "docs: M7 hulk/turret legibility check — both already read at fog distance, no bake needed"` is a legitimate way to mark this task as evaluated-and-closed without inventing work; more consistent with this project's actual convention is to skip the commit and just log the verdict in `CLAUDE.md` §6 and the `PLAN.md` M7 ledger row directly. If Step 2 ran for either subject, gate exactly as Task 2 Step 5.

---

## Self-Review

**Spec coverage:** M0.1's rule change → Task 1 Step 7 (first bake's commit). M0.2's six-step pipeline → Tasks 1-3's Steps 2-6 pattern (concept → image-gen → Blender-MCP → turnaround → quantize → in-engine verify), repeated per subject. M7's priority order (player ship, then bosses, then hulk/turret conditionally) → Task ordering 1/2/3. M7's gate (reads better at fog distance; scripts committed; export size under 1MB; M0.1's doc edits land with the first sprite) → each task's own Step 8/9 (Task 1) or Step 3-5 (Tasks 2-3).

**Placeholder scan:** Task 1 Step 1 and Task 2 Step 1 both explicitly flag a real unresolved scope question (what "the player ship" actually refers to in a first-person game; whether three bosses means three models or one tinted model) rather than guessing an answer and writing code against it — each names the exact investigation to run and what to do with either outcome, and explicitly calls out re-ordering the plan if the resolution demands it. This is the single biggest risk in this plan (more than any other doc in this batch, because M7 is the one phase whose scope depends on visual/creative facts no amount of code-reading alone resolves) and is treated as such rather than smoothed over.

**Type consistency:** `SpriteGenBaked.player_ship_frames()`/`boss_<name>_frames()` all match the `-> Array[ImageTexture]` signature `sprite_gen.gd`'s procedural functions already establish, confirmed against `sprite_gen.gd`'s actual outline (`drone_frames() -> Array[ImageTexture]` etc.) rather than assumed.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-25-m7-sprite-pipeline.md`. Two execution options:

1. **Subagent-Driven (recommended)** — but note this plan is the one in this batch where a subagent's judgment calls (concept art look-dev, the fog-distance ship/no-ship verdict) most need John in the loop, not just a reviewer agent. Treat each task's Step 8/9-equivalent gate as a hard human checkpoint, not something a reviewer subagent can wave through.
2. **Inline Execution** — same caveat applies.

This plan cannot run unattended end-to-end the way the code-only plans in this batch (M4c/M4d, M5, M6) can — it has real look-dev judgment calls at almost every step. Budget accordingly: this is "medium, iterative" per the spec's own words, likely multiple sessions even after this plan exists.
