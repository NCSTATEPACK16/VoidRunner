# VOID RUNNER — Pre-Beta Launch Review

## TL;DR
- **Do not post to Reddit yet.** Of the PRD's own three "beta-ready" bars, only one (infrastructure) is close to met; the two that determine whether the beta *produces signal* — a reachable feedback path and instrumentation to tell "played" from "bounced" — are entirely unbuilt (KNOWN GAPS 3 and 4). Posting now spends your one first-impression on a build that can't measure or capture the reaction.
- **The highest-quality feedback venue is r/destroymygame, but you must lead with a video, not a link, and you should post to r/godot FIRST** because it is the friendliest to an open-source procedural-tech story and forgives rough edges. Rank: r/godot → r/destroymygame → r/playmygame, then niche (r/retrogaming, r/WebGames), with r/Doom and r/Descent as high-risk (off-brand, trademark-adjacent) venues to avoid at launch.
- **Two blockers dwarf all others: no touch-device handling (most Reddit traffic is mobile — Reddit-specific trackers cluster around ~73%, with estimates ranging 62–78%, and the game is unplayable on touch) and no photosensitivity warning (the build white-outs on plasma bombs and has strobe arena lights).** Fix both before any post; they are the difference between "harsh but useful" and "banned/piled-on."

## Key Findings

1. **Reddit skews heavily mobile.** SQ Magazine and Wytlabs both put Reddit at "approximately 73% of all Reddit sessions" on mobile as of 2025; InterTeam Marketing's high end is "78% of traffic coming from mobile"; TechRT's lower estimate is 62–65%. (For context, SOAX/StatCounter put *overall* mobile web traffic at 64.35% globally in July 2025.) A keyboard-mouse-only game with no touch controls and no "desktop required" gate means the majority of your Reddit clickthroughs hit an unplayable page and bounce silently — and, without analytics, you won't even know it happened.

2. **Reddit's self-promotion norm is the 90/10 (a.k.a. 10%) rule and it is enforced by both automod and community.** For every 1 self-promotional post, ~9 should be non-promotional participation. New/low-karma accounts hit karma and age gates (commonly 50–500 karma, 7–30 days) and shadowbans. A "launch-day blast" across many subs is the single fastest way to get flagged.

3. **r/destroymygame requires a video submission** ("All submissions must be videos… No low-effort game projects"). It is small (~11.7k members) but repeatedly cited by devs as the best place for real, harsh, actionable feedback. You cannot post a bare Netlify link there.

4. **r/playmygame (131k) is purpose-built for free playable links** and uses a custom "Make a Post" button and flairs like [PC] (web); it explicitly warns you to read the highlighted posts "or you will risk an immediate Reddit shadowban." Its front page already features procedural, no-asset games (e.g., ".nervk — a procedural horror FPS… every texture, monster, sound and level is generated in code"), which is nearly your exact pitch.

5. **Privacy-first analytics (GoatCounter, Plausible, Umami) can run without a cookie banner** under most EU readings because they set no cookies and store no personal data (legitimate-interest basis, ePrivacy Art. 5(3) not triggered). This lets you satisfy Bar B (measure played-vs-bounced) cheaply and lawfully. Custom event beats ("level started/cleared") are supported.

6. **The retro-FPS revival consensus: keep authentic difficulty but make "easy actually easy" and give many presets.** Prodeus shipped **seven** difficulty tiers running from Ultra Easy to Ultra Hard and lets you change difficulty mid-level; one review (Videogamesgood, 8.5/10) notes "Medium is a more than worthy challenge for a first playthrough." Turbo Overkill's accessibility options (adjustable screen-flash rate, camera shake, FOV, enemy outlines) are the modern baseline. Ultrakill and Dusk are loved but noted as sometimes punishing on default.

7. **Open-source games attract contributors through structure, not by existing.** The biggest draws (Endless Sky's "over 150 people who have submitted code and content," Veloren, Mindustry's 350+ contributors) lean on *content* pipelines (art, missions, translations) — which your "everything procedural, nothing imported" project structurally cannot use. Your transferable levers are: a beginner/good-first-issue label, a CONTRIBUTING.md with a "ping before big changes" norm, crediting contributors in-game, and reframing "content" as *generative code* (new sprite/level generators).

## Details

### 1. Reddit go-to-market

**The governing rule.** Reddit's sitewide anti-spam policy (Content Policy Rule 8 / the 90-10 rule) requires ~90% genuine participation to ~10% self-promotion, and it is enforced by automod, human mods, and downvotes. 2026 guides note Anti-Evil Operations activity has visibly increased and that a launch-day cross-post blast is the fastest route to a shadowban. **Before posting anything, the account should have real history** (comments, help answers in r/godot) and clear the per-sub karma/age gates (commonly 50–500 karma, 7–30 days).

