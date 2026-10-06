# VOID RUNNER v4: the content pass ("more DOS, still 60 fps")

*Plan, 2026-09-30. It slots into the re-audit sequence
(`docs/revamp/2026-09-28-m5-m9-reaudit.md` §4) between Step 6 (M6 feel) and Step 7 (real-device
verification). Steps 3–6 make the game finishable. v4 makes it feel like a full mid-90s DOS
shooter before the public launch in Step 8.*

## Progress (2026-10-05)

| Sub-step | Status |
|---|---|
| v4a palette tricks | Done (PR #11) |
| Perf groundwork | Done (PR #12) |
| v4b part 1: parts kit; LAYER, RAMMER, MENDER, SPLITTER (sectors 3–5) | Done (PR #13) |
| v4b part 2: WRAITH, CRAWLER, WARDEN, CARRIER (sectors 7–8); heavy variants; mini-bosses | Done (PR #14) |
| v4c hubs, keys and objectives | Next, two commits: hubs with keycards and switches; objectives |
| v4d tally, episodes and menu feel | Queued, one commit |

**How v4a landed, and where it differs from the plan below:**
- **Stepped darkness.** The sector shader already cut light into 12 bands, so the missing piece
  was distance.
  - World geometry now darkens in those same bands between the theme's fog start and end
    (`LightRig.set_distance`, called from `game._apply_theme_mood`), instead of through Godot's
    smooth fog. Sprites keep the fog.
  - Full-bright texels never dim below a floor of 0.3, so distant lamps still read.
  - The band count is still one shader default, not set per theme. Tune it after a playtest.
- **Colour cycling.** Each material gets its own `cycle_speed`. A reserved hue would not work,
  because the wall textures are mipmapped and a per-texel marker would smear into its neighbours.
  - `TextureGen.CYCLE` picks the surfaces for each motif:
    - console screens and pipe trims in panel sectors;
    - lava cracks in rock;
    - glowing pods and ceiling sacs in organic;
    - lit walls and coolant pipes in ice;
    - runes and trims in rune sectors.
  - The force-field doors cycle too.
  - A brightness crest runs through the glowing texels, driven by the shader's `TIME`, so there is
    no per-frame uniform write at all.
  - The portal already animated in its own shader.
- **Whole-screen flashes.** They go through one HUD overlay (`Hud.flash_tint`), not a new uniform
  in the palette pass:
  - red on a hit, scaled by the damage;
  - gold on a pickup: stronger for timed powers, faint for salvage;
  - no green: PHASE SHIELD already had a steady cyan glaze;
  - the plasma bomb keeps its own white flash.

  At most one flash starts every 340 ms (under 3 a second), and REDUCE FLASH cuts it to 35%.
  A flash inside that gap is skipped, not stacked; there is no priority order yet. Camera shake
  no longer tints the screen red, so red always means a hit.
- **Explosions and smoke.**
  - The fireball has 14 frames (up from 10) at 0.05 s each. Smoke has 6 (up from 4).
  - Big blasts leave 3 slow smoke puffs that hang for 1.4 s.
  - Hot debris cooling through its ramp moves to perf groundwork: debris gets batched there, and
    the ramp step can then be per-instance data.
- **Cost.** All shader work, except the smoke puffs. They are the one v4a item that adds draw calls:
  up to 3 pooled sprites per big blast for 1.4 s, until `FxBatch` lands.

  Perf probe, 10 headless runs:

  | Run | Worst step |
  |---|---|
  | L8 | 3.1–5.4 ms |
  | L9 boss | 3.4 ms |
  | Gauntlet | 4.9–6.1 ms, plus one borderline 8.3 ms step |

  Two one-off stalls did not reproduce in 3–4 reruns of the same setup, and neither matched a chunk
  build or a spawn. They are this shared container's noise:
  - 123 ms on the level-end step of one L8 run;
  - a 1.3 s cluster of spikes up to 170 ms early in one gauntlet run.
- **A fix on the way:** pickup messages show the difficulty-scaled amount. Step 3 had left them at
  the base +20 and +30.

**How the perf groundwork landed (PR #12, two commits):**
- **Measured first.** `tests/perf_probe.gd` has a dense-arena scene (`VR_PERF_DENSE=1`) and
  per-layer effect counts in every mode. Rendered runs also read the 3D view's draw calls.
  Before batching, the dense arena peaked at 153–204 draw calls, about 90 of them effects.
- **`FxBatch`** (`scripts/fx_batch.gd`) is one `MultiMeshInstance3D` per effect layer.
  - Each layer's frames sit in one atlas strip.
  - The material is a `StandardMaterial3D` in particle-billboard mode, the path
    `CPUParticles3D` uses on WebGL, not a custom shader.
  - There are seven layers: player bolts (every weapon in one atlas), enemy bolts,
    fireballs, shock rings, smoke, sparks and debris.
  - An empty layer hides, so it costs no draw call.
  - Bolts are batched too: they are a third of the effects at the busiest moment of every
    real level.
  - Effects are now plain records in capped arrays, and the `Sprite3D` pool is gone.
- **Hot debris.** Fresh debris glows yellow-hot and cools down the `FIRE` ramp into its hull tint
  over 0.6 s (`GibManager.COOL_T`).
- **Warm-up.** The briefing's warm-up rig shows one instance of every layer, so the batch
  shader variants compile behind the briefing.
- **Parity.** `tests/fx_parity_probe.gd` draws each layer's frame both as a `Sprite3D` and
  through `FxBatch`, then compares them: 0 differing pixels on desktop GL and GLES3. It
  caught a bug the headless tests could not: untinted layers drew nothing at first.
- **Results** (A/B on software GL, `tests/perf_baseline.md`):
  - dense arena: peak draw calls fell to 78–86 and the average from ~117 to ~70;
  - L9 boss: peak draw calls fell from 78 to 42;
  - every rendered run was a little faster, and none slower;
  - script time rose by up to 0.1 ms a step, from rebuilding the layers in GDScript.
- **Still to measure:** the savings are aimed at WebGL on iPad, which the Step 7 device
  pass covers.
- **The biggest group is now enemies.** They are still one `Sprite3D` each (42 at the cap),
  which this plan keeps for now (per-type atlases, see *Performance plan*).

**How v4b part 1 landed (PR #13, two commits).** v4b is split in two PRs: four enemies
for sectors 3–5 here; the other four, the heavy variants and the mini-bosses next.
- **Parts kit** (`SpriteModels`):
  - `taper` makes the wedge hulls, ram plows, carapaces and armour;
  - `fin`, `pod` (the engine pod), `canopy` and `plate`;
  - the greebles: `antenna`, `vents` and `pipe`;
  - `pair` mirrors a part across X;
  - `painted` carries a painted map.

  The "paint sampler" became two studio maps:
  - a greyscale `detail` map, multiplied in;
  - an RGBA `decal` map, laid over.

  `TextureGen.hull_paint` paints panel lines with rivets, vent louvres and hazard stripes.
  Unset, both maps are no-ops.
- **The bake.**
  - Each (model, frame) is built once and duplicated across its 8 angles.
  - A class taller than 2048 px splits across viewports.
  - The bright frame gives the hit flash.
  - The web build logs the bake time.
- **Four enemies, one rule each:**

  | Enemy | Rule | Debut |
  |---|---|---|
  | LAYER | keeps 4 rings (48 u) ahead at up to 24 u/s, faster than cruise but slower than the afterburner; lays a mine behind itself every 2.4 s on straights, at most 3 of its own | L3 entry |
  | RAMMER | a warning tone and a red flare, then a straight charge at 78 u/s; a roll through it (`iframes_t`) shatters it for score, head-on it does 22, a miss wrecks it on the wall | L4 |
  | MENDER | never fires and hangs 40–60 u off; every `MEND_T` (1.6 s) it gives the most damaged non-boss enemy within 28 u +1 HP, up to `max_hp`, with green sparks | L5 |
  | SPLITTER | a slow, tanky chaser that bursts into 3 drones the next frame | L5 |
- **The SPLITTER's brood counts toward `ENEMY_CAP`.** `_kill` reserves only the free slots,
  and the cap check counts the reservations, so nothing spawned in between can take them. In a
  locked arena the brood joins the room's tally, so the bulkhead waits for it too.
- **Solo first contact.** Each `LevelDef.intro_types` newcomer gets one, on fresh sector starts
  only:
  - it waits mid-way along a stretch of plain tunnel (a boss sector's entry tunnel counts);
  - random spawns skip ±8 rings around it;
  - the pools hold the type back before its ring.

  Briefings carry one tip each. The types join every later pool, and gauntlet tiers 2–5.
- **Tests:**
  - the smoke ROSTER block (one check per rule, the intro rule, pools, briefings);
  - a SOAK block: every type runs 10 s beside the ship;
  - `tests/soak_probe.tscn` flies L1–L9 and fails if any type never spawns.
- **Cost.**
  - Bake: 339 → 448 ms (median of 8, A/B with the kit commit on software GL); the 4 kit
    models are busier than 3.0's.
  - Dense arena: peak draw calls 83–87 (gate about 105); headless worst steps at most 5.5 ms.

**How v4b part 2 landed (PR #14, two commits):**
- **Four more enemies, one rule each:**

  | Enemy | Rule | Debut |
  |---|---|---|
  | WRAITH | cloaked it has no blip, no lock and no hit radius (a blast still finds it); it shimmers in with a warning tone, fires a fan of 3, and stays hittable until `WRAITH_SHOW` (1 s) after; under REDUCE FLASH the shimmer is a steady fade up from dark | L7 |
  | CRAWLER | pinned to one wall, creeps along its stretch of tunnel (never through a mouth or a bulkhead) and fires bursts of 3 across it | L7 |
  | WARDEN | a front shield that turns slowly: a hit inside its 55° front arc doing under 3 is absorbed (`hit_enemy(j, dmg, from_dir)`), so NEUTRON, SCATTER and stray bolts bounce off with blue sparks and a ping, while BOLT, flank hits and any blast land | L8 |
  | CARRIER | turns broadside and launches a drone every `LAUNCH_T` (3.5 s), at most 3 of its own, until its first `BAY_HP` (10) of damage blows the bays: a big blast and "CARRIER BAYS DOWN" | L8 |
- **Heavies.** `rammer_hv`, `splitter_hv` and `warden_hv` are `TYPES` rows with a `model` (their
  base type's sprite set, so no new bake rows) and a `tint`, which the ring re-light folds into
  the sector light (`_lit`, generalising the boss tint). More hull, the same rule; the heavy
  splitter still hatches 3 drones. A heavy waits for its base type's intro ring.
- **Mini-bosses.** HAULER (L2, 70 HP), SPORE TENDER (L5, 100) and GATE WARDEN (L8, 140) bake with
  the bosses at 128 px and ride the boss dict (`_boss_dict`, `miniboss` flag):
  - each holds the kill-locked arena nearest mid-sector (`PathGen.mid_arena()`), with that
    room's guards cut to 3; the mini-boss counts toward the room's tally;
  - it sleeps until the ship enters its room (or shoots it), then `miniboss_engaged` brings
    its name, the boss bar (one tick, at 50%), the music and a WARNING line; its radar blip
    waits too;
  - two phases, the second from 50%:

    | Mini-boss | Phase 1 | From 50% |
    |---|---|---|
    | HAULER | aimed shots; mines sown from its tail rack | + escort drones |
    | SPORE TENDER | aimed shots; 6-spore rings; a repair pulse (+1 to each damaged escort within 45 u, every 3 s) | + SPLITTER hatchlings |
    | GATE WARDEN | aimed shots behind the WARDEN shield (it turns at 0.7 rad/s); drones from its bays | the shield fails ("SHIELD DOWN", the hull runs hot) + a spiral hose |
  - its death emits `miniboss_killed`, never `boss_killed`, so the exit is untouched; the
    bulkhead opens with the room's last kill, and that checkpoint's `miniboss_down` keeps it
    down on a resume (`EnemyManager.remove_boss`);
  - only main-boss resupply stations (`refill`) come back at phase changes.
- **The extra angle ring is skipped.** The bake is already 1.58× main's without it (441 →
  699 ms, median of 8, A/B on software GL), past the 1.5× ceiling set for it. A second ring for
  the bosses, mini-bosses and the carrier would add about another boss sheet.
- **Tests:** the smoke ROSTER2 and MINIBOSS blocks (one check per rule, the heavies, the L7 and
  L8 intros, each mini-boss's room, sleep, phases, patterns, bulkhead and checkpoint); the
  SOAK block covers all 18 types; `tests/soak_probe.tscn` also wakes and kills all three
  mini-bosses; the screenshot probe adds `shot_roster2`, `shot_heavies` and `shot_miniboss`.

**Next:** v4c (hubs, keys, switches, objectives) and v4d (tally, episodes, message log, menu
feel), each with the gates in *Order and gates*.

## Why

3.0 got the look right: a 256-colour palette, sector lighting, turntable-baked sprites, a pixel
font and FM audio. Next to the '95 DOS tunnel-shooters this homage draws on, it is still thin in
three places:

1. **Roster.** It has 7 enemy types and 3 bosses; games of the era had 15 to 20 types in several
   size classes.
2. **Structure.** Levels are a tunnel you always move forward through. The era's levels had
   branches, keys and switches, objectives and secrets.
3. **Rituals.** It lacks the stepped darkness, colour cycling, whole-screen flashes, count-up
   intermission tally and episode structure that made those games read as DOS.

## Ground rules

- **Rule 1 stands:** everything is still generated by code. No Blender and no imported art.
  `SpriteForge` is already a turntable pipeline (build a 3D model, render it from 8 angles, bake
  pixel sprites), which is how that era's sprites were made. The limit is `SpriteModels`' small set
  of building blocks, and that is what this plan grows.
- **Rule 2 stands, and it covers design as well as names.** Every enemy, level and screen is our
  own. We aim for the same era, density and rituals, never a redrawn copy of any specific game's
  sprites, levels or layouts. Reference material stays outside the repo.
- **The 60 fps budget is a gate, not a goal.**
  - The worst game step stays under 8 ms in the headless perf probe on L8, the L9 boss and the
    gauntlet.
  - Draw calls in the densest arena must not rise by more than 25% over the 3.0 baseline, measured
    in a rendered probe.
  - Every sub-step below re-runs both before it lands.

## v4a: palette tricks (cheapest, biggest DOS payoff)

All of these are shader lookups or palette writes, so no new lights and no new draw calls.

- **Stepped darkness.** Replace smooth distance darkening with visible bands, the way Doom-era
  games darkened by distance using a table of darker colour ramps. Stepping the light level in
  `shaders/sector.gdshader` before it's applied is enough, because the `PaletteLUT` quantizer
  already snaps the result to `Palette` ramps.
  - Tune the band count per theme.
  - Keep the 8 dynamic lights.
- **Colour cycling.** Animate the colour index of a few texel classes, not the geometry:
  - lava and coolant channels;
  - force-field doors;
  - console screens;
  - the portal.

  The first version uses the existing `uv_scroll` uniform plus a new `cycle_phase` uniform in
  `sector.gdshader`, and `TextureGen` marks cycling texels with a reserved hue. It costs one
  uniform write per frame.
- **Whole-screen flashes.** A tint uniform on the palette pass (`palette_dither.gdshader`):
  - red on a hit;
  - gold on a pickup;
  - green while PHASE SHIELD is active;
  - white for the plasma bomb, which already exists.

  It is capped at 3 flashes per second, dimmed under REDUCE FLASH, and stacks by priority, not
  additively.
- **Sprite explosions and smoke:** more explosion frames from `FxGen`, lingering smoke puffs, and
  hot debris that glows and cools through its colour ramp.

## v4b: the enemy roster

**Richer building blocks in `SpriteModels`:**
- new shapes: wedge hulls, swept fins, engine pods with glowing exhausts, cockpit canopies,
  greeble strips (antennae, vents, pipes), armour plates, and mirrored ("paired") parts;
- painted materials: panel-line and hazard-stripe textures from `TextureGen`, plus emissive vents
  that flash with the hit frame;
- one extra baked angle ring for large ships, if the bake-time measurement allows it
  (see *Performance*).

**New enemies (working names), each with one behaviour players can learn:**

| Enemy | Role | Rule it teaches |
|---|---|---|
| WARDEN | shielded gunship | its front shield soaks shots; flank it or use BOLT |
| SPLITTER | tanky blob | bursts into 3 drones when killed |
| WRAITH | cloaker | flickers into view before it fires |
| LAYER | mine-layer | seeds mines behind itself on long straights |
| CARRIER | slow capital ship | launches drones until its bays are shot out |
| CRAWLER | wall-mounted | creeps along the walls and fires across the tunnel |
| RAMMER | kamikaze | charges straight; a dodge roll through it wins |
| MENDER | support drone | repairs other enemies, so kill it first |

- **Size classes:** a heavier variant (more HP, larger sprite, slower, different colour ramp) for
  three of them, chosen through `LevelDef.enemy_types` weights.
- **Mini-bosses:** one each in sectors 2, 5 and 8, so the long runs between bosses get a centre
  beat. Each is built from the new parts and uses the existing boss health bar and phase plumbing
  in `enemy_manager.gd`.
- **Introduction curve:**
  - at most two new types per sector;
  - each one appears alone first;
  - each gets a one-line briefing tip, the same pattern 3.0 used for STINGER, SPINNER and MINE.

## v4c: level structure (the biggest gap)

The tunnel stays; it becomes the connective tissue between richer rooms. It is built from things
the game already has: arenas and doors, spurs, secrets, the automap and `PathGen` arenas.

- **Hub rooms.** One arena per sector widens into a hub with 2 or 3 exits. One exit continues the
  main path, one leads to a side branch, and an optional one leads to a secret. It is generated by
  `PathGen` as a branch point, the way spurs attach now.
- **Keycards and switches.**
  - The main door out of a hub needs a keycard held in a side branch. A key-coloured light and an
    automap marker show which door it opens.
  - A switch in a branch opens a secret wall elsewhere. The "you hear a door open" moment is the
    reward.
- **One objective per sector**, stated in the briefing, shown on the automap and counted on the
  console. Candidates:
  - destroy the reactor, then escape before the timer runs out;
  - rescue N stranded pods;
  - shut down N generators.
- **Automap:** keys, locked doors, objective markers and unexplored branch mouths.
- **Checkpoints (Step 4) extend** to held keys, switch states and objective progress.

## v4d: rituals and presentation

- **Intermission tally.** Kills, secrets, objective and time count up one line at a time, with an
  FM tick per step and a stamp sound on the rank. Any key skips to the totals.
- **Episodes.** The 9 sectors become 3 episodes of 3:
  - each ends with a boss and an ending-text screen over a still;
  - "EPISODE COMPLETE" leads to the next episode's title card;
  - the sector select groups sectors by episode.
- **Cockpit message log:** the last 3 messages scroll in the console's text strip instead of a
  single line.
- **Menu feel:**
  - a blinking selector glyph;
  - an FM blip on every move and a confirm tone on select;
  - a SETUP screen (sound, controls, display) in the DOS-window style.

## Performance plan (60 fps on single-threaded WebGL)

Pixel cost is trivial at 320×200. The limits are draw calls and script time on the main thread,
especially on iPad.

- **Batch the many-small-things layers.**
  - Shots, gibs, smoke and sparks move from one `Sprite3D` each to one `MultiMeshInstance3D` per
    atlas.
  - The per-instance frame index goes in custom data; a billboard shader picks the atlas cell.
  - Pools stay, and the draw calls for these layers drop to about one each.
- **Enemies stay `Sprite3D`s** (their count is capped by `ENEMY_CAP`). New types reuse per-type
  atlases, so there is still one material per type.
- **Bake budget.**
  - Measure `SpriteForge.bake()` on iPad first (re-audit Step 7).
  - If the bigger roster pushes boot past about 2 s, bake each sector's roster behind its briefing
    (the web warm-up already hides a loading step there) and keep a small shared set baked at boot.
- **Script time.**
  - Enemy AI stays in the flat per-frame loops.
  - The new behaviours use timers and state flags, not per-frame allocation.
  - Nothing new runs a per-enemy raycast.
- **Probes.**
  - Add a dense-arena scene to `tests/perf_probe.gd`: all new types at the spawn cap.
  - Add a draw-call readout (`RenderingServer.get_rendering_info`) to the rendered probe.
  - Log both in `tests/perf_baseline.md` for each sub-step.

## Order and gates

| Sub-step | Depends on | Gate |
|---|---|---|
| v4a palette tricks | 3.0 shaders | perf flat; the flash cap holds; a screenshot review of darkness bands per theme |
| perf groundwork (batched layers + probes) | — | draw calls for shots and gibs about 1 each; smoke test green |
| v4b roster + mini-bosses | the building-block expansion | the soak run spawns every type; each rule reads in a cold playtest; the bake time is measured |
| v4c hubs, keys, objectives | Step 4 checkpoints | every sector is completable from its checkpoint; the automap shows keys and doors |
| v4d tally, episodes, menu feel | — | the full campaign runs end to end in the soak run |

Each sub-step is one PR with the standard gates:
- headless smoke test with zero `SCRIPT ERROR`;
- the perf probe;
- a rendered probe of each new screen;
- a web export booting in headless Chromium.

John playtests between sub-steps.

## Not doing
- Blender or any imported art (rule 1).
- Recreating any specific game's enemies, levels or screens (rule 2).
- Free-roaming 6DOF levels with no tunnel spine: that would be a different game, and the hub
  hybrid gets most of the benefit.
- Higher internal resolution, or more than 8 dynamic lights.
