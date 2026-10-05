# Perf baseline log (V2.1 perf pass)

Probe: `tests/perf_probe.tscn`. Headless = CPU/script cost only (dummy
rasterizer — blind to upload/draw/compile stalls). Rendered = real window,
wall-clock frame deltas, spike threshold 40 ms. All runs `VR_PERF_RAIL=1`.

Commands:

```
VR_PERF_RAIL=1 VR_PERF_LEVEL=7    Godot [--headless] --path . tests/perf_probe.tscn   # L8, 210 rings
VR_PERF_RAIL=1 VR_PERF_LEVEL=8    ...                                                 # L9 boss
VR_PERF_RAIL=1 VR_PERF_GAUNTLET=1 ...                                                 # endless
(rendered adds VR_PERF_RENDERED=1 and drops --headless)
```

## Baseline — 2026-07-12, SHA 76b20ff (branch v2.1-perf-sprites), M-series Mac, Godot 4.7

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| L8 | headless | 6.7 ms | 0 >8 ms | completed ring 203/210 |
| L9 | headless | 1.5 ms | 0 >8 ms | boss killed, level complete |
| Gauntlet | headless | 4.8 ms | 0 >8 ms | streamed to ring 370 |
| L8 | rendered | 210.6 ms | 2 >40 ms | spikes at t=51.0 s (210.6) and t=234.8 s (91.2); `built=` UNCHANGED on both |
| L9 | rendered | 214.2 ms | 2 >40 ms | t=24.3 s (41.2), t=52.0 s (214.2); `built=` unchanged |
| Gauntlet | rendered | 51.2 ms | 1 >40 ms | t=9.5 s (51.2); `built=` unchanged |

Rendered histograms are bimodal (4–6 ms / 10–12 ms — display pacing on this
Mac); full outputs in the session scratchpad (`probe_*_{headless,rendered}.txt`).

## After Step 1 (briefing prebuild, 9e018da)

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| L8 | headless | 2.5 ms | 0 >8 ms | was 6.7 ms — mid-flight builds gone |
| L8 | rendered | 213.8 ms | 3 >40 ms | **`built=209->209` the whole flight — zero mid-flight builds, gate met.** Spikes uncorrelated with game state; the ~t=51 s big one has now fired at t≈51 s in three separate runs (machine-periodic event, not game work) |

## After Step 2 (gauntlet throttle)

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| Gauntlet | headless ×2 | 51.0 / 49.4 ms | 6 / 6 >8 ms | spike rings DIFFER entirely between runs (58/173/314 vs 79/228/343), `built=` constant on every spike ⇒ OS preemption noise (Spotlight was indexing ~1 k new reference PNGs), not game cost. One-chunk-per-frame cap + drained queues verified by smoke asserts |

**Interpretation.** On desktop GL, no spike coincides with a chunk build
(`built=` never changes on a spike frame); the 40–215 ms one-offs are the same
non-repeating environment-noise class documented 2026-07-05 (desktop has a warm
shader cache and cheap buffer uploads). The mid-flight chunk builds that this
pass removes hurt on **single-threaded WebGL**, which this desktop probe cannot
emulate. Therefore the Step 1/2 gates are:

1. **Architectural (deterministic):** after Step 1, `world._built_up_to` must
   never change while PLAYING a finite level — asserted in the smoke test.
2. **Statistical:** spike counts / histograms here must not regress.
3. **Felt:** John's in-browser test on the web export (the binding platform).

## After Step 4 (HUD dirty-cache draw calls + shared enemy-shot cache)

The cockpit was re-emitting the full canopy + console every frame. Now the
static frame (struts, plates, wells) draws once at boot on its own layer, and
each dynamic layer redraws only when its inputs change — threat lamp/blink,
plasma pips, boss HP bar on the canopy; weapon slots, MISL ammo, EVD lamp, TIME
clock, kills on the console. `shot_manager` fills one `eshot_cache`
(`PackedVector3Array`) + a `threat_near` bool inside its existing enemy-shot
loop (which already touches every shot); the HUD threat lamp and the radar both
read those, replacing the fresh `Array[Vector3]` that `enemy_shot_positions()`
allocated on every radar `_draw`. That method is removed.

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| L8 | headless | 2.7 ms | 0 >8 ms | completed ring 203/210 — CPU band unchanged vs Step 1 (2.5 ms) |

