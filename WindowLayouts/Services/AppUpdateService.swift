// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import Security

nonisolated struct AppUpdateAsset: Decodable, Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let contentType: String
    let size: Int
    let digest: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case contentType = "content_type"
        case size
        case digest
    }
}

nonisolated struct GitHubRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let pageURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [AppUpdateAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

nonisolated struct AvailableAppUpdate: Equatable, Sendable {
    let version: SemanticVersion
    let pageURL: URL
    let archive: AppUpdateAsset
    let sha256: String
}

nonisolated enum AppUpdateAvailability: Equatable, Sendable {
    case upToDate(latestVersion: SemanticVersion)
    case available(AvailableAppUpdate)
}

nonisolated enum AppUpdateError: Error, Equatable, LocalizedError, Sendable {
    case invalidCurrentVersion
    case invalidResponse
    case invalidRelease
    case missingInstaller
    case unsafeDownloadURL
    case missingDigest
    case downloadTooLarge
    case downloadFailed
    case digestMismatch
    case extractionFailed
    case invalidApplication
    case signatureRejected
    case automaticInstallationUnavailable
    case installationFailed
    case relaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            String(localized: "The installed version could not be identified.")
        case .invalidResponse:
            String(localized: "GitHub returned an invalid update response.")
        case .invalidRelease:
            String(localized: "The latest GitHub release has an invalid version.")
        case .missingInstaller:
            String(localized: "The latest release does not contain the expected macOS application archive.")
        case .unsafeDownloadURL:
            String(localized: "The update download address is not trusted.")
        case .missingDigest:
            String(localized: "The update does not include a verifiable SHA-256 digest.")
        case .downloadTooLarge:
            String(localized: "The update is larger than the permitted download size.")
        case .downloadFailed:
            String(localized: "The update could not be downloaded.")
        case .digestMismatch:
            String(localized: "The downloaded update did not match GitHub’s SHA-256 digest.")
        case .extractionFailed:
            String(localized: "The downloaded update could not be extracted.")
        case .invalidApplication:
            String(localized: "The downloaded application has unexpected identity or version information.")
        case .signatureRejected:
            String(localized: "The downloaded application was not signed by the Window Layouts developer identity.")
        case .automaticInstallationUnavailable:
            String(localized: "Automatic installation is available only when Window Layouts is running from Applications.")
        case .installationFailed:
            String(localized: "The update could not be installed. The existing application was preserved.")
        case .relaunchFailed:
            String(localized: "The update was installed but could not be relaunched.")
        }
    }
}

actor GitHubAppUpdateService {
    static let repositoryURL = URL(
        string: "https://github.com/baddison2005/window-layouts-macos"
    )!
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/baddison2005/window-layouts-macos/releases/latest"
    )!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(currentVersion: SemanticVersion) async throws -> AppUpdateAvailability {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Window-Layouts-macOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              data.count <= 1_000_000 else {
            throw AppUpdateError.invalidResponse
        }
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw AppUpdateError.invalidResponse
        }
        return try Self.availability(for: release, currentVersion: currentVersion)
    }

    nonisolated static func availability(
        for release: GitHubRelease,
        currentVersion: SemanticVersion
    ) throws -> AppUpdateAvailability {
        guard !release.draft, !release.prerelease,
              let releaseVersion = SemanticVersion(release.tagName),
              release.tagName == "v\(releaseVersion)" else {
            throw AppUpdateError.invalidRelease
        }
        guard release.pageURL.scheme == "https",
              release.pageURL.host == "github.com",
              release.pageURL.path == "/baddison2005/window-layouts-macos/releases/tag/\(release.tagName)" else {
            throw AppUpdateError.unsafeDownloadURL
        }
        guard releaseVersion > currentVersion else {
            return .upToDate(latestVersion: releaseVersion)
        }

        let expectedName = "Window-Layouts-\(releaseVersion)-macOS.zip"
        guard let archive = release.assets.first(where: {
            $0.name == expectedName && $0.contentType == "application/zip"
        }) else {
            throw AppUpdateError.missingInstaller
        }
        guard archive.size > 0, archive.size <= AppUpdateInstaller.maximumArchiveSize else {
            throw AppUpdateError.downloadTooLarge
        }
        guard archive.downloadURL.scheme == "https",
              archive.downloadURL.host == "github.com",
              archive.downloadURL.path == "/baddison2005/window-layouts-macos/releases/download/\(release.tagName)/\(expectedName)" else {
            throw AppUpdateError.unsafeDownloadURL
        }
        guard let digest = archive.digest?.lowercased(),
              digest.hasPrefix("sha256:"),
              digest.count == 71,
              digest.dropFirst(7).allSatisfy({ $0.isHexDigit }) else {
            throw AppUpdateError.missingDigest
        }

        return .available(
            AvailableAppUpdate(
                version: releaseVersion,
                pageURL: release.pageURL,
                archive: archive,
                sha256: String(digest.dropFirst(7))
            )
        )
    }
}