**Candidate venues, ranked by expected feedback quality (not traffic):**

1. **r/godot (~363k)** — *Best first venue.* Cares about tech and the procedural pipeline; the most common flair is "selfpromo (games)," so self-promo is explicitly accommodated with flair. Culture forgives rough betas and rewards a "here's how I did it" writeup. Use the **selfpromo (games)** flair. Note the official Godot *Showcase* (separate from the subreddit) requires 100+ positive reviews and a polished release — you do not qualify for that yet, but the subreddit itself is open.
2. **r/destroymygame (~11.7k)** — *Best for brutal, actionable feedback.* Rules: **video submissions only**, no low-effort projects, "Destroy the game, not the dev." This is an invitation to a beating — exactly what you want, but only once the first 60 seconds are defensible. Post a 30–60s capture; put links in the comment.
3. **r/playmygame (~131k)** — *Best for volume of real plays.* Purpose-built for free playable links; use the custom Make-a-Post flow and the **[PC] (Web)** flair; read the highlighted/onboarding posts to avoid an auto-shadowban. Precedent for procedural no-asset FPS pitches.
4. **r/WebGames (~115k)** — Good fit for "instant, no-download." Check post rules (they differ); feedback tends to be lighter/casual, more "fun?" than "why does it feel wrong."
5. **r/retrogaming** — Cares about 1995 fidelity, but is largely about *playing old games*; self-promo is restricted (often day-limited or removed). Only post if you frame it as a love-letter to the era and confirm current rules; expect nostalgia reactions, not design feedback.
6. **r/opensourcegames** — Small but on-brand for the MIT/open-source angle; low traffic, so treat as a cross-post for the repo, not a feedback engine.
7. **r/itchio** — Low-signal self-promo dumping ground; only useful if you also put the game on itch.

**Flag — avoid at launch (ban/downvote/off-brand risk):**
- **r/Doom, r/Descent** — These are fan communities for specific franchises. Posting an original homage reads as self-promo hijacking a fandom; high downvote risk, and — critically — the project constraints forbid invoking "Radix"/"Descent" branding in a way implying affiliation. A "spiritual successor to Descent" post in r/Descent invites both a rules removal and a trademark-tone problem. Engage there only as a participant, much later, if organic interest appears.
- **r/DOS_Gaming** — Emulation/preservation focus; a modern Godot game is off-topic.
- **r/indiegames, r/IndieDev** — Allowed but noisy; feedback is shallow. Use as later cross-posts, not primary.

**Staged posting schedule:**
- **T-0 (Week 1): r/godot**, flaired selfpromo (games). Lead with the procedural pipeline. Absorb tech feedback, fix the top 3–5 issues.
- **T+4–6 days: r/destroymygame** with a polished 30–60s video incorporating early fixes. Harvest brutal design feedback.
- **T+10–12 days: r/playmygame** for play volume once onboarding and the feedback path are proven.
- **T+2–3 weeks:** one niche cross-post (r/WebGames *or* r/retrogaming) tuned to that sub, only if the prior rounds surfaced no showstoppers.
- Change between posts: rewrite the hook per sub, incorporate the previous round's fixes, and never reuse identical body text (cross-posting identical promo is a flag).

**Do this:** Build 30+ karma of genuine r/godot participation first; post Draft A to r/godot with selfpromo flair; wait for fixes before each subsequent, differently-worded post; never touch r/Descent or r/Doom as a launch venue.

### 2. The post itself

**Cross-cutting rules — what NOT to say:** No marketing voice ("revolutionary," "game-changing," "the best"). Don't call it finished. Don't imply any affiliation with Radix/Descent/Epic — say "inspired by the 1995 DOS tunnel-shooters" and name the *genre*, not the trademark, in the game and repo. Don't ask for upvotes. Don't bury the play link. Don't over-apologize. Disclose it's your project up front.

**How to reference the inspiration safely:** "An original, open-source homage to the mid-90s DOS tunnel-shooter genre (think *Descent*-style 6DOF flight and a *Doom*-era look)" is honest and legal — it references genre and uses the famous titles descriptively/nominatively without claiming endorsement. Do not use "Radix," "Neural Storm," or "Epic MegaGames" anywhere in the post, title, repo, or build, per project constraints.

---

**DRAFT A — r/godot** (flair: selfpromo (games))

**Title:** I built a browser-playable retro tunnel-shooter in Godot 4.7 where every texture, sprite, sound, and level is generated in code — 0 imported art assets. Looking for feedback.