Headless can't see the win (it measures `game._process` only; HUD `_draw` and
the per-frame canvas draw-call count live on the render thread). Regression bar
met (sim cost flat, no new script errors); a red-green smoke run confirmed the
removed method: reverting the radar to `enemy_shot_positions()` throws
`Nonexistent function … in base 'ShotManager'` at `radar_display.gd:60` every
frame, and the cache fix clears it. The **felt** gate stays John's in-browser
test — fewer canvas draw calls per frame is a single-threaded-WebGL win, the
same class as the Step 1/2 chunk-build removals.

## 3.0 "Technicolor Void" re-baseline (2026-09-28)

Re-run on `main` after PR #6 merged (sector shader, SpriteForge sprites,
STINGER/SPINNER/MINE, time-sliced music). Godot 4.7-stable headless on a
shared 4-vCPU cloud container, so treat ±1–2 ms as noise. Rendered runs weren't
repeated this pass. The rendered and web checks in
`docs/revamp/2026-09-27-v3-technicolor-revamp.md` §5 still stand.

| Run | Mode | Worst step | Spikes | Notes |
|---|---|---|---|---|
| L8 | headless | 3.5 ms | 0 >8 ms | boot+instantiate 453 ms, briefing 33 ms |
| L9 boss | headless | 3.6 ms | 0 >8 ms | ring 52/58, reaches victory state |
| Gauntlet | headless | 3.8–5.8 ms in 7 of 8 runs | 1 >8 ms in 1 run | one run had a single 8–10 ms step; 7 reruns stayed under 6 ms |

That's within 1 ms of the phase-7 numbers (3.0 / 1.7 / 3.1 ms) on L8 and
the gauntlet. The L9 boss is ~2 ms higher, but still far under the 8 ms spike
bar. Watch the single gauntlet outlier in the in-browser test: if the gauntlet
stutters on iPad, start here.

## Time to first flight (re-audit Step 5, 2026-10-02)

The web build now records `window.vrBoot.firstFlightMs` (ms from page load to the first
controllable frame) and logs it once to the console as `[vr] first flight at N ms`, so a
device test can read it straight off the remote console.

| Where | Title usable | First flight | Notes |
|---|---|---|---|
| Headless Chromium, SwiftShader (software GL), local server | 9.5 s | 14.1 s | inputs pressed as soon as each screen allowed: notice → NEW CAMPAIGN → briefing warm-up → LAUNCH |

Software rendering is the slow end. Most of the 9.5 s is the boot-time sprite bake and the
title's first shader compiles, both GPU work that SwiftShader runs on the CPU. Real-device
figures come from the Step 7 device pass.

## v4 perf groundwork: dense arena and draw calls (2026-10-03)

The probe gains a dense-arena scene and per-layer effect counts. Rendered runs also
read the 3D view's draw calls.

```
VR_PERF_DENSE=1 VR_PERF_LEVEL=7  Godot [--headless] --path . tests/perf_probe.tscn   # dense arena
(rendered adds VR_PERF_RENDERED=1 and drops --headless; it also prints [draw])
```

- **Dense arena:** L8 for 20 s, seeded. The ship holds ring 10 with fire held. Every
  enemy type refills to the 42 cap, a missile flies every second, and a cluster ahead is
  blown every 1.5 s.
- **`[fx]`** (every mode): the most of each effect layer alive at once. Also the most
  effects in one frame, and the bolts' share of that frame. Before batching, every effect
  is its own `Sprite3D`, so that most-in-a-frame figure is also its draw-call cost.
- **`[draw]`** (rendered): the 3D view's draw calls and objects. The HUD canvas isn't
  counted.

**Baseline before batching.** These runs used `main` at 62d4142, on the same shared
4-vCPU container. Rendered runs used xvfb with software GL (llvmpipe), so their frame
times are wall-clock, not device numbers.

| Run | Mode | Worst step | Average | Most effects in a frame (bolts) | Draw calls |
|---|---|---|---|---|---|
| Dense arena | headless | 4.3–5.4 ms | 0.63–0.76 ms | 86–104 (5–6%) | — |
| Dense arena | rendered | 73 ms (2 frames over 40) | 18.6 ms | 88 (17%) | peak 153, average 116 |
| L8 | headless | 3.5 ms | 0.32 ms | 74 (34%) | — |
| L9 boss | headless | 2.1 ms | 0.16 ms | 63 (33%) | — |
| L9 boss | rendered | 44 ms (1 frame over 40) | 15.3 ms | 62 (32%) | peak 78, average 42 |
| Gauntlet | headless | 14.6 ms (1 step) | 0.29 ms | 64 (39%) | — |

