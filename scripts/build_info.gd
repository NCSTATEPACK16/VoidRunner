extends RefCounted
## Build identity, so a bug report can be tied to a build (PLAN.md M1.4).
##
## `ID` is rewritten by build.sh at export time with the short commit SHA, so a
## Netlify build stamps the exact commit it came from. Local editor runs keep the
## "dev" placeholder — which is itself useful information in a report.
class_name BuildInfo

const ID := "dev"   # always committed as "dev"; stamp_build.sh rewrites it at export
const CHANNEL := "beta"


## The string shown on the start screen and pause overlay.
static func label() -> String:
	return "BUILD %s-%s" % [CHANNEL, ID]
