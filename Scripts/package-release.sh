#!/bin/zsh
# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
PROJECT_PATH="$PROJECT_ROOT/WindowLayouts.xcodeproj"
SCHEME="WindowLayouts"
OUTPUT_DIRECTORY="$PROJECT_ROOT/dist"
APP_NAME="Window Layouts Experimental"
ARTIFACT_PREFIX="Window-Layouts-Experimental"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer team ID.}"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application identity.}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a notarytool Keychain profile.}"

VERSION=$(xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -showBuildSettings | awk '/ MARKETING_VERSION = / { print $3; exit }')

[[ -n "$VERSION" ]] || { print -u2 "Could not read MARKETING_VERSION."; exit 1; }

OUTPUT_ZIP="$OUTPUT_DIRECTORY/$ARTIFACT_PREFIX-$VERSION-macOS.zip"
[[ ! -e "$OUTPUT_ZIP" ]] || {
  print -u2 "Refusing to overwrite existing artifact: $OUTPUT_ZIP"
  exit 1
}

WORK_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/window-layouts-release.XXXXXX")
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

ARCHIVE_PATH="$WORK_DIRECTORY/WindowLayouts.xcarchive"
SUBMISSION_ZIP="$WORK_DIRECTORY/$ARTIFACT_PREFIX-$VERSION-submission.zip"

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { print -u2 "Archive did not contain $APP_NAME.app."; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"

xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

mkdir -p "$OUTPUT_DIRECTORY"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_ZIP"

print "Created notarized release: $OUTPUT_ZIP"
