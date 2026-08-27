# Window Layouts Experimental for macOS

### Your Workspace, Organized Your Way!

> [!CAUTION]
> This branch is an unsupported, opt-in prototype for moving a window between
> macOS Spaces. It is deliberately separate from the signed Window Layouts
> release and is not distributed as an official update.

Window Layouts Experimental is a native macOS utility for arranging application
windows. It includes the stable layout, display-transfer, fill-display,
green-button panel, drag-target, Dock-menu, and global-shortcut features, plus a
guarded experiment that asks macOS to carry the active window to the previous or
next Space.

The app uses SwiftUI, AppKit, the public Accessibility API, and public Quartz
event APIs. It has no third-party dependencies, telemetry, or analytics. It does
not use private Spaces APIs or bypass macOS privacy controls.

## Isolation from the released app

The experimental build uses:

- the product name **Window Layouts Experimental**;
- bundle identifier `com.astrobrett.WindowLayouts.Experimental`;
- a separate Application Support directory and settings library;
- a separate Accessibility/Input Monitoring identity; and
- no stable-release updater or automatic installer.

Quit the released Window Layouts app while testing this build so two copies do
not register overlapping shortcuts or react to the same window action.

## How experimental Space movement works

macOS does not provide a public API for assigning another application's window
to a Space. This prototype reproduces the user gesture through public Quartz
events: it briefly holds a verified noninteractive point in the active window's
title bar while sending Control–Left Arrow or Control–Right Arrow.

The prototype:

- requires explicit opt-in and confirmation of the Mission Control shortcuts;
- requires macOS Accessibility and input-event posting permission;
- waits until real mouse buttons and modifier keys have been released;
- rejects minimized, native full-screen, nonstandard, immovable, obscured, or
  unsafe target windows;
- releases every synthetic key and mouse button after success or failure; and
- restores the pointer to its original location.

There is no public way to verify which Space contains a third-party window, so
the app can report only that the gesture was requested. Behavior can vary by app
and may stop working after a macOS update.

## Build and configure

1. Open `WindowLayouts.xcodeproj` from this experimental worktree in Xcode.
2. Select your development team and run **WindowLayouts**.
3. Grant **Window Layouts Experimental** access when macOS requests it. If
   needed, check **System Settings → Privacy & Security → Accessibility** and
   **Input Monitoring**.
4. In **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**,
   enable **Move left a space** and **Move right a space** as Control–Left Arrow
   and Control–Right Arrow.
5. Open **Configure Window Layouts Experimental… → General**, enable the
   experimental feature, confirm those Mission Control shortcuts, and choose
   **Apply**.
6. In **Shortcuts**, assign different trigger combinations to **Move Window to
   Previous Space** and **Move Window to Next Space**. Do not assign the raw
   Control-arrow combinations, because Mission Control needs them internally.

The actions are also available from the menu bar, Dock menu, and green-button
panel when the experiment is enabled and permissions are granted.

Run the test suite without posting any real input events:

```bash
xcodebuild test \
  -project WindowLayouts.xcodeproj \
  -scheme WindowLayouts \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

## Other safety boundaries

Window Layouts never modifies application title bars. Optional drag targets and
previews are nonactivating panels with `ignoresMouseEvents = true`; hidden or
screen-sized overlay windows cannot accept input. The menu-bar item remains the
emergency path for disabling optional overlays.

The App Sandbox is disabled because controlling other applications through the
Accessibility API is central to the prototype. A local development build should
not be treated as a notarized release.

## Stable and Fedora/KDE editions

- Stable macOS edition: [baddison2005/window-layouts-macos](https://github.com/baddison2005/window-layouts-macos)
- Fedora/KDE Plasma edition: [baddison2005/window-layouts-kde](https://github.com/baddison2005/window-layouts-kde)

## License

Window Layouts is licensed under the
[GNU General Public License v3.0 or later](LICENSE).