**Body:**
Hey r/godot — VOID RUNNER is an MIT-licensed, open-source FPS homage to mid-90s DOS tunnel-shooters (Descent-style flight, Doom-era look), built entirely in Godot 4.7 and exported to HTML5. It runs instantly in the browser, no download.

The part I most want to talk about: the repo contains **zero imported art**. All sprites, textures, audio (SFX + tracker-style music), and all nine campaign levels are generated procedurally by GDScript at runtime. Some specifics for anyone interested in the tech:
- Ring-model PathGen builds winding tunnels, arenas, and boss chambers with variable floor/ceiling heights and side-spurs.
- Enemy sprites are procedurally billboarded; a palette + Bayer-dither shader does the 320×200 "1995 screenshot" look.
- Web delivery uses a custom shell with a warm-up rig to defeat WebGL shader-compile freezes (launch stall went 132 ms → 5 ms; ~38 MB export). Runs on iPad Safari with threads disabled.

It's an early beta and I'm sure things feel rough — I'd love feedback on the procedural generation and the web export path especially.

- Play (desktop + keyboard/mouse required): https://beyondthevoidrunner.netlify.app/
- Code (MIT): https://github.com/NCSTATEPACK16/VoidRunner
- 2-min feedback form: [link]

Heads-up: keyboard + mouse only right now (no touch), and there's flashing/strobe — a reduce-flashing toggle is in settings.

---

**DRAFT B — r/destroymygame** (video submission required)

**Title:** Destroy my browser FPS: a procedural retro tunnel-shooter. Tell me exactly where the first 60 seconds lose you.

**Body (video is the submission; this goes in the post/comment):**
This is VOID RUNNER — an open-source, browser-playable homage to 90s DOS tunnel-shooters, all art/audio/levels generated in code. Clip is the first sector + a boss.

I don't want praise. I want to know:
- When did you get bored or confused in the first minute?
- Do the weapons feel like they hit anything?
- Does the flight feel good or floaty/disorienting?

Play it yourself if you want to be thorough (desktop + keyboard/mouse): https://beyondthevoidrunner.netlify.app/ — code's MIT: https://github.com/NCSTATEPACK16/VoidRunner — and there's a 2-min form: [link]. Be as harsh as you like.

---

**DRAFT C — r/retrogaming**

**Title:** I made a free, no-download browser shooter that tries to *look* like a 1995 screenshot and *feel* like 2026 — homage to the DOS tunnel-shooter era.

**Body:**
Grew up on the mid-90s DOS 6DOF/tunnel shooters and Doom, and wanted to see if I could recreate that exact feeling — 320×200 chunk, palette clamp, light dying into black, billboarded sprite enemies, a cockpit console framing the view — but with modern onboarding, difficulty options, and accessibility toggles.

It's called VOID RUNNER. Free, open-source (MIT), runs in the browser with no download or account. Everything you see — the textures, the enemy sprites, the music — is generated by code, not ripped from anything; it's an original homage, not a port.

Would love to know from people who were there: does it hit the 1995 note, or does it fall into the uncanny valley of "modern game cosplaying as old"?
- Play (desktop/keyboard + mouse): https://beyondthevoidrunner.netlify.app/
- Source: https://github.com/NCSTATEPACK16/VoidRunner

