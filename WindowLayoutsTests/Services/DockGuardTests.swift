// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import WindowLayouts

struct DockGuardPolicyTests {
    let laptop = ScreenSnapshot(id: "mac", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: .zero)
    let lg = ScreenSnapshot(id: "lg", frame: CGRect(x: -200, y: -1000, width: 1400, height: 1000), visibleFrame: .zero)

    @Test func strongProtectsSlidingAndIdleEdgesWithoutWaiting() {
        let policy = DockGuardPolicy()
        for x in [-100.0, -99.5, 1100, 1101] {
            #expect(policy.strongCorrection(point: CGPoint(x: x, y: -1), deltaY: 0, now: 0,
                screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false)
                == CGPoint(x: x, y: -6))
        }
    }

    @Test func strongSharedEdgeIsExemptAtEverySpeedAndInBothDirections() {
        let policy = DockGuardPolicy()
        for delta in [-20.0, -1, 0, 1, 20] {
            for x in [-5.0, 0, 500, 999, 1005] {
                #expect(policy.strongCorrection(point: CGPoint(x: x, y: -1), deltaY: delta, now: 0,
                    screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
            }
        }
        #expect(policy.strongCorrection(point: CGPoint(x: -100, y: -1), deltaY: 5, now: 0,
            screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false)
            == CGPoint(x: -100, y: -6))
    }

    @Test func strongLeavesResizeButtonsBypassAndCooldownUntouched() {
        var policy = DockGuardPolicy()
        for (down, bypass) in [(true, false), (false, true)] {
            #expect(policy.strongCorrection(point: CGPoint(x: -100, y: -1), deltaY: 1, now: 1,
                screens: [laptop, lg], preferredID: "mac", mouseIsDown: down, bypass: bypass) == nil)
        }
        policy.inputReleased(at: 2)
        #expect(policy.strongCorrection(point: CGPoint(x: -100, y: -1), deltaY: 0, now: 2.4,
            screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
        #expect(policy.strongCorrection(point: CGPoint(x: -100, y: -1), deltaY: 0, now: 2.6,
            screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) != nil)
    }

    @Test func strengthMigrationKeepsExistingPreferences() throws {
        let old = Data(#"{"enabled":true,"bypassModifier":"shift","preferredDisplayID":"LG"}"#.utf8)
        var preferences = try JSONDecoder().decode(DockGuardPreferences.self, from: old)
        #expect(preferences.strength == .gentle)
        #expect(preferences.enabled && preferences.preferredDisplayID == "LG" && preferences.bypassModifier == .shift)
        preferences.strength = .strong
        #expect(try JSONDecoder().decode(DockGuardPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }

    @Test func stackedSharedEdgeAllowsCrossingsAndIdlePointerInGentleMode() {
        var policy = DockGuardPolicy()
        for (time, y) in [(0.0, -4.0), (0.04, -2.0), (0.08, -1.0), (0.12, 1.0)] {
            #expect(policy.correction(point: CGPoint(x: 500, y: y), now: time,
                screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
        }
        #expect(policy.correction(point: CGPoint(x: 500, y: -1), now: 1,
            screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
        #expect(policy.correction(point: CGPoint(x: 500, y: -1), now: 1.2,
            screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
        #expect(policy.correction(point: CGPoint(x: 500, y: -1), now: 1.3,
            screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
    }

    @Test func rearrangementMovesTheExemptSegmentAndVisibleFrameChangesAreIgnored() {
        let policy = DockGuardPolicy()
        let moved = ScreenSnapshot(id: "mac", frame: CGRect(x: 500, y: 0, width: 1000, height: 800), visibleFrame: .zero)
        let point = CGPoint(x: 200, y: -1)
        #expect(policy.strongCorrection(point: point, deltaY: 0, now: 0,
            screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
        #expect(policy.strongCorrection(point: point, deltaY: 0, now: 0,
            screens: [moved, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == CGPoint(x: 200, y: -6))
        #expect(!DockGuardPolicy.sameDisplayGeometry([laptop, lg], [moved, lg]))
        #expect(!DockGuardPolicy.sameDisplayGeometry([laptop, lg], [laptop]))
        let dockChanged = ScreenSnapshot(id: "lg", frame: lg.frame, visibleFrame: lg.frame.insetBy(dx: 0, dy: 50))
        #expect(DockGuardPolicy.sameDisplayGeometry([laptop, lg], [dockChanged, laptop]))
    }

    @Test func sideBySideDisplaysKeepTheirExposedBottomEdgesGuarded() {
        let policy = DockGuardPolicy()
        let right = ScreenSnapshot(id: "right", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800), visibleFrame: .zero)
        #expect(policy.strongCorrection(point: CGPoint(x: 1500, y: 799), deltaY: 0, now: 0,
            screens: [laptop, right], preferredID: "mac", mouseIsDown: false, bypass: false) == CGPoint(x: 1500, y: 794))
    }

    @Test func exposedOverhangOnlyNudgesAfterDwellInLogicalPoints() {
        var policy = DockGuardPolicy()
        let point = CGPoint(x: -100, y: -1)
        #expect(policy.correction(point: point, now: 0, screens: [laptop, lg],
            preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
        #expect(policy.correction(point: point, now: 0.1, screens: [laptop, lg],
            preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
        #expect(policy.correction(point: point, now: 0.2, screens: [laptop, lg],
            preferredID: "mac", mouseIsDown: false, bypass: false) == CGPoint(x: -100, y: -6))
    }

    @Test func resizeDragModifierAndReleaseCooldownPassThrough() {
        var policy = DockGuardPolicy()
        let point = CGPoint(x: -100, y: -1)
        for time in [0.0, 1, 2] {
            #expect(policy.correction(point: point, now: time, screens: [laptop, lg],
                preferredID: "mac", mouseIsDown: true, bypass: false) == nil)
        }
        policy.inputReleased(at: 2)
        for time in [2.1, 2.3, 2.49] {
            #expect(policy.correction(point: point, now: time, screens: [laptop, lg],
                preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
        }
        for time in [3.0, 4] {
            #expect(policy.correction(point: point, now: time, screens: [laptop, lg],
                preferredID: "mac", mouseIsDown: false, bypass: true) == nil)
        }
    }

    @Test func missingPreferredDisplayAndPreferredEdgeNeverNudge() {
        var policy = DockGuardPolicy()
        for id in [nil, "disconnected", "lg"] {
            for time in [0.0, 1] {
                #expect(policy.correction(point: CGPoint(x: -100, y: -1), now: time,
                    screens: [laptop, lg], preferredID: id, mouseIsDown: false, bypass: false) == nil)
            }
        }
    }

    @Test func continuousMotionResetsDwellAndSideBySideDoesNotBlockCrossing() {
        var policy = DockGuardPolicy()
        for index in 0..<10 {
            #expect(policy.correction(point: CGPoint(x: -100 + index * 4, y: -1),
                now: Double(index) * 0.1, screens: [laptop, lg], preferredID: "mac",
                mouseIsDown: false, bypass: false) == nil)
        }
        #expect(policy.correction(point: CGPoint(x: 0, y: -100), now: 3,
            screens: [laptop, lg], preferredID: "mac", mouseIsDown: false, bypass: false) == nil)
    }

    @Test func oldLibrariesDefaultToDisabledAndNewPreferencesRoundTrip() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(LayoutLibrary())) as? [String: Any])
        json.removeValue(forKey: "dockGuard")
        json["schemaVersion"] = 7
        let old = try JSONDecoder().decode(LayoutLibrary.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!old.dockGuard.enabled)
        var library = old
        library.dockGuard = DockGuardPreferences(enabled: true, preferredDisplayID: "persistent-lg", bypassModifier: .shift)
        #expect(try JSONDecoder().decode(LayoutLibrary.self, from: JSONEncoder().encode(library)).dockGuard == library.dockGuard)
    }
}

