import Foundation
import os

/// High-integrity security layer ensuring the AI and application operations never touch protected macOS paths
/// and that all file operations comply with approval-based safety rules.
public final class SecurityGuard: Sendable {
    public static let shared = SecurityGuard()
    private static let logger = Logger(subsystem: "com.macguard", category: "SecurityGuard")

    // Hardcoded absolute system paths that can NEVER be modified or deleted
    private let protectedSystemPrefixes: [String] = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/private/etc",
        "/private/var/db",
        "/private/var/root",
        "/private/var/audit",
        "/Volumes",
        "/Network"
    ]

    // Sensitive user directories that must not be deleted by cleanup engine
    private let protectedUserDirectories: Set<String> = [
        ".ssh",
        ".gnupg",
        "Keychains",
        "Accounts",
        "IdentityServices",
        ".git"
    ]

    private init() {}

    public enum SecurityError: LocalizedError, Sendable {
        case protectedPath(String)
        case pathTraversalDetected(String)
        case fileNotFound(String)
        case permissionDenied(String)
        case destructiveActionBlocked(String)

        public var errorDescription: String? {
            switch self {
            case .protectedPath(let path):
                return "Access denied: '\(path)' is a protected macOS system location."
            case .pathTraversalDetected(let path):
                return "Security violation: Path traversal sequence detected in '\(path)'."
            case .fileNotFound(let path):
                return "File does not exist at '\(path)'."
            case .permissionDenied(let path):
                return "Insufficient filesystem permissions for '\(path)'."
            case .destructiveActionBlocked(let reason):
                return "Destructive operation blocked by security policy: \(reason)"
            }
        }
    }

    /// Validates whether a file path is safe to inspect or operate on
    public func validatePath(_ path: String, forModification: Bool = false) throws -> URL {
        // Block path traversal attempts
        if path.contains("../") || path.contains("/..") || path == ".." {
            Self.logger.fault("Path traversal attempt blocked: \(path, privacy: .public)")
            throw SecurityError.pathTraversalDetected(path)
        }

        let standardPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: standardPath).standardized.resolvingSymlinksInPath()
        let resolvedPath = url.path

        // Allow legitimate user temporary directories (/var/folders/...)
        if !resolvedPath.hasPrefix("/var/folders") {
            for prefix in protectedSystemPrefixes {
                if resolvedPath == prefix || resolvedPath.hasPrefix(prefix + "/") {
                    Self.logger.warning("Protected system path access blocked: \(resolvedPath, privacy: .public)")
                    throw SecurityError.protectedPath(resolvedPath)
                }
            }
        }

        // Check if modifying sensitive user directories
        if forModification {
            for component in url.pathComponents {
                if protectedUserDirectories.contains(component) {
                    Self.logger.warning("Protected user directory modification blocked: \(component, privacy: .public)")
                    throw SecurityError.protectedPath(resolvedPath)
                }
            }
        }

        return url
    }

    /// Moves a file safely to the macOS Trash, returning the resulting URL in Trash.
    /// This is strictly preferred over permanent deletion.
    public func safelyMoveToTrash(at url: URL) throws -> URL {
        let validURL = try validatePath(url.path, forModification: true)
        var resultingURL: NSURL?
        
        try FileManager.default.trashItem(at: validURL, resultingItemURL: &resultingURL)
        
        guard let trashedURL = resultingURL as URL? else {
            Self.logger.error("Moved to trash, but did not receive resulting URL for: \(validURL.path, privacy: .public)")
            return validURL
        }
        
        Self.logger.notice("Successfully moved to Trash: \(validURL.path, privacy: .public) -> \(trashedURL.path, privacy: .public)")
        return trashedURL
    }

    /// Safely moves a file from source to destination with non-overwriting guarantee
    public func safelyMoveItem(from sourceURL: URL, to destinationURL: URL) throws {
        let validSource = try validatePath(sourceURL.path, forModification: true)
        let validDestination = try validatePath(destinationURL.path, forModification: true)

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: validSource.path) else {
            throw SecurityError.fileNotFound(validSource.path)
        }

        if fileManager.fileExists(atPath: validDestination.path) {
            throw SecurityError.destructiveActionBlocked("Destination '\(validDestination.path)' already exists. Overwriting is blocked to protect your files.")
        }

        let parentDir = validDestination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try fileManager.moveItem(at: validSource, to: validDestination)
        Self.logger.notice("Successfully moved: \(validSource.path, privacy: .public) -> \(validDestination.path, privacy: .public)")
    }
}
