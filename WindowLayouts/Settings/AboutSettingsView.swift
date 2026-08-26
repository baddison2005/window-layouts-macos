// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject var updateController: AppUpdateController
    @State private var updateToConfirm: AvailableAppUpdate?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Window Layouts")
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
                            "\(updateController.currentVersion.description) (Build \(updateController.currentBuild))"
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

                GroupBox("Software Update") {
                    VStack(alignment: .leading, spacing: 12) {
                        updateStatus

                        HStack {
                            Button("Check for Updates") {
                                updateController.checkForUpdates()
                            }
                            .disabled(isBusy)

                            if case .available(let release) = updateController.state {
                                Button(
                                    updateController.automaticInstallationAvailable
                                        ? "Download and Install"
                                        : "View Release"
                                ) {
                                    if updateController.automaticInstallationAvailable {
                                        updateToConfirm = release
                                    } else {
                                        updateController.openReleasePage(release)
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Link("Release Notes", destination: release.pageURL)
                            } else if case .failed = updateController.state,
                                      let release = updateController.lastAvailableUpdate {
                                Button("View Release") {
                                    updateController.openReleasePage(release)
                                }
                            }

                            Spacer()
                        }

                        Text(
                            "Update checks contact only the public Window Layouts GitHub repository. Automatic installation verifies the release SHA-256 digest, application identity, Developer ID signature, and Gatekeeper assessment before replacing the installed app."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .confirmationDialog(
            "Install Window Layouts \(updateToConfirm?.version.description ?? "")?",
            isPresented: Binding(
                get: { updateToConfirm != nil },
                set: { if !$0 { updateToConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let release = updateToConfirm {
                Button("Download, Install, and Relaunch") {
                    updateToConfirm = nil
                    updateController.install(release)
                }
            }
            Button("Cancel", role: .cancel) {
                updateToConfirm = nil
            }
        } message: {
            Text(
                "Window Layouts will verify the download, replace the copy in Applications, and relaunch. Your layouts and shortcuts will be preserved."
            )
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateController.state {
        case .idle:
            Text("Check GitHub for a newer stable release of Window Layouts.")
                .foregroundStyle(.secondary)
        case .checking:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates…")
            }
        case .upToDate:
            Label(
                "Window Layouts \(updateController.currentVersion.description) is up to date.",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .available(let release):
            Label(
                "Window Layouts \(release.version.description) is available.",
                systemImage: "arrow.down.circle.fill"
            )
        case .downloading(let release):
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading Window Layouts \(release.version.description)…")
            }
        case .installing(let release):
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Verifying and installing Window Layouts \(release.version.description)…")
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var isBusy: Bool {
        switch updateController.state {
        case .checking, .downloading, .installing:
            true
        default:
            false
        }
    }
}
