# M9: Repo Hygiene, Release Gates, and Staged Posting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The last phase before a public post — scope the repo's public-facing hygiene down to match D7 ("players, not contributors"), run the release gates that have never once been completed (a full 9-sector-plus-gauntlet playthrough, a re-judged 1995-screenshot verdict, cross-browser/device coverage), then post in the staged sequence John already decided (D8).

**Architecture:** This phase is almost entirely verification and light documentation, not new game code — by design. It depends on M4-M8 having shipped (the gates it runs are gates *on* that work), so it must run last. The one piece of "building" is a bug-report issue template and a couple of README/licence sentences; everything else is running the game and reading the result.

**Tech Stack:** GitHub issue templates (Markdown + YAML frontmatter), this project's existing test suite (`tests/smoke_test.tscn`, `tests/perf_probe.tscn`, `tests/screenshot_probe.tscn`), and manual cross-browser/cross-device play.

**Spec:** `../../../../PLAN.md` (parent `RadixRemix/PLAN.md`), Part Two §M9, and §M11 (the kill-criteria list this phase is what actually clears).

## Global Constraints

- Same hard rules as every plan in this repo — no imported assets, never name the source game, MIT-only, child-friendly tone. The bug-report template and README edits in Task 1 are exactly the kind of public-facing text where a slip (naming the source game, an unintentionally non-child-friendly line) would be most visible to exactly the audience M9 is about to invite — proofread against these rules specifically, not just for typos.
- **D7 scope discipline is the organizing constraint of Task 1**: "players, not contributors." No `CONTRIBUTING.md` soliciting pull requests, no "good first issue" labels, no contributor-credit system. The spec is explicit that these are deliberately *not* wanted, not merely deprioritized — do not add them even as a small/minimal version.
- **Never post to r/Doom or r/Descent** — explicit in the spec, and consistent with hard rule #2's whole rationale (posting an original homage into a specific franchise fandom reads as hijacking).
- This phase cannot start meaningfully until M4-M8 are done — Task 3 (the release gates) will produce false or misleading results if run against an incomplete build. If dispatched before those phases ship, the correct action is to say so and stop, not to run the gates anyway and report a result that will need re-running.
- Commit per task (Tasks 1-2 are code/doc commits; Task 3 is verification with a log entry, not a commit unless a bug it finds needs an immediate fix; Task 4 is entirely John's and produces no repo commit at all).

---

## Task 1: Repo hygiene, scoped to D7

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`
- Modify: `README.md`

**Interfaces:** none.

- [ ] **Step 1: Bug-report template asking for exactly what a real bug report needs**

Per the spec: "A bug-report template asking for the version stamp and browser." `scripts/build_info.gd::label()` (already exists, shown on the start screen and pause overlay per the M1 session log) is the version stamp a reporter should copy verbatim — reference it explicitly in the template so reporters know where to find it:

```markdown
---
name: Bug report
about: Report a problem with VOID RUNNER
title: ''
labels: bug
---

**Version stamp** (shown on the start screen and pause menu — copy it exactly):


**Browser + device** (e.g. "Chrome 128 / Windows 11 desktop", "Safari / iPhone 14"):


**What happened:**


**What you expected:**


**Steps to reproduce (if known):**

```

Keep this short — a long form suppresses reports rather than improving them, and this project's own tone (child-friendly, low-friction) argues for brevity here too.

- [ ] **Step 2: README — one honest sentence on scope, plus the M0.1 licence/asset note if not already updated**

Per the spec: "one honest README sentence that the project is not accepting outside code or art but welcomes recommendations." Read the current README in full first (M7's plan already touches its licence/asset section per M0.1 — if M7 ran first, confirm that edit landed before adding this one so they don't conflict). Add a short, plain sentence near wherever contribution/community expectations would naturally go (or a new small section if none exists) — something in the spirit of: *"This is a solo project — I'm not taking outside code or art contributions, but I'd love to hear what you think, and recommendations are always welcome via the feedback link in-game or an issue here."* Do not add a `CONTRIBUTING.md`, do not add issue labels beyond the one `bug` label the template above uses, do not add a code-of-conduct file beyond whatever GitHub's own defaults already provide unprompted.

- [ ] **Step 3: Gate + commit**

No headless/rendered gate applies to Markdown files — the check here is a read-through for tone and factual accuracy (does the version-stamp instruction actually match where `build_info.gd::label()` renders it; does the README sentence accurately describe the project's actual posture).

```bash
git add .github/ISSUE_TEMPLATE/bug_report.md README.md
git commit -m "docs: bug report template + contribution-scope note (M9, D7)"
```

---

## Task 2: The full nine-sector-plus-gauntlet playthrough — the gate that's never been run

**Files:** none (verification only, no code changes unless it finds a bug).

**Interfaces:** none.

- [ ] **Step 1: Confirm this is genuinely running for the first time before starting**

`PLAN.md`'s M11 kill-criterion #5 states plainly: "The full nine-sector run has never been completed once." Cross-check this against `CLAUDE.md` §6's session log for any session claiming a completed 9-sector playthrough (the log has many *partial* verifications — smoke-test-driven, which script through all 9 levels programmatically but are not the same as a real human playing all 9 start-to-finish) — if a genuine human completion has happened since this plan was written and just wasn't logged as clearing this specific criterion, update `PLAN.md`'s M11 list to reflect that rather than re-running unnecessarily. Otherwise, proceed — this is real, never-done verification work.

- [ ] **Step 2: Play the full campaign, sectors 1 through 9, start to finish, in one session or a clearly-tracked multi-session run**

This must be John (per the spec: "John has personally finished the campaign start to end" is M9's literal gate), not a scripted test — the smoke test's programmatic 9-level probe loop already proves the *game* can run through all 9 levels without crashing; it does not prove the *game is fun/fair/completable by a human*, which is the actual thing this gate exists to check. Play on the actual deployed build (post-M4-M8) if by this point in the project timeline it's live, or the local `dist/` export otherwise. Note anything that breaks the flow: a level that feels unfair at its shipped difficulty (cross-check against M5's presets — is Runner, the default, actually beatable by a competent-but-not-expert player?), a boss fight that reads as unfair rather than hard, a UI dead-end.

- [ ] **Step 3: Play a Void Gauntlet (endless mode) session**

Separately from the 9-sector campaign — the Gauntlet (K5) has its own difficulty-tier-per-~720m ramp and has had far less real playtesting than the campaign per the session log's own notes ("gauntlet perf-probe mode + rendered/headless baseline," but no logged extended human session). Play until a real death, note where the difficulty ramp starts feeling unfair versus appropriately hard.

- [ ] **Step 4: Log the result — this is what actually flips M11 kill criterion #5**

Whatever Task 2 finds, log it in `CLAUDE.md` §6 in this project's established style (what was played, what worked, what didn't, any bugs found with enough detail to file as issues via Task 1's new template) and update `PLAN.md`'s M11 list to mark criterion #5 as cleared (with the date). If real problems are found, they are new backlog items, not blockers to logging that the *gate itself* ran — distinguish "the playthrough happened and surfaced N issues" from "the playthrough hasn't happened," since only the latter is what criterion #5 is actually tracking.

- [ ] **Step 5: No automated gate applies — this task's gate is its own completion**

If Task 2 surfaces a bug severe enough to block posting (a hard crash, an uncompletable level), fix it as a small follow-up task before proceeding to Task 4 (posting) — but that fix is its own scoped piece of work with its own commit, not folded into this verification task.

---

## Task 3: 1995-screenshot verdict (re-judged) + cross-browser/device pass

**Files:** none (verification only).

- [ ] **Step 1: Re-run the screenshot gate from `PLAN.md` Phase G, now against the finished build**

Phase G's original gate (already in `PLAN.md` §8): "Take a screenshot of the Godot build and put it next to your reference screenshot... would a 1995 shareware player believe this frame? List the top 3 remaining gaps." This was last run during the K7 prep pass (2026-07-11 session log: `tests/screenshot_probe.tscn` capture with gaps noted — "mid-distance darkness, strip neon-ness, canopy weight — all John taste calls, nothing retuned"). Re-run it now that M6 (feel pass) and M7 (baked sprites, if shipped) have changed what's actually on screen — the prior verdict's specific gaps may be resolved, unchanged, or superseded by new ones.

- [ ] **Step 2: Run `tests/screenshot_probe.tscn` fresh and compare against the last-logged gaps**

```bash
godot --headless --import
godot --headless tests/screenshot_probe.tscn
```

Read the 2026-07-11 session log entry's exact three gaps again, and check each one specifically against the new captures: has M6's boost FOV kick / infighting changed the "mid-distance darkness" read at all (unlikely — that gap was about fog/lighting, out of M6's scope, so probably still open, which is fine — Phase G's own gate language explicitly allows "John taste calls, nothing retuned" as a valid standing verdict, not a blocker); has M7's baked sprites (if shipped) changed the "canopy weight" or overall silhouette read.

- [ ] **Step 3: Cross-browser pass**

Test the deployed (or locally-served `dist/`) build in: Chrome, Firefox, Safari (desktop), and — since M4 shipped real mobile support — Chrome for Android and Safari for iOS. This overlaps directly with M4's own Task 6 (mid-range Android + iPhone checks) — if that task already ran and logged results, this step is a re-confirmation on the *finished* build (post M5-M8) rather than duplicate work; note explicitly in the log which browsers were freshly tested here versus already covered by M4's pass.

- [ ] **Step 4: Log the verdict**

Same pattern as Task 2 Step 4 — write the result into `CLAUDE.md` §6, update `PLAN.md`'s K7 ledger row (still open per the current ledger: "the 1995-screenshot verdict") and M11 criterion #7 ("Any hard freeze, black screen, or silent failure on a mainstream desktop browser") to reflect what this pass actually found.

---

## Task 4: Staged posting (John only, no code)

**Files:** none.

- [ ] **Step 1: Confirm every M11 kill criterion is false**

Before John posts anywhere, re-read `PLAN.md`'s M11 list in full and confirm each of the 7 items is actually resolved (not just "probably fine") — items 1-4 were closed by M1-M3, item 5 by Task 2 above, item 6 by M5's onboarding work, item 7 by Task 3 above. This is a final checklist read, not new work — if any item is still true, stop and say so rather than proceeding to post.

- [ ] **Step 2: r/godot first, with the selfpromo flair**

Per D8's staged order. The post should describe the Blender-MCP sprite-bake pipeline accurately if M7 shipped (per M7's own scheduling note: "a Blender-MCP-scripted, fully reproducible sprite bake pipeline is itself an r/godot-shaped story... the post must describe it accurately") — this is copy John writes, not something this plan drafts on his behalf, but it should be fact-checked against what M7 actually shipped (which subjects were baked, which stayed procedural and why) rather than describing aspirational scope.

- [ ] **Step 3: Fix the top issues raised, then r/destroymygame with the video** (M8 Task 3's deliverable) roughly a week later, per D8's pacing.

- [ ] **Step 4: Fix again, then r/playmygame.**

- [ ] **Step 5: Never r/Doom or r/Descent** — restated here because it's the one rule in this task with real consequence if forgotten in the moment of "just one more sub."

This task has no automated gate and no commit — it is entirely John's execution, informed by M12's parallel-track community standing (which should already be underway independent of this plan, per `PLAN.md` §M12's own "starts immediately, John only" framing).

---

## Self-Review

**Spec coverage:** M9 bullet 1 (hygiene, D7-scoped) → Task 1. M9 bullet 2 (the gates — full playthrough, screenshot verdict, cross-browser/device) → Tasks 2-3. M9 bullet 3 (staged posting) → Task 4. M9's own gate ("every kill criterion in `docs/beta/beta-sequence.html` is false, and John has personally finished the campaign start to end") → Task 4 Step 1 + Task 2.

**Placeholder scan:** Task 1's template and README sentence are fully written, not sketched. Tasks 2-3 are verification tasks with no code to place a placeholder in — their "steps" are legitimately "go play the game and write down what happened," which is the correct shape for this kind of task, not a placeholder standing in for undone design work.

**Type consistency:** N/A — no code interfaces in this plan.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-25-m9-hygiene-gates-posting.md`. Two execution options:

1. **Subagent-Driven** — Task 1 (hygiene) is genuinely delegable to a fresh subagent. Tasks 2-4 are not — they require John playing the game and making judgment calls a subagent cannot make on his behalf.
2. **Inline Execution** — same split applies; Task 1 can run inline in any session, Tasks 2-4 are scheduling/calendar items for John more than "execution" in the usual sense.

**This plan must run last** among all six plans in this batch (M4c/M4d, M5, M6, M7, M8, M9) — its gates are gates on their combined output.
