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

echo "--- Importing project ---"
"${GODOT}" --headless --import

echo "--- Exporting Web build ---"
"${GODOT}" --headless --export-release "Web" dist/index.html

echo "--- Done: $(ls dist) ---"