@MainActor
struct DockGuardEmergencyTests {
    @Test func emergencyDisableStillDisarmsRuntimeWhenSavingFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = LayoutLibraryPersistence(fileURL: directory.appendingPathComponent("settings.json"))
        try persistence.save(LayoutLibrary(dockGuard: DockGuardPreferences(enabled: true, preferredDisplayID: "missing")))
        let store = SettingsStore(persistence: persistence)
        let guardController = DockGuardController(settingsStore: store)
        // Replace only this disposable test file with a directory to force
        // atomic persistence to fail, without touching real user settings.
        try FileManager.default.removeItem(at: persistence.fileURL)
        try FileManager.default.createDirectory(at: persistence.fileURL, withIntermediateDirectories: false)
        guardController.disableImmediately()
        #expect(!store.library.dockGuard.enabled)
        #expect(guardController.status == "Disabled")
    }

    @Test func dockMenuDisableWorksWithoutEligibleAppOrPermissionsAndDisarmsStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = LayoutLibraryPersistence(fileURL: directory.appendingPathComponent("settings.json"))
        // A disconnected display keeps the test from installing an event tap.
        let preferences = DockGuardPreferences(enabled: true, preferredDisplayID: "missing", bypassModifier: .option)
        try persistence.save(LayoutLibrary(showDockIcon: true, dockGuard: preferences))
        let store = SettingsStore(persistence: persistence)
        let controller = WindowLayoutsController(settingsStore: store)
        let dock = DockIntegrationController(settingsStore: store, windowController: controller)
        let menu = try #require(dock.makeDockMenu())
        let item = try #require(menu.items.first { $0.title == "Disable Dock Guard" })
        #expect(item.isEnabled)
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        #expect(!store.library.dockGuard.enabled)
        #expect(!persistence.load().library.dockGuard.enabled)
        #expect(controller.dockGuardController.status == "Disabled")
    }
}
