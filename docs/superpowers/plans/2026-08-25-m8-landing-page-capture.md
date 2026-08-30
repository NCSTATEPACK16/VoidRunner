# M8: Landing Page and Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the deployed site so the root domain serves a static DOS-terminal landing page and the game moves to `/play`, then produce a 30-60 second looping muted capture for the mandatory r/destroymygame submission format.

**Architecture:** Today `build.sh` exports the whole game to `dist/index.html` and Netlify publishes `dist/` as the entire site (`netlify.toml`: `publish = "dist"`) — the root domain *is* the game. This plan changes that in the smallest possible way: the Godot export target moves from `dist/index.html` to `dist/play/index.html` (a one-line change to the existing `--export-release` invocation plus renaming the export preset's output path), and a new static `web/landing/index.html` gets copied into `dist/index.html` by `build.sh` as a plain file copy — not a build step, no bundler, matching the spec's explicit "static HTML, no build step" requirement and this project's existing `stamp_build.sh`-style pattern of small, auditable shell steps inside `build.sh`.

**Tech Stack:** Static HTML/CSS/JS (the landing page — no framework, matching `web/vr_shell.html`'s own plain-JS style), the existing `web/vr_shell.html` template (unchanged except its export destination), bash (`build.sh` changes), and this project's existing `tests/capture_verify.gd` (a rendered, non-headless scripted flythrough) as the starting point for the capture video rather than a new tool.

**Spec:** `../../../../PLAN.md` (parent `RadixRemix/PLAN.md`), Part Two §M8.

## Global Constraints

- Same hard rules as every plan in this repo — no imported assets (the landing page's visuals must be CSS/SVG/canvas, not stock photography or icon packs), never name the source game, MIT-only, child-friendly tone, and specifically: the landing page **extends the retro-terminal visual language the start screen already established** (2026-07-27 session, `scripts/overlays.gd`'s `_build_start()`) rather than inventing a new design language — read that session's actual shipped screen (via the local dev server or `tests/screenshot_probe.tscn`'s `shot_start.png`) before writing any landing-page CSS, so the two surfaces read as one product.
- `build.sh` must stay a Godot-export-plus-copy script, not grow a JS/CSS build pipeline — the spec is explicit ("Static HTML, no build step, so `build.sh` stays untouched" in spirit, though this plan does add one `cp`-level line, which is not what "build step" means in context).
- `netlify.toml`'s existing headers (`Cross-Origin-Opener-Policy`) apply site-wide (`for = "/*"`) already — confirm the landing page doesn't need different headers before adding any (it shouldn't; it has no WASM/threading concerns the game build has).
- Gate: page loads with no console errors, scrolls cleanly at phone width (this is explicitly a mobile-visible page — Reddit traffic is overwhelmingly mobile per this project's own M1 rationale), `/play` still serves the full game unchanged, and the capture is under whatever size r/destroymygame's submission format accepts (verify this limit at posting time in M9, not guessed here).
- Commit per task. Update `PLAN.md`'s M8 row and `CLAUDE.md` §6 at session end.

---

## Task 1: Move the game export to `/play`

**Files:**
- Modify: `build.sh`
- Modify: `export_presets.cfg` (the "Web" preset's export path)
- Test: local export + serve, manual URL check

- [ ] **Step 1: Read the current export path wiring in full**

`build.sh`'s existing line is `"${GODOT}" --headless --export-release "Web" dist/index.html`. `export_presets.cfg` (referenced by the V2.1 Step 5 web-shell work, `html/custom_html_shell` setting already lives there per this project's session log) likely also has path-related settings — read it in full before changing anything, since the custom HTML shell (`web/vr_shell.html`) substitution and the `$GODOT_*` placeholder mechanism (explicitly checked for in every prior session's gate: "0 unsubstituted `$GODOT_` placeholders") must keep working from the new path.

- [ ] **Step 2: Change the export target**

In `build.sh`, change:

```bash
echo "--- Exporting Web build ---"
"${GODOT}" --headless --export-release "Web" dist/index.html
```

to:

```bash
echo "--- Exporting Web build ---"
mkdir -p dist/play
"${GODOT}" --headless --export-release "Web" dist/play/index.html
```

Godot's exporter writes all its companion files (the `.wasm`, `.pck`, the substituted HTML shell, any worker JS) alongside whatever path is given as the export target — confirm this by running the export locally and checking `dist/play/`'s contents match what `dist/` used to contain (same file set, just one directory deeper), rather than assuming.

- [ ] **Step 3: Copy the landing page into place**

Add after the export step, before the final `echo "--- Done"` line:

```bash
echo "--- Copying landing page ---"
cp web/landing/index.html dist/index.html
```

(Task 2 creates `web/landing/index.html`; this step can be written now and will simply have nothing to copy until Task 2 lands — sequence Task 2 before running this end-to-end, or write both in the same session.)

- [ ] **Step 4: Update any hardcoded `/`-relative links inside the game build**

Search the codebase for any place that currently assumes the game is served from the domain root — `feedback.gd`'s form-open logic, any `README.md` play-URL references (already stamped once during M1, per the session log: "README play URL filled"), and `build_info.gd`'s label if it references a URL. Update the README's play link specifically from the bare domain to `<domain>/play`.

- [ ] **Step 5: Local verification**

```bash
godot --headless --import
godot --headless --export-release "Web" dist/play/index.html   # or run build.sh directly if Step 3 is also in place
python3 -m http.server 8765 --directory dist &
```

Open `http://localhost:8765/play/` — confirm the game boots exactly as before (this is a pure path move; nothing about the game's own behavior should differ). Open `http://localhost:8765/` — until Task 2 lands, this will 404 or show nothing; that's expected at this point in the plan.

- [ ] **Step 6: Commit**

```bash
git add build.sh export_presets.cfg README.md
git commit -m "build: move the game export to /play (M8, makes room for the landing page)"
```

---

## Task 2: The landing page itself

**Files:**
- Create: `web/landing/index.html`

**Interfaces:** none — self-contained static HTML/CSS/JS, no GDScript surface.

- [ ] **Step 1: Establish the visual baseline**

Before writing any markup, look at the actual current start screen (`overlays.gd::_build_start()`, verified via a local `dist/play/` serve or `tests/screenshot_probe.tscn`'s `shot_start.png`) and note its concrete visual vocabulary: exact colors (`overlays.gd`'s `BG`/`TITLE_COL`/`TEXT_COL`/`KEY_COL`/`ORANGE_COL` constants, `overlays.gd:16-20`, are the literal hex values to reuse — `TITLE_COL := Color("62ffd0")` etc. — don't eyeball-approximate them, copy the values), the bracket-boxed panel style from the 2026-07-27 retro-terminal restyle (`[ SYSTEM_BACKSTORY.DAT ]`-style framing), and the terminal-prompt CTA button convention (`C:VOID_RUNNER> RUN.EXE`-style copy). The landing page should read as the same product's front door, not a different site that happens to link to it.

- [ ] **Step 2: Write the page structure per the spec's content list**

`PLAN.md` M8 bullet 2 lists: pitch, large play button, controls, requirements, known issues, privacy note, repo link, feedback link. Structure as one scrolling static page (no routing, no JS framework):

```html
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
	<title>VOID RUNNER</title>
	<style>
		/* Reuse overlays.gd's literal palette values — see Step 1 */
		:root {
			--bg: #020308;
			--title: #62ffd0;
			--text: #8fb8cc;
			--key: #ffd34d;
			--orange: #ff9c40;
		}
		* { box-sizing: border-box; }
		body {
			background: var(--bg);
			color: var(--text);
			font-family: 'Courier New', monospace;
			margin: 0;
			padding: 0;
			line-height: 1.5;
		}
		.wrap { max-width: 720px; margin: 0 auto; padding: 24px 16px 64px; }
		h1 {
			color: var(--title);
			font-size: clamp(28px, 6vw, 48px);
			letter-spacing: 2px;
			margin-bottom: 4px;
		}
		.tagline { color: var(--orange); margin-bottom: 24px; }
		.bracket-box {
			border: 1px solid var(--title);
			padding: 16px;
			margin: 16px 0;
			position: relative;
		}
		.bracket-box::before {
			content: attr(data-label);
			position: absolute;
			top: -10px;
			left: 12px;
			background: var(--bg);
			padding: 0 6px;
			color: var(--title);
			font-size: 12px;
			letter-spacing: 1px;
		}
		.play-btn {
			display: block;
			width: 100%;
			max-width: 340px;
			margin: 24px auto;
			padding: 18px;
			background: transparent;
			border: 2px solid var(--key);
			color: var(--key);
			font-family: inherit;
			font-size: 18px;
			text-align: center;
			text-decoration: none;
			letter-spacing: 1px;
		}
		.play-btn:hover, .play-btn:focus { background: var(--key); color: var(--bg); }
		ul { padding-left: 20px; }
		a { color: var(--orange); }
		.footer-links { margin-top: 32px; font-size: 14px; }
	</style>
</head>
<body>
	<div class="wrap">
		<h1>BEYOND THE<br>VOID RUNNER</h1>
		<p class="tagline"><!-- one-line pitch, matching the start screen's tagline tone --></p>

		<a class="play-btn" href="/play/">C:VOID_RUNNER&gt; RUN.EXE</a>

		<div class="bracket-box" data-label="CONTROLS.DAT">
			<!-- arrows/mouse steer, LMB/Space fire, 1-4 weapons, W/RMB boost, S brake,
			     A/D dodge, P plasma bomb, Enter/ESC pause — pull verbatim from the
			     in-game Controls & Guide overlay (overlays.gd::_build_help) rather
			     than re-deriving it, so the two never drift apart -->
		</div>

		<div class="bracket-box" data-label="REQUIREMENTS.DAT">
			<!-- desktop: any modern browser w/ WebGL2. mobile: phones get a real
			     touch build (M4); tablets/others get the desktop controls. -->
		</div>

		<div class="bracket-box" data-label="KNOWN_ISSUES.DAT">
			<!-- pull from the actual current state — do not invent issues, and do
			     not leave this section empty if real ones exist (M4b's un-device-
			     tested status, if still true at time of writing, belongs here) -->
		</div>

		<div class="bracket-box" data-label="PRIVACY.DAT">
			<!-- reuse feedback.gd's existing privacy note text verbatim (M3 already
			     wrote this copy once — don't write a second, possibly-divergent
			     version here) -->
		</div>

		<div class="footer-links">
			<a href="https://github.com/NCSTATEPACK16/VoidRunner">SOURCE</a>
			&nbsp;·&nbsp;
			<a href="#" id="feedback-link">FEEDBACK</a>
		</div>
	</div>
	<script>
		// Feedback link opens the same Tally form feedback.gd uses in-game —
		// hardcode the URL here rather than trying to share GDScript constants
		// across the language boundary; keep both in sync by hand if the form
		// URL ever changes (it hasn't since M3 shipped).
		document.getElementById('feedback-link').href = 'https://tally.so/r/KYrvyk';
	</script>
</body>
</html>
```

Fill every `<!-- -->` placeholder with real copy before this ships — per this plan's "No Placeholders" discipline, the comments above mark *where* content goes and *what source to copy it from* (the in-game help overlay, `feedback.gd`'s privacy note, the actual current M4b/M4d device-testing status), not permission to ship empty sections. Read `overlays.gd::_build_help()` and `feedback.gd`'s privacy-note string in full before filling the CONTROLS.DAT and PRIVACY.DAT boxes so the copy is copied, not re-derived from memory.

- [ ] **Step 3: Mobile-width verification**

This is a static page — verify by actually narrowing a browser window (or real-device testing, same LAN-serve pattern M4 already established) to a phone width (~375px) and confirming no horizontal scroll, the play button stays reachable without excessive scrolling, and text remains legible at the `clamp()`-scaled sizes above.

- [ ] **Step 4: Gate + commit**

```bash
cp web/landing/index.html /tmp/landing-check.html   # or serve dist/ directly per Task 1 Step 5
```

Open in a browser, check the console for errors (there should be none — this page has no external requests beyond the two internal links and the one hardcoded feedback URL), confirm `/play/` link resolves once Task 1 has run.

```bash
git add web/landing/index.html
git commit -m "feat(web): DOS-terminal landing page (M8)"
```

---

## Task 3: The capture video

**Files:**
- Modify or extend: `tests/capture_verify.gd` (already exists — a rendered, non-headless scripted flythrough; read it in full before deciding whether to extend it or write a sibling script)
- Output: a committed or externally-hosted 30-60s muted loop (see Step 4 for where it actually lives)

- [ ] **Step 1: Read `tests/capture_verify.gd` in full**

Its outline (`_ready`, `_dir`, `_fly(game, frames)`, `_run`) suggests it already drives the game through a scripted flythrough for visual verification — this is the closest existing tool to "record 30-60s of gameplay" and should be extended or reused rather than building a second capture mechanism from scratch. Determine exactly what it currently captures (screenshots per frame? a fixed set of key moments?) and at what resolution/rate.

- [ ] **Step 2: Script a 30-60s route that shows the game's best material**

Per the spec: "it should show M7's sprites and M6's feel" — meaning this task should run **after** M6 (feel pass) and M7 (sprite bakes) have shipped, not before, or the capture will need to be redone. Script (or extend `capture_verify.gd`'s existing `_fly()` pattern) a route through: a tunnel stretch showing boost feedback (M6 Task 2) and the dither/lighting pass, at least one combat encounter showing hit-stop/gibs/muzzle-kick (already-shipped L1 work) and, if M7 shipped by this point, a baked boss encounter, and a locked-arena-clear or exit-portal beat for a satisfying loop point.

- [ ] **Step 3: Capture at a resolution suitable for a Reddit video post, not the native 320×200**

The in-game render is intentionally 320×200 with nearest-filter scaling (the DOS-feel rendering profile, a hard constraint per every plan in this repo) — for a *capture video* specifically (not gameplay itself), render at a larger output resolution with the same nearest-neighbor upscale baked in (e.g. capture the already-upscaled window framebuffer, matching what a real player's browser actually displays, rather than the raw 320×200 buffer) so the video doesn't look softer than the actual game. Godot's `--write-movie` CLI flag (headless-compatible video capture, distinct from `--headless`'s screenshot-only mode `capture_verify.gd` may currently use) is the right mechanism if `capture_verify.gd` doesn't already produce video — check its actual output format in Step 1 before assuming a new mechanism is needed.

- [ ] **Step 4: Mute and loop-check**

The spec requires "muted" — either strip audio entirely from the capture output or ensure the export step does (Godot's `--write-movie` captures video only by default unless an audio mixdown is separately requested; confirm which is actually happening rather than assuming). Play the result back on a loop and check the seam between the end and the restart doesn't jar — trim/adjust the route's start/end points if it does.

- [ ] **Step 5: Where the file lives**

This is a large binary asset — do not commit it into the git repo (this project has no precedent for binary media in version control, and a 30-60s video at any reasonable bitrate is not a small file). Two options, pick based on what M8's landing page and M9's Reddit posts actually need: (a) host it via Netlify as a static asset alongside `dist/` (added to `dist/` by `build.sh` as a copy step, same pattern as the landing page in Task 1 Step 3, from a source file kept outside git in a location noted in this repo's own asset-handling convention — check how `reference/originals/` is gitignored-but-locally-present for the closest existing precedent), or (b) upload directly to Reddit at post time (M9) and never host it on the site at all, in which case this task's deliverable is just the rendered file handed to John, not a repo change at all. **Ask John which before finalizing this step** — this is a real product/hosting decision this plan shouldn't guess at silently, unlike the code-level judgment calls in the other plans in this batch which had a clear best-default; this one genuinely depends on where John wants to host video, which this plan has no way to know.

- [ ] **Step 6: Gate + commit (whichever way Step 5 resolves)**

If (a): `git add build.sh` (the new copy step) and note the video file's actual location (outside git) in the commit message and `CLAUDE.md` §6, mirroring how `reference/originals/` is documented as present-but-gitignored. If (b): no repo commit — hand the file to John directly, log the handoff in `CLAUDE.md` §6.

---

## Self-Review

**Spec coverage:** M8 bullet 1 (root=landing, `/play`=game, static, no build step) → Tasks 1-2. M8 bullet 2 (content list) → Task 2 Step 2. M8 bullet 3 (30-60s muted capture) → Task 3. M8's gate (loads with no console errors, scrolls at phone width, `/play` still serves the game, capture under Reddit's size limit) → Task 1 Step 5, Task 2 Steps 3-4, Task 3 Step 4 + M9's actual size-limit check at post time.

**Placeholder scan:** Task 2 Step 2's HTML template uses `<!-- -->` comments to mark *where* real copy goes and *what source to copy it from* — each is a directed instruction (pull from `_build_help()`, pull from `feedback.gd`'s privacy string, do not invent known-issues content), not a vague TODO, and Step 2's own text explicitly says these must be filled before shipping. Task 3 Step 5 explicitly defers to John on a real hosting decision rather than guessing — flagged as fundamentally different from the other plans' judgment calls because this plan has no code-level signal to resolve it from.

**Type consistency:** N/A for this plan — no GDScript interfaces are introduced; the landing page is fully static and the capture tooling extends an existing script rather than defining new ones.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-25-m8-landing-page-capture.md`. Two execution options:

1. **Subagent-Driven (recommended)** — Task 3 specifically should not start until M6 and M7 have actually shipped (per Step 2's own note); sequence it last regardless of which execution mode is chosen.
2. **Inline Execution** — same sequencing caveat applies.
