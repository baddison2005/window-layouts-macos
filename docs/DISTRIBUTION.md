# Public distribution

Window Layouts uses Developer ID distribution outside the Mac App Store. App
Sandbox remains disabled because the application is an Accessibility client
that moves third-party windows. Release builds enable Hardened Runtime and use
only public macOS APIs.

## One-time signing setup

Install a **Developer ID Application** certificate for the selected Apple
Developer team in the login Keychain. Store notarization credentials in the
Keychain rather than in this repository:

```bash
xcrun notarytool store-credentials "window-layouts-notary" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "APPLE_DEVELOPER_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Do not commit the Apple ID, app-specific password, exported certificates, or
notarization credentials.

## Create the release zip

From the repository root, provide the non-secret team and identity names plus
the Keychain profile name:

```bash
export DEVELOPMENT_TEAM="APPLE_DEVELOPER_TEAM_ID"
export DEVELOPER_ID_APPLICATION="Developer ID Application: CERTIFICATE NAME (TEAM_ID)"
export NOTARYTOOL_PROFILE="window-layouts-notary"
./Scripts/package-release.sh
```

The script refuses to overwrite an existing artifact. It creates a Release
archive, verifies its signature, submits a temporary zip to Apple, waits for
notarization, staples and validates the ticket, runs Gatekeeper assessment, and
then writes `dist/Window-Layouts-1.0.0-macOS.zip`.

Before publishing, test that exact zip on a fresh macOS account or Mac. Publish
the GPL-3.0-or-later source corresponding to the binary and retain the
notarization log with the release records.

## Fresh-user installation

1. Download and expand the notarized zip.
2. Move **Window Layouts.app** into `/Applications` before launching it.
3. Open Window Layouts. Use its onboarding command to grant access under
   **System Settings → Privacy & Security → Accessibility**.
4. If drag targets do not receive global drag observations, separately allow
   Window Layouts under **Input Monitoring**, then relaunch it.
5. Configure layouts and optional features from the menu-bar icon. Enable
   launch at login only after the app is installed in `/Applications`.

Window Layouts never asks users to bypass Gatekeeper or macOS privacy controls.
Updating should preserve the bundle identifier, Developer ID team, and install
path so Accessibility approval remains stable. Quit the old version before
replacing it to avoid two copies issuing window commands.

## Diagnostics

Window Layouts emits unified logs under the
`com.astrobrett.WindowLayouts` subsystem with `WindowOperations`, `Overlays`,
`Persistence`, and `Lifecycle` categories:

```bash
log stream --style compact --level debug \
  --predicate 'subsystem == "com.astrobrett.WindowLayouts"'
```

Action names, process identifiers, window geometry, and error details are
private by default. Window titles, document paths, typed keys, and shortcut
contents are not logged. The app contains no telemetry.
