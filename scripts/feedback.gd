extends RefCounted
## The beta feedback path and its anonymous counters (PLAN.md M3).
##
## One source of truth for the five questions, so the form, the Reddit post body
## and the in-game prompt can never drift apart — answers stay comparable no
## matter which route a player took to send them.
##
## Both services are free at this project's scale and neither sets a cookie:
##   * Tally  — unlimited forms and submissions on the free plan.
##   * GoatCounter — free for non-commercial use; open source; self-hostable.
## Nothing here is required for the game to run. With both codes left blank the
## build is exactly the game it was before, minus a menu button.
class_name Feedback

## Paste the Tally form's share URL here (https://tally.so/r/XXXXXX).
static var FORM_URL := ""
## Paste the GoatCounter site code here — just the subdomain, e.g. "voidrunner"
## for voidrunner.goatcounter.com. Blank means no analytics script is injected.
static var ANALYTICS_CODE := ""

## The five questions. Short enough that people finish, specific enough that the
## answers are actionable. Ask more and the completion rate is what suffers.
const QUESTIONS := [
	"Where did you stop playing — and did you clear Sector 1?",
	"Did you understand the controls inside the first minute?",
	"Did the flying and the shooting feel good? (1-5, and why)",
	"What was the single most confusing or annoying thing?",
	"What device and browser were you on?",
]

## Counter names. Sector-1 completion rate — the number this whole beta turns on —
## is LEVEL_CLEARED over LEVEL_STARTED for level 1, so these two must always fire
## in pairs and must never carry anything that could identify a person.
const EV_LOADED := "game-loaded"
const EV_LEVEL_STARTED := "level-started"
const EV_LEVEL_CLEARED := "level-cleared"
const EV_FEEDBACK := "feedback-opened"


static func is_configured() -> bool:
	return FORM_URL != ""


## Open the form in a new tab (web) or the system browser (desktop). Counted, so
## the response rate can be read against the number of people who were asked.
static func open_form() -> void:
	if not is_configured():
		return
	count(EV_FEEDBACK)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.vrOpenForm && window.vrOpenForm();", true)
	else:
		OS.shell_open(FORM_URL)


## Fire one anonymous counter. A no-op off the web, and a no-op on the web when
## no code is configured or the script was blocked — never a hard dependency.
static func count(event_name: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.vrCount && window.vrCount(%s);"
		% JSON.stringify(event_name), true)


## Per-level counters carry the sector number only — no scores, no timings, no
## identifiers. "level-started-1" is the whole payload.
static func count_level(event_name: String, level_index: int) -> void:
	count("%s-%d" % [event_name, level_index + 1])
