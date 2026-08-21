// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

@MainActor
struct SettingsDraftTests {
    @Test func cancelDoesNotApplyEditsToTheCanonicalStore() {
        let store = SettingsStore(
            persistence: LayoutLibraryPersistence(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("unused-\(UUID().uuidString).json")
            )
        )
        let draft = SettingsDraft(library: store.library)

        draft.library.layoutPadding = 40
        #expect(draft.hasChanges)
        #expect(store.library.layoutPadding == 0)

        draft.cancel()
        #expect(draft.library == store.library)
        #expect(!draft.hasChanges)
    }
}
