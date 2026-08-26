// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WindowLayouts

struct AppUpdateServiceTests {
    @Test func selectsOnlyTheExpectedNewerSignedArchiveMetadata() throws {
        let release = makeRelease(version: "v1.2.0")
        let availability = try GitHubAppUpdateService.availability(
            for: release,
            currentVersion: SemanticVersion("1.1.1")!
        )

        guard case .available(let update) = availability else {
            Issue.record("Expected an available update")
            return
        }
        #expect(update.version == SemanticVersion("1.2.0"))
        #expect(update.archive.name == "Window-Layouts-1.2.0-macOS.zip")
        #expect(update.sha256 == String(repeating: "a", count: 64))
    }

    @Test func equalOrOlderPublishedVersionIsUpToDate() throws {
        for tag in ["v1.2.0", "v1.1.9"] {
            let availability = try GitHubAppUpdateService.availability(
                for: makeRelease(version: tag),
                currentVersion: SemanticVersion("1.2.0")!
            )
            guard case .upToDate = availability else {
                Issue.record("Expected \(tag) not to be offered")
                continue
            }
        }
    }

    @Test func rejectsDraftPrereleaseAndMalformedTags() {
        #expect(throws: AppUpdateError.invalidRelease) {
            try GitHubAppUpdateService.availability(
                for: makeRelease(version: "v1.2.0", draft: true),
                currentVersion: SemanticVersion("1.1.1")!
            )
        }
        #expect(throws: AppUpdateError.invalidRelease) {
            try GitHubAppUpdateService.availability(
                for: makeRelease(version: "v1.2.0", prerelease: true),
                currentVersion: SemanticVersion("1.1.1")!
            )
        }
        for tag in ["latest", "1.2.0", "V1.2.0", "v01.2.0"] {
            #expect(throws: AppUpdateError.invalidRelease) {
                try GitHubAppUpdateService.availability(
                    for: makeRelease(version: tag),
                    currentVersion: SemanticVersion("1.1.1")!
                )
            }
        }
    }

    @Test func rejectsUnexpectedAssetIdentityAndMissingDigest() {
        #expect(throws: AppUpdateError.missingInstaller) {
            try GitHubAppUpdateService.availability(
                for: makeRelease(version: "v1.2.0", archiveName: "other.zip"),
                currentVersion: SemanticVersion("1.1.1")!
            )
        }
        #expect(throws: AppUpdateError.unsafeDownloadURL) {
            try GitHubAppUpdateService.availability(
                for: makeRelease(
                    version: "v1.2.0",
                    downloadURL: URL(string: "https://example.com/update.zip")!
                ),
                currentVersion: SemanticVersion("1.1.1")!
            )
        }
        #expect(throws: AppUpdateError.missingDigest) {
            try GitHubAppUpdateService.availability(
                for: makeRelease(version: "v1.2.0", digest: nil),
                currentVersion: SemanticVersion("1.1.1")!
            )
        }
    }

    @Test func automaticInstallationRequiresTheCanonicalApplicationsPath() {
        #expect(AppUpdateInstaller.supportsAutomaticInstallation(
            at: URL(fileURLWithPath: "/Applications/Window Layouts.app")
        ))
        #expect(!AppUpdateInstaller.supportsAutomaticInstallation(
            at: URL(fileURLWithPath: "/tmp/Window Layouts.app")
        ))
    }

    private func makeRelease(
        version: String,
        draft: Bool = false,
        prerelease: Bool = false,
        archiveName: String? = nil,
        downloadURL: URL? = nil,
        digest: String? = "sha256:" + String(repeating: "a", count: 64)
    ) -> GitHubRelease {
        let normalizedVersion = String(version.drop(while: { $0 == "v" || $0 == "V" }))
        let expectedName = archiveName ?? "Window-Layouts-\(normalizedVersion)-macOS.zip"
        let resolvedDownloadURL = downloadURL ?? URL(
            string: "https://github.com/baddison2005/window-layouts-macos/releases/download/\(version)/\(expectedName)"
        )!
        return GitHubRelease(
            tagName: version,
            pageURL: URL(
                string: "https://github.com/baddison2005/window-layouts-macos/releases/tag/\(version)"
            )!,
            draft: draft,
            prerelease: prerelease,
            assets: [
                AppUpdateAsset(
                    name: expectedName,
                    downloadURL: resolvedDownloadURL,
                    contentType: "application/zip",
                    size: 800_000,
                    digest: digest
                )
            ]
        )
    }
}
