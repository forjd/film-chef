#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FilmChef"
BUNDLE_ID="com.filmchef.app"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${APP_VERSION:-0.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.zip"
NOTARIZE="${NOTARIZE:-0}"

create_archive() {
  rm -f "$ARCHIVE_PATH"
  ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"
}

cd "$ROOT_DIR"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"

swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

for RESOURCE_BUNDLE in "$BUILD_DIR"/${APP_NAME}_*.bundle; do
  [[ -d "$RESOURCE_BUNDLE" ]] || continue
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
done

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDisplayName</key>
  <string>Film Chef</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Film Chef Project</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.filmchef.project</string>
      </array>
    </dict>
  </array>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.photography</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright (c) 2026 Forjd. Released under the MIT License.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.json</string>
      </array>
      <key>UTTypeDescription</key>
      <string>Film Chef Project</string>
      <key>UTTypeIdentifier</key>
      <string>com.filmchef.project</string>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>filmchef</string>
        </array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Sign nested bundles first, then the app itself; --deep is deprecated for
# distribution signing.
sign_app() {
  local identity="$1"
  shift
  while IFS= read -r -d '' nested_bundle; do
    codesign --force "$@" --sign "$identity" "$nested_bundle"
  done < <(find "$APP_RESOURCES" -name '*.bundle' -prune -print0)
  codesign --force "$@" --sign "$identity" "$APP_BUNDLE"
}

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  sign_app "$SIGN_IDENTITY" --options runtime --timestamp
else
  sign_app -
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

create_archive

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    echo "NOTARIZE=1 requires SIGN_IDENTITY for Developer ID signing." >&2
    exit 1
  fi

  NOTARY_ARGS=()
  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE")
  else
    if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APP_SPECIFIC_PASSWORD:-}" ]]; then
      echo "NOTARIZE=1 requires NOTARYTOOL_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APP_SPECIFIC_PASSWORD." >&2
      exit 1
    fi
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APP_SPECIFIC_PASSWORD")
  fi

  SUBMIT_OUTPUT="$(xcrun notarytool submit "$ARCHIVE_PATH" "${NOTARY_ARGS[@]}" --wait 2>&1 | tee /dev/stderr)" || true
  if ! grep -q "status: Accepted" <<<"$SUBMIT_OUTPUT"; then
    SUBMISSION_ID="$(grep -m1 -E '^[[:space:]]*id: ' <<<"$SUBMIT_OUTPUT" | awk '{print $2}')"
    if [[ -n "$SUBMISSION_ID" ]]; then
      echo "Notarization was not accepted; fetching log for $SUBMISSION_ID" >&2
      xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" >&2 || true
    fi
    echo "Notarization failed." >&2
    exit 1
  fi

  xcrun stapler staple "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  spctl --assess --type execute --verbose "$APP_BUNDLE"
  create_archive
else
  if ! spctl --assess --type execute --verbose "$APP_BUNDLE"; then
    echo "note: Gatekeeper assessment failed; distribution requires notarization (NOTARIZE=1)." >&2
  fi
fi

echo "Release app: $APP_BUNDLE"
echo "Archive: $ARCHIVE_PATH"
