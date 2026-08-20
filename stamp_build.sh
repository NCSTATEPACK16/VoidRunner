#!/usr/bin/env bash
# Stamps build identity + the feedback/analytics codes into the tree before an
# export. Called by build.sh on Netlify, and run by hand before a local macOS
# export so the two paths can't diverge. Every edit is idempotent — re-running
# rewrites the same assignments rather than consuming them.
set -euo pipefail
cd "$(dirname "$0")"

SHA="${COMMIT_REF:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"
SHA="${SHA:0:7}"
sed -i.bak "s/^const ID := \".*\"$/const ID := \"${SHA}\"/" scripts/build_info.gd
rm -f scripts/build_info.gd.bak

FORM_URL=$(sed -n 's/^static var FORM_URL := "\(.*\)"$/\1/p' scripts/feedback.gd)
GC_CODE=$(sed -n 's/^static var ANALYTICS_CODE := "\(.*\)"$/\1/p' scripts/feedback.gd)
sed -i.bak \
  -e "s|var FORM_URL = '.*';|var FORM_URL = '${FORM_URL}';|" \
  -e "s|var GC_CODE = '.*';|var GC_CODE = '${GC_CODE}';|" \
  web/vr_shell.html
rm -f web/vr_shell.html.bak

echo "stamped: build ${SHA} · analytics ${GC_CODE:-(none)} · form ${FORM_URL:-(none)}"