nonisolated struct PreparedAppUpdate: Sendable {
    let release: AvailableAppUpdate
    let applicationURL: URL
    let workingDirectory: URL
}

nonisolated struct InstalledAppUpdate: Sendable {
    let applicationURL: URL
    let backupURL: URL
    let workingDirectory: URL
}

actor AppUpdateInstaller {
    static let maximumArchiveSize = 50_000_000
    static let pendingBackupDefaultsKey = "pendingAppUpdateBackupPath"

    private static let expectedBundleIdentifier = "com.astrobrett.WindowLayouts"
    private static let expectedTeamIdentifier = "SRNLN9U724"
    private static let installedApplicationURL = URL(
        fileURLWithPath: "/Applications/Window Layouts.app",
        isDirectory: true
    )

    func prepare(_ release: AvailableAppUpdate) async throws -> PreparedAppUpdate {
        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("window-layouts-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        do {
            let (temporaryDownload, response) = try await URLSession.shared.download(
                from: release.archive.downloadURL
            )
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200 else {
                throw AppUpdateError.downloadFailed
            }
            let archiveURL = workingDirectory.appendingPathComponent("update.zip")
            try fileManager.moveItem(at: temporaryDownload, to: archiveURL)
            let attributes = try fileManager.attributesOfItem(atPath: archiveURL.path)
            guard let byteCount = attributes[.size] as? NSNumber,
                  byteCount.intValue == release.archive.size,
                  byteCount.intValue <= Self.maximumArchiveSize else {
                throw AppUpdateError.downloadFailed
            }
            let data = try Data(contentsOf: archiveURL, options: [.mappedIfSafe])
            let actualDigest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actualDigest == release.sha256 else {
                throw AppUpdateError.digestMismatch
            }

            let extractionURL = workingDirectory.appendingPathComponent(
                "extracted",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: extractionURL,
                withIntermediateDirectories: true
            )
            try Self.run(
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archiveURL.path, extractionURL.path],
                failure: .extractionFailed
            )
            let applicationURL = extractionURL.appendingPathComponent(
                "Window Layouts.app",
                isDirectory: true
            )
            try Self.validateApplication(
                at: applicationURL,
                expectedVersion: release.version
            )
            return PreparedAppUpdate(
                release: release,
                applicationURL: applicationURL,
                workingDirectory: workingDirectory
            )
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            throw error
        }
    }

    func install(
        _ prepared: PreparedAppUpdate,
        currentApplicationURL: URL
    ) throws -> InstalledAppUpdate {
        let fileManager = FileManager.default
        let currentURL = currentApplicationURL.resolvingSymlinksInPath().standardizedFileURL
        guard currentURL == Self.installedApplicationURL,
              fileManager.isWritableFile(atPath: currentURL.deletingLastPathComponent().path) else {
            throw AppUpdateError.automaticInstallationUnavailable
        }

        let cacheRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("com.astrobrett.WindowLayouts/Updates", isDirectory: true)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        let backupURL = cacheRoot.appendingPathComponent(
            "Window Layouts-previous-\(identifier).app",
            isDirectory: true
        )
        let stagedURL = currentURL.deletingLastPathComponent().appendingPathComponent(
            ".Window Layouts-update-\(identifier).app",
            isDirectory: true
        )

        do {
            try Self.run(
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: [prepared.applicationURL.path, stagedURL.path],
                failure: .installationFailed
            )
            try Self.validateApplication(
                at: stagedURL,
                expectedVersion: prepared.release.version
            )
            try fileManager.moveItem(at: currentURL, to: backupURL)
            do {
                try fileManager.moveItem(at: stagedURL, to: currentURL)
                try Self.validateApplication(
                    at: currentURL,
                    expectedVersion: prepared.release.version
                )
            } catch {
                if fileManager.fileExists(atPath: currentURL.path) {
                    try? fileManager.moveItem(
                        at: currentURL,
                        to: prepared.workingDirectory.appendingPathComponent(
                            "failed-install.app",
                            isDirectory: true
                        )
                    )
                }
                try fileManager.moveItem(at: backupURL, to: currentURL)
                throw AppUpdateError.installationFailed
            }
            return InstalledAppUpdate(
                applicationURL: currentURL,
                backupURL: backupURL,
                workingDirectory: prepared.workingDirectory
            )
        } catch {
            if fileManager.fileExists(atPath: stagedURL.path) {
                try? fileManager.removeItem(at: stagedURL)
            }
            throw error
        }
    }

    func rollback(_ installed: InstalledAppUpdate) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: installed.backupURL.path) else { return }
        if fileManager.fileExists(atPath: installed.applicationURL.path) {
            try? fileManager.moveItem(
                at: installed.applicationURL,
                to: installed.workingDirectory.appendingPathComponent(
                    "failed-relaunch.app",
                    isDirectory: true
                )
            )
        }
        try? fileManager.moveItem(
            at: installed.backupURL,
            to: installed.applicationURL
        )
    }

    static func supportsAutomaticInstallation(at applicationURL: URL) -> Bool {
        applicationURL.resolvingSymlinksInPath().standardizedFileURL
            == installedApplicationURL
    }

    static func cleanPendingBackup(defaults: UserDefaults = .standard) {
        guard let path = defaults.string(forKey: pendingBackupDefaultsKey) else { return }
        defaults.removeObject(forKey: pendingBackupDefaultsKey)

        let fileManager = FileManager.default
        guard let caches = try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let allowedRoot = caches.appendingPathComponent(
            "com.astrobrett.WindowLayouts/Updates",
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let candidate = URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        guard candidate.deletingLastPathComponent() == allowedRoot,
              candidate.lastPathComponent.hasPrefix("Window Layouts-previous-"),
              candidate.pathExtension == "app" else { return }
        try? fileManager.removeItem(at: candidate)
    }

    private static func validateApplication(
        at applicationURL: URL,
        expectedVersion: SemanticVersion
    ) throws {
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = plist as? [String: Any],
              info["CFBundleIdentifier"] as? String == expectedBundleIdentifier,
              let versionString = info["CFBundleShortVersionString"] as? String,
              SemanticVersion(versionString) == expectedVersion else {
            throw AppUpdateError.invalidApplication
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            applicationURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
        let staticCode else {
            throw AppUpdateError.signatureRejected
        }

        let requirementText = "anchor apple generic and identifier \"\(expectedBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess,
        let requirement else {
            throw AppUpdateError.signatureRejected
        }

        let flags = SecCSFlags(rawValue:
            kSecCSCheckAllArchitectures
                | kSecCSCheckNestedCode
                | kSecCSStrictValidate
                | kSecCSCheckGatekeeperArchitectures
                | kSecCSRestrictSymlinks
                | kSecCSRestrictToAppLike
        )
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw AppUpdateError.signatureRejected
        }
        try run(
            executable: URL(fileURLWithPath: "/usr/sbin/spctl"),
            arguments: ["--assess", "--type", "execute", applicationURL.path],
            failure: .signatureRejected
        )
    }

    private static func run(
        executable: URL,
        arguments: [String],
        failure: AppUpdateError
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw failure
        }
        guard process.terminationReason == .exit,
              process.terminationStatus == 0 else {
            throw failure
        }
    }
}
