#!/bin/zsh
# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIRECTORY:h}
PROJECT_PATH="$PROJECT_ROOT/WindowLayouts.xcodeproj"
SCHEME="WindowLayouts"
OUTPUT_DIRECTORY="$PROJECT_ROOT/dist"
APP_NAME="Window Layouts Experimental"
ARTIFACT_PREFIX="Window-Layouts-Experimental"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application identity.}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a notarytool Keychain profile.}"

VERSION=$(xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -showBuildSettings | awk '/ MARKETING_VERSION = / { print $3; exit }')

[[ -n "$VERSION" ]] || { print -u2 "Could not read MARKETING_VERSION."; exit 1; }

SOURCE_ZIP=${1:-"$OUTPUT_DIRECTORY/$ARTIFACT_PREFIX-$VERSION-macOS.zip"}
OUTPUT_DMG="$OUTPUT_DIRECTORY/$ARTIFACT_PREFIX-$VERSION-macOS.dmg"

[[ -f "$SOURCE_ZIP" ]] || { print -u2 "Release zip not found: $SOURCE_ZIP"; exit 1; }
[[ ! -e "$OUTPUT_DMG" ]] || {
  print -u2 "Refusing to overwrite existing artifact: $OUTPUT_DMG"
  exit 1
}

WORK_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/window-layouts-dmg.XXXXXX")
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

EXTRACT_DIRECTORY="$WORK_DIRECTORY/extracted"
STAGING_DIRECTORY="$WORK_DIRECTORY/staging"
DMG_PATH="$WORK_DIRECTORY/$ARTIFACT_PREFIX-$VERSION-macOS.dmg"
mkdir -p "$EXTRACT_DIRECTORY" "$STAGING_DIRECTORY"

ditto -x -k "$SOURCE_ZIP" "$EXTRACT_DIRECTORY"
APP_PATH="$EXTRACT_DIRECTORY/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { print -u2 "Release zip did not contain $APP_NAME.app."; exit 1; }

APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
[[ "$APP_VERSION" == "$VERSION" ]] || {
  print -u2 "App version $APP_VERSION does not match project version $VERSION."
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_NAME"
ARCHITECTURES=$(lipo -archs "$EXECUTABLE")
[[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " == *" x86_64 "* ]] || {
  print -u2 "Expected a universal arm64 and x86_64 app; found: $ARCHITECTURES"
  exit 1
}

ditto "$APP_PATH" "$STAGING_DIRECTORY/$APP_NAME.app"
ln -s /Applications "$STAGING_DIRECTORY/Applications"

hdiutil create \
  -quiet \
  -fs HFS+ \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIRECTORY" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

codesign --force \
  --sign "$DEVELOPER_ID_APPLICATION" \
  --timestamp \
  "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=2 \
  "$DMG_PATH"

mkdir -p "$OUTPUT_DIRECTORY"
mv "$DMG_PATH" "$OUTPUT_DMG"

print "Created signed and notarized disk image: $OUTPUT_DMG"
