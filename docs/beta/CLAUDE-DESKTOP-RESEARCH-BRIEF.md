# Claude Desktop research brief — VOID RUNNER beta readiness

**How to use this file:** paste the block under §"THE PROMPT" into Claude Desktop with web search
(and Extended Thinking) enabled. Attach the artifacts listed in §"WHAT TO ATTACH". Everything above
"THE PROMPT" is instructions for *you*, not for Desktop.

---

## WHAT TO ATTACH

Desktop cannot run the game or read the repo, so it needs evidence, not source. Attach:

1. **`docs/beta/BETA-PRD.md`** (the companion file) — the ground-truth state of the build.
2. **6–10 screenshots**, ideally the ones `tests/screenshot_probe.tscn` already produces
   (start, briefing, corridor, arena, boss, automap) — these are the single most valuable input.
3. **A 3–5 minute screen recording** of one full level plus 60 s of Void Gauntlet. Upload to
   YouTube as unlisted and paste the link; Desktop can't watch video, but a link lets *reviewers*
   see it and lets Desktop reason about the beat sheet you narrate.
4. **The live URL:** https://beyondthevoidrunner.netlify.app/
5. **`reference/NOTES.md` §5** (the 1995-screenshot believability gate verdict) and
   **`PROJECT.md` §8** (the playtest checklist) — pasted, not linked.

Do **not** attach `reference/originals/` — the 1995 shareware files stay local, always.

---

## THE PROMPT

