#!/usr/bin/env bash
# Netlify build script: download headless Godot + matching web export templates,
# then export the project to dist/. Also runs locally on Linux for pipeline debugging
# (on macOS, export with the installed Godot app instead — see README).
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7}"
RELEASE="Godot_v${GODOT_VERSION}-stable"
BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
TEMPLATE_DIR="${HOME}/.local/share/godot/export_templates/${GODOT_VERSION}.stable"

mkdir -p bin dist

if [ ! -x "bin/${RELEASE}_linux.x86_64" ]; then
  echo "--- Downloading Godot ${GODOT_VERSION} (headless Linux) ---"
  curl -fsSL "${BASE_URL}/${RELEASE}_linux.x86_64.zip" -o bin/godot.zip
  unzip -o -q bin/godot.zip -d bin
  chmod +x "bin/${RELEASE}_linux.x86_64"
fi
GODOT="bin/${RELEASE}_linux.x86_64"

if [ ! -f "${TEMPLATE_DIR}/web_nothreads_release.zip" ]; then
  echo "--- Downloading web export templates ---"
  curl -fsSL "${BASE_URL}/${RELEASE}_export_templates.tpz" -o bin/templates.tpz
  mkdir -p "${TEMPLATE_DIR}"
  # The .tpz is a zip with everything under templates/ — we only need the web ones.
  unzip -o -q bin/templates.tpz "templates/web_*" -d bin/tpl
  mv bin/tpl/templates/* "${TEMPLATE_DIR}/"
fi

# M1.4: stamp the commit into the build so a bug report names its build. Netlify
# exposes COMMIT_REF; a plain git checkout falls back to git itself; neither being
# available leaves the committed "dev" placeholder, which is also honest.
SHA="${COMMIT_REF:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"
SHA="${SHA:0:7}"
echo "--- Stamping build ${SHA} ---"
sed -i.bak "s/^const ID := \".*\"$/const ID := \"${SHA}\"/" scripts/build_info.gd
rm -f scripts/build_info.gd.bak

# M3: mirror feedback.gd's codes into the HTML shell, so the two can never drift.
FORM_URL=$(sed -n 's/^static var FORM_URL := "\(.*\)"$/\1/p' scripts/feedback.gd)
GC_CODE=$(sed -n 's/^static var ANALYTICS_CODE := "\(.*\)"$/\1/p' scripts/feedback.gd)
echo "--- Feedback form: ${FORM_URL:-(none)} · analytics: ${GC_CODE:-(none)} ---"
# idempotent: rewrites the assignment, so re-running never eats the target
sed -i.bak \
  -e "s|var FORM_URL = '.*';|var FORM_URL = '${FORM_URL}';|" \
  -e "s|var GC_CODE = '.*';|var GC_CODE = '${GC_CODE}';|" \
  web/vr_shell.html
rm -f web/vr_shell.html.bak

echo "--- Importing project ---"
"${GODOT}" --headless --import

echo "--- Exporting Web build ---"
"${GODOT}" --headless --export-release "Web" dist/index.html

echo "--- Done: $(ls dist) ---"
