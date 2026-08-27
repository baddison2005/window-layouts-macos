// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import OSLog

nonisolated enum AppDiagnostics {
    static let windowOperations = Logger(
        subsystem: "com.astrobrett.WindowLayouts.Experimental",
        category: "WindowOperations"
    )
    static let overlays = Logger(
        subsystem: "com.astrobrett.WindowLayouts.Experimental",
        category: "Overlays"
    )
    static let persistence = Logger(
        subsystem: "com.astrobrett.WindowLayouts.Experimental",
        category: "Persistence"
    )
    static let lifecycle = Logger(
        subsystem: "com.astrobrett.WindowLayouts.Experimental",
        category: "Lifecycle"
    )
}