> You are acting as a **senior game producer + launch strategist** doing a pre-beta review of a
> browser-playable indie FPS before its first public exposure on Reddit. Use web search
> aggressively — I want current (2026) facts about subreddit rules, launch norms, and player
> expectations, not recalled generalities. Cite sources inline.
>
> **The game:** VOID RUNNER — an original, MIT-licensed, fully open-source homage to 1995 DOS
> tunnel shooters ('95 DOS games / the *Descent* lineage) with a Doom-era look. Built in
> Godot 4.7, exported to HTML5, deployed on Netlify, playable instantly in a browser with no
> download. All art, audio, and levels are generated procedurally by code at runtime — the repo
> contains zero imported art assets. Nine campaign sectors with bosses at 3/6/9, an endless "Void
> Gauntlet" mode, four weapons plus a plasma bomb, a dodge roll, salvage economy with an upgrade
> bay, an automap, destructible props, hazards, secrets, and a persistent records file.
> Attached: a PRD with the full feature inventory and known gaps, plus screenshots.
>
> **My goal:** post it to Reddit for beta feedback, get *useful* feedback rather than silence or a
> pile-on, and give players the feeling of Doom and '95 DOS games in a genuinely modern, exciting, and
> challenging package.
>
> Work through these seven questions in order. Think hard before each. Where you are uncertain,
> say so explicitly rather than guessing.
>
> **1. Reddit go-to-market.** Which specific subreddits are the right venues in 2026 for a free,
> browser-playable, open-source retro FPS? For each candidate (consider at minimum r/godot,
> r/IndieDev, r/indiegames, r/WebGames, r/incremental_games-style niche subs, r/Doom, r/Descent,
> r/DOS_Gaming, r/retrogaming, r/playmygame, r/destroymygame, r/opensourcegames, r/itchio): pull
> the *current* posting rules, self-promotion limits, karma/age gates, required flair, and any
> feedback-thread-only policies. Rank them by expected quality of feedback, not raw traffic. Flag
> any sub where posting this would get me banned or downvoted on sight, and why. Propose a
> **staged posting schedule** (which sub first, how long to wait, what to change between posts).
>
> **2. The post itself.** Write me three complete, ready-to-post drafts — title + body — tuned to
> the three highest-ranked subs. Reddit rewards specificity and candor and punishes marketing
> voice; each draft should lead with the hook that sub actually cares about (r/godot cares about
> the tech and the procedural pipeline; r/destroymygame wants me to invite a beating;
> r/retrogaming cares about the 1995 fidelity). Include what to say about it being open source
> and MIT, and the exact set of links (play / repo / feedback form). Tell me what NOT to say.
>
> **3. Feedback instrumentation.** Search for what indie devs in 2024–2026 actually use to collect
> browser-game beta feedback and what response rates they report. Compare: an in-game feedback
> key that opens a form, a Google/Tally form linked from the post, a GitHub Issues template, a
> Discord, and privacy-respecting web analytics (e.g. Plausible/GoatCounter/Umami self-hosted).
> Recommend a specific stack for a solo dev who wants ~50–200 responses, including **the five to
> seven questions to actually ask** (not more), and whether to add anonymous gameplay telemetry —
> if yes, what events, what consent banner, and what GDPR obligations attach to a Netlify-hosted
> EU-reachable page.
>
> **4. First-ten-minutes audit.** Using only the attached screenshots and PRD, predict where a
> cold Reddit player who has never heard of '95 DOS games will bounce. Be specific about the first 60
> seconds: the loading overlay, the start screen, the briefing wall of text, control discovery,
> and the first enemy encounter. Research current expectations for browser games — acceptable
> time-to-first-input, whether mouse-lock prompts cause abandonment, mobile/tablet traffic share
> from Reddit, and what fraction of Reddit clicks arrive on a phone (this game currently has no
> touch controls — quantify how much of the audience that costs me and whether it is worth
> fixing before or after the beta).
>
> **5. Difficulty and "modern take".** Research how recent well-received retro-FPS revivals
> (e.g. Dusk, Ultrakill, Turbo Overkill, Prodeus, Forgive Me Father, and any Descent-likes such
> as Overload) handle the tension between authentic 1995 difficulty and 2026 player patience.
> What did their reviews and post-mortems say about difficulty curves, checkpointing, and
> onboarding? Then give me concrete recommendations for a nine-sector campaign with bosses at
> 3/6/9: where the difficulty select should live, how many presets, what each preset should
> actually change (enemy HP? fire rate? player shields? checkpoint density?), and how to avoid
> the classic failure of the "easy" mode feeling insulting.
>
> **6. Feel: Doom + '95 DOS games, modernized.** Research and synthesize the specific, *mechanical*
> sources of the Doom feel — weapon kick, hit-stop, enemy pain states and infighting, sprite
> billboarding readability at distance, sound-design layering, movement speed relative to level
> geometry — and separately the '95-DOS-games/Descent-lineage feel of tunnel flight (constant forward
> motion, wall-bounce forgiveness, spatial disorientation and how the good games mitigate it).
> Produce a prioritized list of the ten changes most likely to raise "this feels great" scores in
> beta feedback, each with an estimated implementation size (S/M/L) and the risk it damages the
> retro authenticity.
>
> **7. Open source as a strategy.** Research how open-source games actually attract contributors
> versus just sitting on GitHub. What does a repo need on day one of a public beta — README
> shape, CONTRIBUTING, issue templates, a labelled good-first-issue set, a public roadmap, a code
> of conduct, a license note about assets? Find two or three recent open-source game repos that
> got real outside contributions and identify what they did that most repos don't. Recommend
> whether to accept content contributions (levels, sprites) at all given the project's
> "everything is procedural, nothing imported" constraint, and how to word that constraint so
> contributors don't waste effort.
>
> **Output format.** One document with the seven sections above, each ending in a short
> **"Do this"** block of concrete actions. Then close with:
> - a **two-week pre-beta punch list**, ordered, with each item marked *blocker* / *should* /
>   *nice*, and
> - a **"what would make me say don't post yet"** section — the honest kill criteria.
>
> Do not soften the assessment to be encouraging. I would rather hear that it isn't ready.

---

## AFTER DESKTOP ANSWERS

Bring the output back to Claude Code in this repo. Everything actionable becomes either a GitHub
issue or a line in `PLAN.md`'s ledger — the PRD's §9 punch list is the intended landing zone.