- In the dense arena, debris sits at its 48 cap, and smoke and sparks run at about half
  of theirs. Effects are about 90 of the 153 draw calls; the 42 enemies and the level
  geometry make up the rest.
- Bolts are a third of the effects at the busiest moment of every real level. In the dense
  arena they are fewer, because debris and smoke saturate there.
- The gauntlet's single 14.6 ms step came with nothing built or spawned. It is the same
  container noise as before, here on unchanged code.
- The rendered screenshot probe now prints each shot's draw calls too. Baseline: corridor
  49, arena 48, combat 89, threats 61, boss room 18.

**After batching** (`FxBatch`, same container, same commands). Rendered numbers come from
an A/B: the baseline commit and the batched build ran alternately, two rounds each, so both
saw the same container load.

| Run | Mode | Before | After |
|---|---|---|---|
| Dense arena | rendered, draw calls (peak / average) | 166–204 / 117–118 | **78–86 / 68–72** |
| Dense arena | rendered, average frame | 20.6–22.0 ms | **19.3–19.9 ms** |
| L9 boss | rendered, draw calls (peak / average) | 77–78 / 43–44 | **42–43 / 31** |
| L9 boss | rendered, average frame (worst) | 16.7–17.4 ms (52–83 ms) | **16.3–17.0 ms (32 ms)** |
| Dense arena | headless, worst / average step | 4.3–5.4 / 0.63–0.76 ms | 1.8–2.2 / 0.65–0.74 ms |
| L8 | headless, worst / average step | 3.5 / 0.32 ms | 2.7–5.4 / 0.40–0.44 ms |
| L9 boss | headless, worst / average step | 2.1 / 0.16 ms | 2.6 / 0.18 ms |
| Gauntlet | headless, worst / average step | 14.6 / 0.29 ms | 3.5–8.0 / 0.33–0.37 ms |

- Every effect layer costs one draw call while anything in it is alive, and none when it is
  empty: at most 7 (player bolts, enemy bolts, fireballs, shock rings, smoke, sparks and
  debris). The dense arena drew more effects after (106 in a frame) than before (88), and
  still used half the calls.
- In the A/B, every rendered run was a little faster batched, and none was slower. On the
  L9 boss, no frame went over 40 ms.
- Script time per step rose by up to 0.1 ms headless. The layers are rebuilt in GDScript
  each frame, and headless runs can't see the per-sprite node and mesh updates that
  batching removed; the rendered frames show the net.
- Behaviour is unchanged. The seeded dense runs land on the same two per-layer outcomes
  before and after (86 or 104 effects in a frame).
- One L8 run had a 23 ms step that came with nothing built or spawned. Two reruns stayed
  at 5.4 ms or below.
- Software GL is not a device. The draw-call savings are aimed at WebGL on iPad, where
  each call costs most, and the Step 7 device pass measures them there.

## v4b: the roster and its bake (2026-10-05)

Measured on a shared 4-vCPU container, xvfb with software GL (llvmpipe), Godot 4.7. Each
figure is 8 runs of `tests/forge_probe.tscn`, dropping the first run's cold-cache outlier
(about 900 ms either way).

**Baseline on `main` (238c78e).** 7 enemies, 3 bosses, 9 pickups.

| Run | Result | Notes |
|---|---|---|
| L8 headless | worst 4.6 ms, average 0.53 ms | 7908 steps |
| L9 boss headless | worst 2.0 ms, average 0.21 ms | boss killed |
| Gauntlet headless | worst 3.9 ms, average 0.41 ms | ring 370 |
| Dense arena headless | worst 2.6 ms, average 0.89 ms | 86 effects in a frame |
| Dense arena rendered | peak 73–74 draw calls, average 65 | average frame 30 ms on this container |
| Sprite bake | 417 ms (349–487) | 3 sheets |

**Commit 1 (parts kit).** Each (model, frame) is built once and duplicated across its 8 angle
cells, so meshes and materials are shared. A sprite class taller than 2048 px splits across
viewports (no class needed it yet).

| Run | Bake (median, range) |
|---|---|
| Sprite bake | 379 ms (337–442), 3 sheets |

About 10% faster on software GL, where rasterizing the cells dominates. The mesh-building
share is larger on a device with a real GPU. The web build now logs the bake (`[vr] sprite
bake N ms gpu=…`) and records it in `window.vrBoot.bakeMs`, so `vrReport()` carries it.
