// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject var updateController: AppUpdateController

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Window Layouts Experimental")
                        .font(.largeTitle.bold())
                    Text("Your Workspace, Organized Your Way!")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Window Layouts is a native macOS utility for easily creating and applying custom layouts to application windows."
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

                VStack(spacing: 7) {
                    LabeledContent("Version") {
                        Text(
                            "\(updateController.currentVersion.description)-experimental (Build \(updateController.currentBuild))"
                        )
                    }
                    LabeledContent("Author") {
                        Text("Dr. Brett Addison")
                    }
                    LabeledContent("Source code") {
                        Link(
                            "GitHub Repository",
                            destination: updateController.repositoryURL
                        )
                    }
                    LabeledContent("License") {
                        Text("GPL-3.0-or-later")
                    }
                }
                .frame(maxWidth: 500)

                GroupBox("Experimental Build") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            "Space movement is an unsupported, opt-in prototype.",
                            systemImage: "flask.fill"
                        )
                        .foregroundStyle(.orange)

                        Text(
                            "This build has a separate application identity and settings library. Stable update checks and automatic installation are intentionally unavailable so it cannot replace or modify the released Window Layouts app."
                        )
                        .foregroundStyle(.secondary)

                        Link(
                            "View Stable Window Layouts Releases",
                            destination: URL(
                                string: "https://github.com/baddison2005/window-layouts-macos/releases"
                            )!
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(maxWidth: 620)

                Text("No third-party dependencies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }
}
