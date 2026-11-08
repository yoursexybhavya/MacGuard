import Foundation
import AppKit
import Combine

/// Manages macOS TCC permissions and Full Disk Access (FDA) status.
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public private(set) var hasFullDiskAccess: Bool = false

    private init() {
        checkPermissions()
    }

    /// Synchronous, non-isolated check for Full Disk Access.
    /// Safely tests access to a protected directory without triggering modal dialogs.
    public nonisolated static var isFullDiskAccessGranted: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testPath = home.appendingPathComponent("Library/Suggestions").path
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: testPath)
            return true
        } catch {
            return false
        }
    }

    /// Updates published permission state on the main thread.
    public func checkPermissions() {
        self.hasFullDiskAccess = Self.isFullDiskAccessGranted
    }

    /// Opens macOS System Settings directly to Privacy & Security > Full Disk Access,
    /// and reveals MacGuard in Finder so the user can easily toggle it on or drag it in.
    public func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }

        // Highlight MacGuard.app in Finder for effortless drag-and-drop into System Settings
        let installedAppURL = URL(fileURLWithPath: "/Applications/MacGuard.app")
        if FileManager.default.fileExists(atPath: installedAppURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([installedAppURL])
        }
    }
}
