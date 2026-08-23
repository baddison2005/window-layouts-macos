# Window Layouts for macOS

### Your Workspace Organized the Way You Want It!

Window Layouts is a native macOS menu-bar utility for moving and resizing
application windows. The implementation contains the Phase 0 geometry core,
the Phase 1 focused-window controller, Phase 2 custom-layout settings, Phase 3
global shortcuts and launch-at-login controls, the Phase 4 optional green-button
layout panel, Phase 5 input-transparent drag targets, and Phase 6 release
hardening.

## Behavior

- Fixed layouts: four halves, four quarters, three thirds, and three two-thirds
  layouts, matching the Fedora/KDE default set.
- Window actions: Center, Maximize, and Restore.
- Display actions: Move to Previous Monitor and Move to Next Monitor. They
  preserve a recognized fixed or custom layout, or proportional free-form
  geometry.
- Up to 20 named custom layouts on a 24 × 12 selection grid.
- Named, reorderable custom groups and independently reorderable menu sections.
- Edge-aware padding from 0 through 200 logical points.
- Apply/Cancel Settings editing backed by one canonical in-process store.
- Configurable global shortcuts for every fixed and custom layout, each
  built-in or custom **Fill Target Display** group, window action, and monitor
  action. Internal duplicates are rejected.
- Optional launch at login through the public Service Management API, with
  explicit approval, failure, and retry states.
- An optional compact layout panel beside the focused window's green button.
  It uses the button geometry reported by the public Accessibility API and does
  not modify or replace Apple's title-bar menu. The panel includes a public
  SwiftUI Settings link for configuring Window Layouts.
- Four panel sizes, edge-aware placement, active-window tracking, and a fully
  opaque surface from the moment the panel appears.
- Optional drag targets at matching layout-zone centers or in a top-center
  strip, with proximity or immediate reveal modes. Shared-center targets stack
  without overlapping, and a hovered target previews its padded destination.
- Drag release applies to the exact AX window recorded when movement began.
  The hovered target's display remains authoritative even while most of the
  dragged window is still on an adjacent display. Interactive resize,
  permission loss, display changes, destroyed targets, and stale sessions
  cancel without moving a window.
- **Fill Target Display** arranges eligible visible windows using horizontal or
  vertical halves, quarters, thirds, or a named custom group. The focused or
  retained target window chooses the display. Windows are assigned in public
  Core Graphics front-to-back order; extra windows reuse slots in the same
  order.
- A versioned JSON library saved atomically under
  `~/Library/Application Support/Window Layouts/layout-library.json`.
- Corrupt libraries activate safe defaults without automatically changing the
  original file.
- Uses the Fedora/KDE Window Layouts artwork with a dedicated 16 × 16-point
  intrinsic canvas for the menu-bar item.
- An optional Dock icon uses the application artwork and the standard public
  macOS Dock context menu. Control-click or right-click it for the complete
  fixed, custom, window, and monitor action hierarchy, or to configure Window
  Layouts. Dock actions retain the last active third-party app as their explicit
  Accessibility target because opening the Dock menu can change which app is
  frontmost. The menu-bar menu shows and uses that same retained target.
- Uses `NSScreen.visibleFrame` in logical points.
- Uses only the public `AXUIElement` Accessibility client API.
- Verifies each AX frame mutation and retries once after a short delay for apps
  that apply their first resize asynchronously.
- Keeps App Sandbox disabled because the app controls other applications through
  the public Accessibility client API. Release builds enable Hardened Runtime.
- Registers shortcuts non-exclusively through the public Carbon event API, so
  Window Layouts never suppresses another application's shortcut. macOS has no
  complete public registry for detecting shortcuts used by other apps, so both
  apps may respond to the same combination.
- Does not modify title bars or move windows between Spaces. The green-button
  panel is compact and visibly rendered. Every drag target and preview panel
  always uses `ignoresMouseEvents = true`; hidden panels do so before they are
  ordered out. Screen-sized and invisible interactive windows are prohibited.
