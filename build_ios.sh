#!/usr/bin/env bash
# PR D2: the iOS / TestFlight build, in one command. Run it on the Mac:
#
#   ./build_ios.sh            export the Xcode project into build/ios/ and check it
#   ./build_ios.sh archive    ...then archive it with xcodebuild
#   ./build_ios.sh upload     ...then send the archive to TestFlight
#
# Your signing details stay out of the repo. Put them in ios.local.env (gitignored)
# or in the environment:
#
#   VR_IOS_TEAM_ID=ABCDE12345            Apple Developer Team ID (required)
#   VR_IOS_BUNDLE_ID=com.you.voidline  the app's bundle id (required)
#   VR_IOS_VERSION=0.4.0                 marketing version (default: the preset's)
#   VR_IOS_BUILD=123                     build number (default: git commit count)
#   GODOT=/path/to/godot                 Godot 4.7 binary (default: found by itself)
#
# "upload" signs in with the account Xcode is logged in to. To use an App Store
# Connect API key instead, also set VR_ASC_KEY_PATH, VR_ASC_KEY_ID and
# VR_ASC_ISSUER_ID.
#
# On Linux the script stops after the project export and its check (the CI gate):
# archiving needs Xcode. Steps: docs/ios/TESTFLIGHT.md.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-project}"
case "${MODE}" in
  project|archive|upload) ;;
  *) echo "usage: ./build_ios.sh [project|archive|upload]" >&2; exit 2 ;;
esac

if [ -f ios.local.env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./ios.local.env
  set +a
fi

TEAM_ID="${VR_IOS_TEAM_ID:-}"
BUNDLE_ID="${VR_IOS_BUNDLE_ID:-}"
if [ -z "${TEAM_ID}" ] || [ -z "${BUNDLE_ID}" ]; then
  echo "build_ios: set VR_IOS_TEAM_ID and VR_IOS_BUNDLE_ID (in ios.local.env or the" >&2
  echo "environment). See the header of this script." >&2
  exit 2
fi
case "${TEAM_ID}${BUNDLE_ID}" in
  *[!A-Za-z0-9.-]*) echo "build_ios: the Team ID or bundle id has a character Apple doesn't allow" >&2; exit 2 ;;
esac
BUILD_NUMBER="${VR_IOS_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
VERSION="${VR_IOS_VERSION:-$(sed -n 's/^application\/short_version="\(.*\)"$/\1/p' export_presets.cfg)}"

if [ -z "${GODOT:-}" ]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT="godot"
  elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
  elif [ -x "bin/Godot_v4.7-stable_linux.x86_64" ]; then
    GODOT="bin/Godot_v4.7-stable_linux.x86_64"
  else
    echo "build_ios: no Godot found. Set GODOT=/path/to/godot (4.7)." >&2
    exit 2
  fi
fi

./stamp_build.sh

echo "--- Importing project ---"
"${GODOT}" --headless --import

echo "--- Painting app icons and the launch mark ---"
"${GODOT}" --headless tools/make_icons.tscn

# The committed preset carries placeholders. Fill them in for this export only,
# and put the file back however the script ends.
cp export_presets.cfg export_presets.cfg.orig
trap 'mv -f export_presets.cfg.orig export_presets.cfg' EXIT
sed -i.bak \
  -e "s|^application/app_store_team_id=\".*\"$|application/app_store_team_id=\"${TEAM_ID}\"|" \
  -e "s|^application/bundle_identifier=\".*\"$|application/bundle_identifier=\"${BUNDLE_ID}\"|" \
  -e "s|^application/short_version=\".*\"$|application/short_version=\"${VERSION}\"|" \
  -e "s|^application/version=\".*\"$|application/version=\"${BUILD_NUMBER}\"|" \
  export_presets.cfg
rm -f export_presets.cfg.bak

echo "--- Exporting the Xcode project: ${BUNDLE_ID} ${VERSION} (${BUILD_NUMBER}) ---"
rm -rf build/ios
mkdir -p build/ios
"${GODOT}" --headless --export-release "iOS" build/ios/Voidline.ipa

# Godot writes "Apple Distribution" as the Release identity, which Xcode rejects next to
# automatic signing. Archive / Distribute App re-signs for distribution on its own.
sed -i.bak 's|CODE_SIGN_IDENTITY = "Apple Distribution";|CODE_SIGN_IDENTITY = "Apple Development";|' \
  build/ios/Voidline.xcodeproj/project.pbxproj
rm -f build/ios/Voidline.xcodeproj/project.pbxproj.bak

python3 tests/ios_export_check.py build/ios \
  --team "${TEAM_ID}" --bundle "${BUNDLE_ID}" --version "${VERSION}" --build "${BUILD_NUMBER}"

if [ "${MODE}" = "project" ]; then
  echo "--- Done. Open build/ios/Voidline.xcodeproj, or run ./build_ios.sh archive ---"
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "build_ios: '${MODE}' needs Xcode (xcodebuild); the project is in build/ios/." >&2
  exit 1
fi

AUTH=()
if [ -n "${VR_ASC_KEY_PATH:-}" ]; then
  AUTH=(-authenticationKeyPath "${VR_ASC_KEY_PATH}"
        -authenticationKeyID "${VR_ASC_KEY_ID:?set VR_ASC_KEY_ID}"
        -authenticationKeyIssuerID "${VR_ASC_ISSUER_ID:?set VR_ASC_ISSUER_ID}")
fi

echo "--- Archiving ---"
xcodebuild -project build/ios/Voidline.xcodeproj -scheme Voidline \
  -configuration Release -destination "generic/platform=iOS" \
  -archivePath build/ios/Voidline.xcarchive \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} archive

if [ "${MODE}" = "archive" ]; then
  echo "--- Done: build/ios/Voidline.xcarchive (Xcode: Window, Organizer, Distribute App) ---"
  exit 0
fi

cat > build/ios/UploadOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
EOF

echo "--- Uploading to TestFlight ---"
xcodebuild -exportArchive -archivePath build/ios/Voidline.xcarchive \
  -exportOptionsPlist build/ios/UploadOptions.plist -exportPath build/ios/upload \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

echo "--- Uploaded ${VERSION} (${BUILD_NUMBER}). It shows in TestFlight once Apple has processed it. ---"