(Mods — happy to remove if this isn't the right kind of post; checked the rules but tell me if I misread.)

**Do this:** Use Draft A first. Keep all three link sets identical in *destination* but non-identical in *body text*. Never paste "Radix" anywhere.

### 3. Feedback instrumentation

**The stack for a solo dev targeting 50–200 responses:**
- **Analytics: GoatCounter (self-hosted or free non-commercial tier) or Plausible.** Cookieless, no consent banner needed under most EU readings, ~1 KB script. This is the cheapest way to satisfy PRD Bar B and KNOWN GAP 4 — you'll finally distinguish "200 people played" from "200 people opened and closed it." Fire two custom events minimum: `level_started` and `level_cleared` (sector 1), plus `game_loaded` and `feedback_opened`.
- **Qualitative: one linked form (Tally or Google Forms).** Devs overwhelmingly use a simple linked form; it's the path of least resistance and precedent is everywhere. Tally is more privacy-friendly and better-looking (conversational forms report meaningfully higher completion). Link it from: (a) the Reddit post, (b) an in-game **F-key** that opens the form in a new tab, and (c) the game-over and victory screens. This directly closes KNOWN GAP 3.
- **GitHub Issues template** for the technical minority who'll file real bugs — link from the README and the pause screen. Don't expect volume here; it's for quality.
- **Skip Discord for now.** A Discord is a time sink that fragments feedback and looks empty at launch (empty server = negative signal). Add it only if the beta creates demand.

**The 5–7 questions to actually ask (no more):**
1. Where were you when you stopped playing (or did you finish sector 1)? [short text]
2. Did you understand the controls within the first minute? [yes / mostly / no]
3. Did the shooting and flying feel good? [1–5 + optional why]
4. What one thing was most confusing or annoying? [short text]
5. What's one thing you'd tell a friend about it (good or bad)? [short text]
6. Device + browser? [short text — critical for attributing bug reports]
7. (Optional) Anything else? [short text]

**Telemetry & GDPR.** Yes, add anonymous gameplay telemetry, but keep it aggregate and event-based, not personal. Safe events: `game_loaded`, `level_started`, `level_cleared`, `player_died` (+ sector/cause), `feedback_opened`, `session_length_bucket`. **Do not** collect IP-linked identifiers, precise timestamps tied to a user, or anything that could single a person out. Using GoatCounter/Plausible/Umami in default cookieless config, no consent banner is required under most EU DPAs (CNIL exemption criteria; ePrivacy Art. 5(3) not triggered because nothing is stored on the device). GDPR obligations that still attach even to a Netlify-hosted, EU-reachable page: (1) a short **privacy note** on the landing page saying what you collect (aggregate analytics, no cookies, no personal data) and why (legitimate interest); (2) don't send data to non-GDPR-safe third parties; (3) if you ever add anything that stores a device identifier, you cross into consent territory. Germany (TTDSG) and Italy (Garante) are stricter — a one-line disclosure is prudent regardless.

**Do this:** Add GoatCounter + a Tally form, wire the F-key and game-over/victory links, and put a one-line privacy note on the landing page. That single day of work converts the beta from unmeasurable to measurable.

### 4. First-ten-minutes audit

I fetched the live build's shell and the PRD; **I could not perform a full visual/gameplay inspection** (the canvas game state isn't renderable through fetch, and the screenshots weren't attached). Where a visual pass would change the verdict, I say so.

**The first 60 seconds, in order:**
- **Loading overlay (0–?s):** The shell shows "INITIALIZING… compiling shaders — first run is slowest" plus rotating lore ("STARLIGHT STATION — LINK ESTABLISHED," "RIFT ACTIVITY: CLIMBING," "VOID RUNNER, YOU ARE GO FOR LAUNCH"). Good: it *explains itself* and the warm-up rig kills the shader-freeze (Bar A infrastructure is genuinely handled). Risk: on a cold cache with a ~38 MB export on mid mobile/slow desktop, acceptable time-to-first-input is short. Google/DoubleClick's 2016 "The Need for Mobile Speed" report found "53% of visits are likely to be abandoned if pages take longer than 3 seconds to load" (analysis of 10,000+ mobile domains). If shader warm-up pushes perceived load well past a few seconds without a progress signal, some users bounce. **A visual pass on real load times across devices would change this answer** — instrument it.
- **The mobile cliff (biggest single bounce source):** ~73% of Reddit sessions (estimates 62–78%) are mobile. With no touch controls and no detection message, the majority of Reddit visitors reach a page they literally cannot play. Right now that's a silent, uncounted bounce. **This is the highest-leverage fix in the whole audit.** At minimum: detect touch-only devices and show an honest "VOID RUNNER needs a desktop or an iPad with a keyboard" card with the repo link, so mobile users leave informed (and maybe star the repo) instead of confused.
- **Start screen:** Known cosmetic bug — sector `< >` arrows collide with long sector names (GAP 11). On a cold player this reads as "unfinished," coloring everything after. Cheap fix, high perception payoff. There's also no build/version stamp (GAP 9) — bug reports won't be attributable.
- **Briefing wall of text:** Three text bands before every level (GAP 12), unmeasured against cold-player patience. Retro fans tolerate briefings; a Reddit rando does not. Risk: they skim/skip and then don't understand the objective, then bounce in-level blaming "confusing."
- **Control discovery / pointer lock:** Browser FPS need pointer lock, and as of Chrome 130 (Sept 2024) pointer lock requires a user gesture/permission. That's fine (you gate it behind a click), but it means the *first click* must clearly be "click to play/lock." If controls aren't taught in the first 90 seconds (PRD S7 is still a "should," not done), players won't discover boost/dodge. Pointer-lock prompts themselves are standard for web FPS and not a major abandonment driver *if* triggered by an obvious click — the abandonment risk is uncommunicated controls, not the lock itself.
- **First enemy encounter:** If readability ("where did that damage come from?") isn't instant, a cold player reads it as unfair. The PRD lists billboarded drones/weavers/hulks/turrets; without a visual pass I can't judge sprite readability at distance — **this is the single place a screenshot/video would most change my assessment.**

**Verdict:** Bar A is ~80% there on infrastructure but fails on the mobile cliff and the photosensitivity gap. Bar C (defensible first ten minutes) is not met until onboarding (S7), the arrow-collision fix (B8), and briefing trim (N4) land.

**Do this:** Ship touch detection and the "desktop required" card before anything else; add a load-progress signal; run one real cold-load test on a mid-range Android phone and an iPad and record the numbers.

### 5. Difficulty and "modern take"

**What the revivals teach:**
- **Prodeus:** shipped **seven** difficulty tiers (Ultra Easy → Ultra Hard) and lets you change difficulty mid-level; a review (Videogamesgood, 8.5/10) says "Medium is a more than worthy challenge for a first playthrough." Note on checkpoints: reports conflict — some players/reviews call Prodeus's checkpoints sparse and frustrating, while others (e.g., ComingSoon.net) say "checkpoints are forgiving and don't even reset the fight." Treat checkpoint *density* as a deliberate, tunable design lever rather than assuming sparse-is-authentic.
- **Turbo Overkill:** the modern accessibility baseline — adjustable **screen-flash rate, camera shake, FOV (beyond 100), enemy outlines**, wall-run screen-roll toggle. This is the bar 2026 players expect.
- **Ultrakill / Dusk:** beloved but noted as punishing on default; Ultrakill's difficulty sometimes "too high… especially during boss fights or arenas with too little space to dodge." Dusk's own reviewers called Normal "super easy" for some while others got motion-sick — i.e., one curve never fits everyone, which is the argument *for* presets.

**Concrete recommendations for the 9-sector / bosses-at-3-6-9 campaign:**
- **Where it lives:** On the start screen, selectable before sector 1, **defaulting to the middle preset** (PRD S1 already says this — correct). Also make it changeable from the pause menu mid-campaign (Prodeus/TO players expect to dial it down at a wall rather than quit).
- **How many presets: three, named without insult.** Avoid "Easy/Normal/Hard." Use flavor that respects the player, e.g. **RECRUIT / RUNNER / VOIDBORNE**. The classic failure — "easy feels insulting" — is avoided by (a) never labeling it "easy/baby," (b) still awarding score/ranks on the lowest tier, and (c) framing it as *pace* ("more room to learn the flight model"), not *ability*.
- **What each preset actually changes** (change several axes, not just enemy HP):
  - *Recruit:* enemy fire rate −30%, enemy projectile speed −20%, player shields +50%, **checkpoint before every arena and boss phase**, wall-bounce damage halved, missiles more generous.
  - *Runner (default):* the tuned baseline; checkpoint per major arena and at each boss.
  - *Voidborne:* enemy fire rate/HP up, faster projectiles, **checkpoints only at sector start and boss entry**, tighter ammo/heat.
- **Do NOT make the "modern take" only about lowering numbers.** The modern part is *checkpointing that respects a browser session* (a tab close shouldn't nuke a 20-minute run), *readability*, and *onboarding* — those apply to all presets. Given a browser audience that can close the tab in one click, **checkpoint generosity matters more here than on Steam** — err toward more checkpoints than a 1995 purist would.

**Do this:** Ship 3 presets defaulting to middle, changeable from pause; make each change fire rate + projectile speed + shields + checkpoint density (not just HP); keep score/ranks on all tiers.

### 6. Feel: Doom + Radix, modernized

**Mechanical sources of the Doom feel** (from design analyses and the Doom source/wikis):
- **Weapon kick / punch:** muzzle flash, view-kick, and a brief recoil sell impact; guns that feel weak kill everything downstream (PCGamesN's Doom Eternal analysis: bullet-sponge enemies that "no-sell" damage destroy the power fantasy).
- **Hit-stop & enemy pain states:** enemies must visibly *react* — flinch animations, pain frames, knockback. This is the highest-value "feel" lever and is exactly PRD N3.
- **Enemy infighting:** in Doom, monsters retaliate against each other's stray fire (hitscanners like zombiemen/shotgun guys are especially prone, per DoomWiki). This creates emergent spectacle and a breather. A tunnel-shooter can approximate it: let enemy projectiles damage other enemies.
- **Sprite billboarding readability:** billboarded sprites must read at distance and telegraph attacks; damage direction must be instantly legible (Doom's "sound propagation sees you" is a readability tool, not just AI).
- **Sound layering:** distinct fire/impact/death layers; the PRD's 3 phase-aligned music mixes with intensity crossfade is already the modern move.
- **Movement speed vs geometry:** Doom feels fast because the player outpaces the geometry; corridors too tight for your speed feel bad.

**Radix/Descent tunnel-flight feel:**
- **Constant forward motion** with afterburner/brake (you have this) — the joy is threading geometry at speed.
- **Wall-bounce forgiveness:** Descent-likes forgive glancing wall contact; harsh bounce damage punishes exactly the exploratory flying that makes 6DOF fun (you have forgiving wall-bounce — keep it).
- **Spatial disorientation is the genre's central risk.** Overload reviews repeatedly flag that 6DOF is "disorienting and even nauseating (especially at first)." Good games mitigate with: a clear cockpit frame (you have one), an automap/radar (you have both), stable horizon/roll cues, and — critically — a **reduce-screen-roll / comfort option** (Turbo Overkill added exactly this). Motion sickness is a bounce driver for a cold audience.

**Prioritized top-10 changes to raise "this feels great" scores** (size S/M/L; retro-authenticity risk):

1. **Enemy pain states + hit-stop on hit** (M; low risk — this *is* the Doom feel). Highest single feel win.
2. **Weapon kick / view-punch + muzzle flash per weapon** (S–M; low risk). Cheap, huge perceived impact.
3. **Damage-direction indicator** (S; low risk — modern readability, invisible to authenticity). "Always know where damage came from."
4. **Comfort options: reduce screen-roll + reduce-flashing toggle** (S; none — pure addition). Also a blocker for accessibility (see §4).
5. **Hit-confirm feedback: enemy flash + crunchy impact SFX layer** (S–M; low risk). Sells that shots connect.
6. **Sprite readability pass at distance** (M; low–med risk — must preserve chunk). Ensure enemy silhouettes/telegraphs read; risk is over-cleaning the 1995 look.
7. **Enemy infighting (projectiles damage other enemies)** (M; low risk; arguably *increases* authenticity). Emergent spectacle + breathers.
8. **Impact/decal + small screenshake on kills, tied to the shake toggle** (S; low risk). Keep it optional to avoid nausea.
9. **Afterburner/boost feedback (FOV kick + audio swell)** (S; low risk). Makes speed *feel* like speed — core Radix joy.
10. **First-90-seconds teach of fire/boost/dodge via in-world prompts** (M; low risk to authenticity if diegetic; this is PRD S7). Feel is worthless if players never discover the dodge roll.

Note the tension: items 6 and 8 must be *toggleable* because the same juice (flash, shake, roll) that reads as "great feel" to one player reads as "nausea/seizure risk" to another. Default them ON but expose the toggles.

**Do this:** Prioritize items 1–4 for the beta (pain states, weapon kick, damage-direction, comfort toggles). They are the biggest feel wins with the lowest authenticity risk.

### 7. Open source as a strategy

**Repos don't attract contributors by existing — structure does.** Evidence from projects that got real outside contributions:
- **Endless Sky:** the project's own wiki states "there are over 150 people who have submitted code and content to Endless Sky" (repo ~7.2k stars / ~1.2k forks). Its contributor magnet is an explicit **"content" issue label** ("adding new game content… without making code changes"), content-authoring wiki guides, and a plugin architecture — content decisions are framed as "plug-in or pull request." Almost all of that draw is art/writing/missions, i.e., the opposite of your project; the transferable lesson is the *structural* separation of a content track and clear authoring guides.
- **Veloren** (Rust voxel RPG): development on GitLab with a **"beginner" issue tag**, a **#new-contributors** Discord channel that grants direct push access (no fork needed), and a **weekly dev blog that thanks every contributor by handle** — a strong, art-independent motivator. README: "We accept many types of contributions, not only from software developers!" Translations run through a Weblate instance.
- **Mindustry** (350+ contributors): a CONTRIBUTING.md with a "**ping me before big changes**" norm ("first contact me… so I can… make sure you're not wasting your time"), a separate suggestions repo with a "candidate" tag for first-timers, and **credit as incentive** ("If you would like your name to appear in the game's credits, add it… as part of your PR").

**What the repo needs on day one of the beta (all are PRD S3 / GAP 7, currently unbuilt):**
- **README as a landing document** (fixes GAP 6 — it still says "(Netlify URL goes here)"). Shape: one-line hook → animated GIF/WebM → "Play now" link → "What is this" (procedural, MIT homage) → build/run instructions → how to contribute → license/asset note.
- **CONTRIBUTING.md** with a "ping before big features" norm and clear build steps (fetch pinned headless Godot, export).
- **Issue templates** (bug / feature) — the bug template must request the build/version stamp (GAP 9) and browser/device.
- **A labelled good-first-issue set (≥3–5).** This is the single most-cited contributor on-ramp: contributors literally search the "good first issue" label. Seed it with real, small tasks (e.g., "add invert-Y," "FOV slider," "fix arrow/label collision," "add a new palette to the dither shader").
- **A public roadmap** (a pinned issue or a simple ROADMAP.md / GitHub Project).
- **A CODE_OF_CONDUCT.md** (Contributor Covenant is the norm; Godot's own CoC is a fine model).
- **A license/asset note** (see below).

**Should you accept content contributions (levels, sprites)?** Given the non-negotiable "everything procedural, nothing imported" constraint: **No imported art or hand-authored level files — but yes to *generative code*.** The honest reframing that avoids wasted effort:
- **Reject:** imported PNGs/sprites/textures, audio files, hand-placed level geometry, any Blender-authored runtime mesh, and anything copied from GPL projects (Rad-X, Doom source) into the MIT repo.
- **Accept and actively invite:** new **procedural generators** (a new enemy sprite-gen routine, a new palette/dither variant, a new PathGen room type, a new music-gen pattern), gameplay code, bug fixes, accessibility features, and **translations** — the one "content" category you *can* take, and the proven low-skill/high-volume funnel across Mindustry (bundle files), Veloren (Weblate), and Endless Sky.
- **Word the constraint in CONTRIBUTING.md, verbatim suggestion:** *"VOID RUNNER generates 100% of its art, audio, and levels from code at runtime — there are no asset files in this repo, by design. Please do not submit imported images, audio, 3D models, or hand-authored level files; they cannot be merged. The equivalent of 'new content' here is new generator code: a new sprite generator, palette, room archetype, or music routine. See the good-first-issue label for starting points."* This turns your biggest constraint into a clear, unusual contribution brief instead of a wall people hit after doing work.

**Do this:** Before the r/godot post (which will drive the repo's only traffic spike), ship README + CONTRIBUTING + CoC + 3–5 good-first-issues + the asset-constraint note. Credit contributors in-game. Don't stand up a Discord yet.

## Recommendations

**Stage 0 — before ANY Reddit post (blockers):**
1. Ship **touch-device detection** + honest "desktop/keyboard required" card (B2 / GAP 1). Without it you lose the majority of Reddit traffic to silent bounces.
2. Ship the **photosensitivity warning + REDUCE FLASHING toggle** (B3 / GAP 2). Ethics/liability issue and a pile-on risk; note WCAG 2.3.1 defines the "more than three flashes per second" threshold your full-white plasma flash and strobe lights likely exceed.
3. Wire the **in-game feedback path** (F-key form; links on game-over/victory) (B4 / GAP 3).
4. Add **cookieless analytics + `level_started`/`level_cleared` events** (B5 / GAP 4). Without this the beta cannot prove its own success metric (40% sector-1 completion).
5. Add a **build/version stamp** (B6 / GAP 9); fix the **arrow/long-name collision** (B8 / GAP 11); **rewrite the README** with the play URL (B1 / GAP 6).
6. Run the **full 9-sector + gauntlet playtest** end to end (B7 / K7) — this has never been done; do not post an untested campaign.

**Stage 1 — first post (r/godot):** Only after Stage 0. Post Draft A, flaired selfpromo (games). Fix the top 3–5 issues raised.

**Stage 2 — r/destroymygame:** Record a 30–60s capture (S6) after Stage 1 fixes; post Draft B. This also requires the **onboarding pass (S7)** to be done, or the video's first 60 seconds will get destroyed for the wrong reasons.

**Stage 3 — r/playmygame + niche:** Once onboarding, feedback, and analytics are proven and sector-1 completion is trending above 40%.

**Benchmarks that change the plan:**
- If analytics show **sector-1 completion < 25%**, stop expanding; fix onboarding/difficulty before any new sub.
- If **>60% of sessions are <60 seconds**, you have a first-minute problem (load, controls, or mobile bounce) — diagnose before posting further.
- If the **first r/godot post gets removed or piled on**, do not re-post elsewhere; fix and wait.
- Add difficulty presets (S1) before Stage 3 if feedback clusters on "too hard/too confusing."

## Caveats

- **No full visual/gameplay inspection was possible.** I fetched the live shell (loading-overlay text confirmed: "INITIALIZING… compiling shaders — first run is slowest," rotating lore lines) and relied on the PRD as the verified feature inventory, but I could not see the start-screen layout, sprite readability, or the first encounter render. The places this most limits me: sprite readability at distance (§6 item 6), actual cold-load times across devices (§4), and the real severity of the briefing wall (§4). Screenshots or a screen capture would materially change those specific judgments.
- **Reddit rules change and vary; automod is unpredictable.** I've cited the current governing norms (90/10, video-only at r/destroymygame, playmygame's flow) but you must re-read each sidebar the day you post — mods update rules and karma gates without notice. Treat any specific karma/age threshold as indicative, not exact.
- **Mobile-share figures range widely** (62%–78% depending on tracker and definition of "session" vs "traffic"). The conclusion (most Reddit clicks are mobile) is robust; the exact number is not.
- **GDPR guidance here is not legal advice.** The cookieless-analytics-without-a-banner position is the mainstream reading (CNIL exemption, ePrivacy Art. 5(3)) but Germany/Italy are stricter; a one-line privacy disclosure is cheap insurance.
- **Prodeus checkpoint reports conflict** (sparse-and-frustrating vs. forgiving-and-fight-preserving); I've flagged rather than picked a side. Treat checkpoint density as a design decision to test, not a settled best practice.
- **Source quality:** subreddit-rule specifics for smaller subs (r/WebGames, r/retrogaming, r/opensourcegames) are drawn from aggregators and general 2026 self-promo guides rather than a live read of each sidebar, because those exact pages weren't directly retrievable in this pass — verify on the day. Mindustry's exact live contributor count is obscured by GitHub's contributor-graph cap; "350+" is a defensible floor.

---

## Two-Week Pre-Beta Punch List (ordered)

1. **[blocker]** Touch-device detection + "desktop/keyboard required" message (GAP 1/B2).
2. **[blocker]** Photosensitivity first-run warning + REDUCE FLASHING toggle (GAP 2/B3).
3. **[blocker]** In-game feedback path: F-key opens form; links on game-over + victory (GAP 3/B4).
4. **[blocker]** Cookieless analytics (GoatCounter/Plausible) + `level_started`/`level_cleared` events (GAP 4/B5).
5. **[blocker]** Run full 9-sector + gauntlet playtest end-to-end (K7/B7).
6. **[blocker]** README rewrite with live play URL (GAP 6/B1).
7. **[blocker]** Build/version stamp on start + pause (GAP 9/B6).
8. **[should]** Fix start-screen arrow / long-name collision (GAP 11/B8).
9. **[should]** Sector-1 onboarding pass: teach fire/boost/dodge in first 90s without a wall of text (S7).
10. **[should]** 30–60s looping capture (GIF/WebM) for README + r/destroymygame (S6).
11. **[should]** Difficulty select, 3 presets, default middle, changeable from pause (S1).
12. **[should]** Open-source on-ramp: CONTRIBUTING, issue templates, CoC, ≥3 good-first-issues, roadmap, asset-constraint note (S3/GAP 7).
13. **[should]** Trim briefing text density; make skippable (N4/GAP 12).
14. **[nice]** Feel pass: enemy pain states + hit-stop + weapon kick (N3).
15. **[nice]** Comfort: reduce-screen-roll toggle; damage-direction indicator.
16. **[nice]** Invert-Y + FOV slider (S4); key rebinding (N2).
17. **[nice]** Verify gamepad on real hardware (S5/GAP 8).

## What Would Make Me Say "Don't Post Yet" (kill criteria)

- **Any hard freeze, black screen, or silent failure** on a mainstream desktop browser (Chrome/Firefox/Edge/Safari). This violates the PRD's own zero-tolerance Bar A and the user's success criterion; a single such report on Reddit becomes the top comment.
- **No feedback path in the build.** If a player can't get their opinion to you in one click, the beta is feedback-theater — you've spent your first impression to learn nothing. (Currently true → don't post.)
- **No analytics.** If you can't tell 200 plays from 200 bounces, you cannot evaluate the beta against your own 40%/200-session criteria. (Currently true → don't post.)
- **Mobile visitors get a broken canvas with no explanation.** With most Reddit traffic on phones, this guarantees mass silent bounce and some public "doesn't work" comments. (Currently true → don't post.)
- **No photosensitivity warning while the build white-outs and strobes.** This is an ethical and reputational line, not a nicety. (Currently true → don't post.)
- **The full 9-sector + gauntlet run has never been completed once.** If you haven't finished your own game start-to-finish, a Redditor will hit the wall you didn't. (Currently true → don't post.)
- **First 60 seconds not defensible** (onboarding + arrow-collision + briefing): if a cold player can't understand controls and survive sector 1, r/destroymygame will (correctly) destroy it and the feedback won't be about the parts you can fix quickly.

**Bottom line:** Six of these kill criteria are currently true. The build is an impressive piece of engineering with a genuinely novel procedural story, but it is **not ready to post today.** Clear the seven blockers on the punch list (realistically the two-week window), and post to r/godot first — not r/destroymygame, and never to r/Descent.