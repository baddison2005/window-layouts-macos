# macOS prototype architecture

The macOS edition is a native implementation, not a translation of the KDE
KWin/QML code.

- `Geometry/` is nonisolated, platform-neutral logic for normalized rectangles,
  fixed layouts, edge-aware padding, coordinate conversion, and monitor
  transfer.
- `LayoutLibrary` schema 5 is the versioned Codable document for custom layouts,
  custom groups, menu group order, padding, stable shortcut assignments, and the
  launch-at-login, green-button-panel, and drag-target preferences. Older documents migrate
  in memory with safe defaults. Decoding and pre-save validation reject invalid
  geometry, duplicate identifiers or shortcut combinations, broken references,
  unknown actions or menu groups, and more than 20 custom layouts.
- `LayoutLibraryPersistence` atomically stores the library in Application
  Support. Invalid or corrupt input returns safe in-memory defaults without a
  repair write, preserving the original bytes for diagnosis or recovery.
- `SettingsStore` is the one observable canonical model shared by the menu,
  controller, and Settings scene. `SettingsDraft` isolates unapplied edits so
  Cancel and window close cannot mutate active behavior.
- `AccessibilityPermissionService` owns trust checks and explicit prompting.
- `WindowAccessibilityService` is an actor that serializes focused-window AX
  lookup, validation, frame mutation, and in-memory Restore frames. AX messaging
  uses a 250 ms timeout. The system-wide AX focused application remains the
  primary source; when macOS reports no value for it, the service uses the
  public `NSWorkspace.frontmostApplication` PID to create the equivalent AX
  application element. Frame writes use a destination-contained staging
  position, then size and final position. When the old frame is too large for a
  destination display, they resize before moving to avoid an oversized visible
  intermediate frame. Monitor movement is explicitly two-stage: move a safely
  contained staging frame, allow 350 ms for the display handoff, then use the
  normal same-display layout path. Writes verify after 60 ms and again after a
  220 ms settle interval, correcting late geometry drift. Unified diagnostics
  record the requested, staging, handed-off, settled, and final frames as
  private data. The final accepted
  frame is constrained to the usable display when an application imposes its
  own size.
- `ScreenService` snapshots `NSScreen` frames on the main actor and converts
  them once into Accessibility's top-left global coordinate system.
- `ScreenGeometryResolver` identifies the display with the largest window
  intersection and deterministically selects an adjacent display.
- `MonitorTransfer` preserves known fixed or custom layouts across usable
  display frames; free-form windows retain their normalized size and position.
  The AX service separately remembers the last intended layout and the frame
  the target application actually accepted. If an application enforces a
  minimum width or height, an unchanged window therefore returns to the intended
  layout on a larger monitor instead of scaling the constrained dimensions.
  Moving or resizing the window manually invalidates that remembered match.
- `WindowLayoutsController` coordinates menu actions without performing AX
  calls on the main actor.
- `GlobalShortcutManager` observes only applied canonical settings and maps
  stable action identifiers to individual-window or multi-window-fill
  controller actions. Built-in fill IDs are fixed; custom-fill IDs contain the
  group's UUID and therefore survive renaming and reordering. Its registrar is
  abstracted for unit tests. `CarbonGlobalShortcutService` uses the public
  `RegisterEventHotKey` API on the main actor with `kEventHotKeyNoOptions`; it
  never requests exclusive ownership. Registration failures are surfaced for
  recovery. macOS does not expose a complete registry for another application's
  non-exclusive shortcuts.
- `LaunchAtLoginManager` observes the applied preference and calls
  `SMAppService.mainApp`. Enabled, disabled, approval-required, unavailable, and
  recoverable failure states remain explicit and are tested with a fake system
  client.
- `ActiveWindowSnapshotService` performs short-timeout, defensive public AX
  discovery for the focused third-party window and its full-screen/zoom button.
  It uses the same `NSWorkspace.frontmostApplication` fallback as command
  dispatch when the system-wide AX focused-application attribute is absent.
  A normal window maximized to `NSScreen.visibleFrame` remains eligible. A
  full-display frame is rejected when the display has reserved menu-bar or Dock
  space. On an edge-to-edge external display, public geometry cannot distinguish
  that frame from a normally maximized window, so the panel additionally relies
  on the existing standard/movable-window checks and a real, nonzero AX green
  button before it can be triggered.
  `ActiveWindowObserver` combines focused-window AX notifications, workspace
  activation/display notifications, and a low-frequency enabled-only fallback
  refresh. It publishes geometry only; it never changes another app's UI.