- Keeps an always-available menu command that immediately disables optional
  panels and persists the disabled setting.

Grant Accessibility access only from the app's onboarding action in **System
Settings → Privacy & Security → Accessibility**.

## Build and test

Open `WindowLayouts.xcodeproj` in Xcode 26.6 or run:

```bash
xcodebuild test \
  -project WindowLayouts.xcodeproj \
  -scheme WindowLayouts \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

The deployment target is macOS 14.6. There are no third-party dependencies.
Developer ID signing, notarization, stapling, packaging, and fresh-user
installation are documented in [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md).

When iterating in Xcode, quit or stop the previously running menu-bar build
before running a newly compiled copy. Two copies acting on the same focused
window can issue competing frame changes and make placement appear constrained
until every old copy is quit.

## Settings workflow

Choose **Configure Window Layouts…** from the menu-bar menu. Edits remain in a
draft until **Apply** is selected. **Cancel**, closing the Settings window, or
reopening it without applying discards the draft and leaves the active layout
library unchanged. Shortcut assignments, launch-at-login, green-button panel,
Dock icon, and drag-target preferences are part of the same version 5 library
and also take effect only after Apply.

The green-button panel is disabled by default. Enable it under **General**, pick
a compact size, and choose **Apply**. Hover the green button of an eligible
third-party window to reveal it. Apple may still show its own tiling menu; the
app neither suppresses nor alters that system UI. Layout rows use the standard
accent-color highlight as the pointer moves over them.

The Dock icon is disabled by default. Enable it under **General** and choose
**Apply**, then control-click or right-click the application icon to choose a
layout or open **Configure Window Layouts…**. The Dock and menu-bar menus
identify the external app that will receive the action. A normal click continues
to use the standard macOS activation behavior because macOS has no public API
for replacing a Dock icon's primary click with a custom popup. Disable the
setting to return to a menu-bar-only app.

Drag targets are also disabled by default. Enable them under **General**, choose
zone-center or top-center placement and an optional immediate reveal mode, then
choose **Apply**. Start moving a normal third-party window with the mouse, hover
a visible target, and release to apply it. The overlays never receive the drag
or mouse-up. If this macOS installation does not deliver global drag events,
allow Window Layouts under **System Settings → Privacy & Security → Input
Monitoring** and relaunch it.

Choose **Fill Target Display** from the menu-bar, Dock, or green-button panel
and select a group. Window Layouts uses the target window to select the MacBook
or external display, then matches public Core Graphics on-screen windows to
eligible public Accessibility windows. Minimized, nonstandard, native
full-screen, immovable, off-display, and other-Space windows are left alone.
When there are more visible windows than slots, later windows reuse the slots
from the beginning; choose or create a group with enough layouts to avoid
stacking.

To record a shortcut, open the **Shortcuts** tab, choose **Record Shortcut**, and
press a key combination containing Command, Option, or Control. The **Fill
Target Display** section includes the four built-in fill groups and every named
custom group. A fill shortcut uses the focused window to choose its display,
just like the menu command. Delete clears a shortcut and Escape cancels
recording. Registration failures remain visible in Settings and can be retried.

Launch-at-login builds run from Xcode may live at a temporary DerivedData path.
Verify the login item again after installing a signed build in Applications.

## Platform limit

Moving an arbitrary third-party window to another Space is intentionally not
implemented. macOS has no supported public API for that operation; adding it
would require private APIs or brittle UI automation. Window Layouts does not
attempt to bypass that boundary.

## Diagnostics and privacy

Window Layouts uses privacy-redacted unified logging and contains no telemetry.
It does not log window titles, document paths, typed keys, or shortcut contents.
See [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) for the diagnostic command and
release process.

## License

Window Layouts is licensed under GPL-3.0-or-later. See `LICENSE`.
