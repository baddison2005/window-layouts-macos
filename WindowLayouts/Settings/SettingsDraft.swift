// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine

@MainActor
final class SettingsDraft: ObservableObject {
    @Published var library: LayoutLibrary

    private var baseline: LayoutLibrary

    init(library: LayoutLibrary) {
        self.library = library
        self.baseline = library
    }

    var hasChanges: Bool { library != baseline }

    func reset(from library: LayoutLibrary) {
        self.library = library
        self.baseline = library
    }

    func cancel() {
        library = baseline
    }

    func markApplied(_ library: LayoutLibrary) {
        self.library = library
        self.baseline = library
    }
}
