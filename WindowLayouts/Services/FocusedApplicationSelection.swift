// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

nonisolated enum FocusedApplicationSelection {
    static func processIdentifier(
        axFocusedProcessIdentifier: pid_t?,
        workspaceFrontmostProcessIdentifier: pid_t?
    ) -> pid_t? {
        if let axFocusedProcessIdentifier, axFocusedProcessIdentifier > 0 {
            return axFocusedProcessIdentifier
        }
        if let workspaceFrontmostProcessIdentifier,
           workspaceFrontmostProcessIdentifier > 0 {
            return workspaceFrontmostProcessIdentifier
        }
        return nil
    }
}
