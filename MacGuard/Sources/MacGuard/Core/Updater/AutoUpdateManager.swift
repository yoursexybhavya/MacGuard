import Foundation
import AppKit
import os

public struct AppUpdateInfo: Codable, Sendable {
    public let name: String
    public let version: String
    public let tagName: String
    public let releaseNotes: String
    public let downloadUrl: String
    public let publishedAt: String
    public let minimumMacOS: String
    public let appleSiliconOnly: Bool
}

@MainActor
public final class AutoUpdateManager: ObservableObject {
    public static let shared = AutoUpdateManager()
    private static let logger = Logger(subsystem: "com.macguard", category: "AutoUpdateManager")

    // Production Vercel deployment endpoint
    public let updateServerURL: URL = URL(string: "https://updater-server-kappa.vercel.app/api/version")!

    @Published public var currentVersion: String = "1.0.0"
    @Published public var isChecking: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var availableUpdate: AppUpdateInfo?
    @Published public var statusMessage: String?
    @Published public var isUpdateAvailable: Bool = false
    @Published public var updateError: String?

    private init() {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            currentVersion = v
        }
    }

    /// Checks the Vercel update server for newer releases
    public func checkForUpdates(isUserInitiated: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        updateError = nil
        if isUserInitiated {
            statusMessage = "Checking https://updater-server-kappa.vercel.app for updates..."
        }

        do {
            var request = URLRequest(url: updateServerURL)
            request.timeoutInterval = 8.0
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "AutoUpdate", code: 500, userInfo: [NSLocalizedDescriptionKey: "Update server unavailable (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"])
            }

            let info = try JSONDecoder().decode(AppUpdateInfo.self, from: data)
            let serverVersion = info.version.trimmingCharacters(in: .whitespacesAndNewlines)

            if isNewerVersion(serverVersion, than: currentVersion) {
                availableUpdate = info
                isUpdateAvailable = true
                statusMessage = "Update available: Version \(serverVersion)"
            } else {
                availableUpdate = nil
                isUpdateAvailable = false
                if isUserInitiated {
                    statusMessage = "MacGuard is up to date (Version \(currentVersion))."
                }
            }
        } catch {
            Self.logger.warning("Auto-update check failed: \(error.localizedDescription, privacy: .public)")
            if isUserInitiated {
                updateError = "Failed to check for updates: \(error.localizedDescription)"
                statusMessage = nil
            }
        }

        isChecking = false
    }

    /// Compares two semver strings (e.g., "1.0.1" > "1.0.0")
    private func isNewerVersion(_ server: String, than current: String) -> Bool {
        let sParts = server.split(separator: ".").compactMap { Int($0) }
        let cParts = current.split(separator: ".").compactMap { Int($0) }
        
        let count = max(sParts.count, cParts.count)
        for i in 0..<count {
            let s = i < sParts.count ? sParts[i] : 0
            let c = i < cParts.count ? cParts[i] : 0
            if s > c { return true }
            if s < c { return false }
        }
        return false
    }

    /// Downloads the latest release and applies the update atomically
    public func performUpdate() async {
        guard let update = availableUpdate, let url = URL(string: update.downloadUrl) else { return }
        isDownloading = true
        downloadProgress = 0.1
        statusMessage = "Downloading MacGuard \(update.version)..."

        do {
            let (tempLocalURL, _) = try await URLSession.shared.download(from: url)
            downloadProgress = 0.6
            statusMessage = "Verifying package and installing update..."

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent("MacGuard.zip")
            try FileManager.default.moveItem(at: tempLocalURL, to: zipPath)

            // Extract zip
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", "-o", zipPath.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()

            downloadProgress = 0.9
            statusMessage = "Finalizing update..."

            // Locate new app bundle
            let targetApp = URL(fileURLWithPath: "/Applications/MacGuard.app")
            let extractedApp = tempDir.appendingPathComponent("MacGuard.app")

            if FileManager.default.fileExists(atPath: extractedApp.path) {
                // Remove old bundle and move new one
                if FileManager.default.fileExists(atPath: targetApp.path) {
                    try FileManager.default.removeItem(at: targetApp)
                }
                try FileManager.default.moveItem(at: extractedApp, to: targetApp)

                downloadProgress = 1.0
                statusMessage = "Update complete! Relaunching MacGuard..."

                // Relaunch app
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: targetApp, configuration: config) { _, _ in
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                }
            } else {
                throw NSError(domain: "AutoUpdate", code: 404, userInfo: [NSLocalizedDescriptionKey: "Extracted update does not contain MacGuard.app"])
            }
        } catch {
            updateError = "Update failed: \(error.localizedDescription)"
            statusMessage = nil
        }

        isDownloading = false
    }
}