- `LayoutPanelPlacementEngine` is pure geometry in Accessibility's top-left
  coordinate space. It places the requested compact panel below the green
  button when possible, switches above and/or to trailing alignment near usable
  display edges, and refuses to create a panel when the requested size would no
  longer be compact relative to the usable display.
- `GreenButtonPanelController` compares the pointer with the public AX button
  frame and presents `SafeLayoutPanel`, a borderless nonactivating `NSPanel`,
  only while the feature is enabled. The panel contains ordinary SwiftUI action
  controls and calls the same `WindowLayoutsController` actions as the menu bar.
  Repeated AX observations do not reframe an unchanged panel, and actual frame
  changes avoid forcing a synchronous AppKit display pass while the hosted
  SwiftUI hierarchy may already be laying itself out.
- `SafeLayoutPanel` is exactly the size of its visible content. It sets
  `ignoresMouseEvents = true` before concealment and enables input only after
  the opaque panel is visibly ordered front. It is never screen-sized, key, or
  main. `OptionalOverlaySafety` and the persistent menu-bar emergency command
  stop observation and conceal it immediately.
- `DragTargetController` installs a global AppKit mouse-event observer only
  while its opt-in feature is enabled. The first drag sample records a standard,
  movable AX window; a later sample must show origin movement without a size
  change before any overlay appears. The AX actor retains a short-lived opaque
  session token so release applies to that recorded window instead of resolving
  whichever application happens to be focused later. A 50 ms public
  `CGEventSource.buttonState` check recovers a missed mouse-up. Permission loss,
  resize detection, window destruction, display topology changes, or disabling
  the feature cancels the session. The display containing the hovered target is
  carried through mouse-up as an explicit ID; it overrides largest-window-
  intersection resolution at shared display edges and triggers the normal
  staged display-handoff path when necessary.
- `DragTargetLayoutEngine` is pure geometry in Accessibility coordinates. It
  builds zone-center stacks or a wrapping top-center strip, calculates
  proximity and sticky reveal bounds, hit-tests the global pointer, and reuses
  `LayoutEngine` for padded previews. Group order controls stacking order for
  layouts with identical centers.
- Every drag card, strip background, and preview is its own borderless
  nonactivating `InputTransparentOverlayPanel`. These panels set
  `ignoresMouseEvents = true` during initialization, immediately before every
  map, and before every unmap; no code path enables their input. The preview may
  cover a large destination rectangle but remains input-transparent, while
  target-card windows are only 116 × 80 logical points.
- Multi-window fill first anchors to the focused or explicitly retained target
  window's display. Public `CGWindowListCopyWindowInfo` with
  `optionOnScreenOnly` supplies the current desktop's front-to-back window
  rectangles; those are matched one-to-one with eligible elements from the
  public `kAXWindowsAttribute`. Matching by PID and frame, and consuming each AX
  element once, prevents AX-only windows on other Spaces from being selected in
  the ordinary case. Each matched window is assigned the next normalized slot,
  wrapping only when there are more windows than layouts. No window is assigned
  to or moved between Spaces.
- `MenuBarExtra`, the SwiftUI Settings scene, and the optional compact panel are
  the UI surfaces in the current phase. The Settings editor draws a 24 × 12
  `Canvas` inside its normal application window; it is not an overlay.
- `Localizable.xcstrings` is the English source catalog for SwiftUI, AppKit,
  validation, and status text. Icon-only controls have explicit VoiceOver
  labels, and the custom-layout grid exposes named move and resize actions.
- Release builds keep App Sandbox disabled, enable Hardened Runtime, and carry
  no unused file-access entitlements. `Scripts/package-release.sh` requires a
  Developer ID identity and Keychain notary profile, then verifies, notarizes,
  staples, Gatekeeper-assesses, and zips the exact app artifact.
- `AppDiagnostics` uses the `com.astrobrett.WindowLayouts` unified-log subsystem.
  Dynamic action names, process identifiers, geometry, and errors are private;
  no window title, document path, typed key, shortcut contents, or telemetry is
  recorded.

No private API, title-bar modification, input synthesis, or Spaces integration
exists. Pointer proximity is sampled only during an observed drag while drag
targets are enabled. macOS may require the user to grant Input Monitoring for
global drag events; Settings explains that optional privacy-controlled step.
macOS exposes no public API for assigning arbitrary third-party windows to
Spaces.

The public SDK has no supported full-screen state attribute for third-party AX
windows. Full-display frames are therefore rejected conservatively unless they
match a frame Window Layouts itself just applied and retained for Restore.
