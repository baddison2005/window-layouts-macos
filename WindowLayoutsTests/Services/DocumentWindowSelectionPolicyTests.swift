// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import Testing
@testable import WindowLayouts

struct DocumentWindowSelectionPolicyTests {
    @Test func blankWorkbookQualifiesWithoutDocumentURLOrTitleTransition() {
        #expect(DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .unsupported,
            appearedAfterBaseline: false,
            titleChangedAfterBaseline: false,
            baselineComplete: false,
            editorConfirmed: true
        ))
    }

    @Test func chooserThenThemeChooserThenEditorOnlySelectsEditor() {
        let selected = [false, false, true].map { editorReady in
            DocumentWindowSelectionPolicy.shouldSelect(
                documentEvidence: .empty,
                appearedAfterBaseline: true,
                titleChangedAfterBaseline: true,
                baselineComplete: true,
                editorConfirmed: editorReady
            )
        }
        #expect(selected == [false, false, true])
        #expect(!DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .value,
            appearedAfterBaseline: true,
            titleChangedAfterBaseline: true,
            baselineComplete: true,
            editorConfirmed: false
        ))
    }

    @Test func editorChecksCoverBothKeynoteBundleIDsAndOnlyKnownApps() {
        #expect(DocumentWindowSelectionPolicy.editorIdentifiers(for: "com.microsoft.Excel") == ["XLFormulaEditor"])
        for bundle in ["com.apple.Keynote", "com.apple.iWork.Keynote"] {
            #expect(DocumentWindowSelectionPolicy.editorIdentifiers(for: bundle) == ["ToolbarItemAddSlide"])
            #expect(DocumentWindowSelectionPolicy.editorRoles(for: bundle) == ["AXLayoutArea"])
            #expect(
                DocumentWindowSelectionPolicy.editorRoleSignature(for: bundle)
                    == ["AXToolbar", "AXRadioGroup"]
            )
        }
        #expect(DocumentWindowSelectionPolicy.editorIdentifiers(for: "com.microsoft.Word") == nil)
        #expect(DocumentWindowSelectionPolicy.editorRoles(for: "com.microsoft.Word") == nil)
        #expect(DocumentWindowSelectionPolicy.editorRoleSignature(for: "com.microsoft.Word") == nil)
        #expect(
            DocumentWindowSelectionPolicy.editorStabilizationDuration(for: "com.apple.Keynote")
                == .seconds(2)
        )
        #expect(
            DocumentWindowSelectionPolicy.editorStabilizationDuration(for: "com.microsoft.Excel")
                == .milliseconds(500)
        )
    }

    @Test func closedTransitionWindowCanResumeDocumentSelection() {
        #expect(WindowAccessibilityService.isStaleMappedWindowError(
            .accessibilityFailure(
                operation: "reading a window attribute",
                code: AXError.invalidUIElement.rawValue
            )
        ))
        #expect(!WindowAccessibilityService.isStaleMappedWindowError(
            .windowCannotBeMovedOrResized
        ))
    }

    @Test func startScreenIsNeverSelectedFromItsTitleAlone() {
        #expect(!DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .unsupported,
            appearedAfterBaseline: true,
            titleChangedAfterBaseline: false,
            baselineComplete: true
        ))
        #expect(!DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .empty,
            appearedAfterBaseline: false,
            titleChangedAfterBaseline: false,
            baselineComplete: true
        ))
    }

    @Test func savedDocumentCanBeSelectedWithoutWaitingForBaseline() {
        #expect(DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .value,
            appearedAfterBaseline: false,
            titleChangedAfterBaseline: false,
            baselineComplete: false
        ))
    }

    @Test func newlyCreatedWindowIsSelectedAfterStartupBaseline() {
        #expect(DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .empty,
            appearedAfterBaseline: true,
            titleChangedAfterBaseline: false,
            baselineComplete: true
        ))
    }

    @Test func reusedStartWindowRequiresATitleTransition() {
        #expect(!DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .empty,
            appearedAfterBaseline: false,
            titleChangedAfterBaseline: true,
            baselineComplete: false
        ))
        #expect(DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .empty,
            appearedAfterBaseline: false,
            titleChangedAfterBaseline: true,
            baselineComplete: true
        ))
    }

    @Test func transientWindowWithoutDocumentSemanticsIsNeverSelected() {
        #expect(!DocumentWindowSelectionPolicy.shouldSelect(
            documentEvidence: .unsupported,
            appearedAfterBaseline: true,
            titleChangedAfterBaseline: true,
            baselineComplete: true
        ))
    }
}
