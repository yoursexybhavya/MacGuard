import Foundation
import os

public enum SafetyTier: String, CaseIterable, Codable, Sendable {
    case safe = "Safe Cleanup"
    case reviewRecommended = "Review Recommended"
    case highRisk = "High Risk"
    case protected = "Protected"

    public var badgeColorName: String {
        switch self {
        case .safe: return "green"
        case .reviewRecommended: return "orange"
        case .highRisk: return "red"
        case .protected: return "gray"
        }
    }
}

public struct CleanupTarget: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let path: String
    public let size: Int64
    public let safetyTier: SafetyTier
    public let category: String
    public let explanation: String
    public var isSelected: Bool

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        size: Int64,
        safetyTier: SafetyTier,
        category: String,
        explanation: String,
        isSelected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.path = url.path
        self.size = size
        self.safetyTier = safetyTier
        self.category = category
        self.explanation = explanation
        self.isSelected = isSelected
    }
}

public final class CleanupEngine: Sendable {
    public static let shared = CleanupEngine()
    private static let logger = Logger(subsystem: "com.macguard", category: "CleanupEngine")

    private init() {}

    /// Discovers all cleanup candidates across safe user-level caches and downloads
    public func discoverCleanupCandidates() -> [CleanupTarget] {
        var targets: [CleanupTarget] = []
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser

        // 1. Xcode DerivedData (Safe)
        let derivedData = homeURL.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if fileManager.fileExists(atPath: derivedData.path) {
            let size = calculateDirectorySize(at: derivedData)
            if size > 10 * 1024 * 1024 { // > 10MB
                targets.append(CleanupTarget(
                    name: "Xcode DerivedData Cache",
                    url: derivedData,
                    size: size,
                    safetyTier: .safe,
                    category: "Developer Caches",
                    explanation: "Build artifacts and intermediate index files safely regenerated during compilation."
                ))
            }
        }

        // 2. User Crash Logs (Safe)
        let diagnosticReports = homeURL.appendingPathComponent("Library/Logs/DiagnosticReports")
        if fileManager.fileExists(atPath: diagnosticReports.path) {
            let size = calculateDirectorySize(at: diagnosticReports)
            if size > 1024 * 1024 { // > 1MB
                targets.append(CleanupTarget(
                    name: "Old System Diagnostic Logs",
                    url: diagnosticReports,
                    size: size,
                    safetyTier: .safe,
                    category: "System Logs",
                    explanation: "Past application crash and diagnostic reports no longer needed for system diagnostics."
                ))
            }
        }

        // 3. User Trash Bin (Review Recommended)
        let trashURL = homeURL.appendingPathComponent(".Trash")
        if fileManager.fileExists(atPath: trashURL.path) {
            let size = calculateDirectorySize(at: trashURL)
            if size > 1024 * 1024 { // > 1MB
                targets.append(CleanupTarget(
                    name: "macOS Trash Contents",
                    url: trashURL,
                    size: size,
                    safetyTier: .reviewRecommended,
                    category: "Trash Bin",
                    explanation: "Files previously moved to Trash waiting to be permanently reclaimed.",
                    isSelected: false // User must review
                ))
            }
        }

        // 4. Old Disk Images & Installers in Downloads (Review Recommended)
        let downloads = homeURL.appendingPathComponent("Downloads")
        if fileManager.fileExists(atPath: downloads.path),
           let items = try? SystemScanner.shared.scanDirectory(at: downloads, recursive: false) {
            for item in items where item.category == .installers {
                targets.append(CleanupTarget(
                    name: item.name,
                    url: item.url,
                    size: item.size,
                    safetyTier: .reviewRecommended,
                    category: "Old Installers",
                    explanation: "Downloaded .dmg/.pkg installer that can usually be safely removed after software installation."
                ))
            }
        }

        return targets.sorted(by: { $0.size > $1.size })
    }

    /// Executes approved cleanups by sending them to macOS Trash (100% reversible) and logging
    public func executeCleanup(targets: [CleanupTarget]) throws {
        let securityGuard = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        for target in targets {
            let resultingTrashURL = try securityGuard.safelyMoveToTrash(at: target.url)
            let record = OperationRecord(
                actionType: .moveToTrash,
                sourcePath: target.path,
                destinationPath: resultingTrashURL.path,
                fileSize: target.size,
                reason: target.explanation
            )
            ledger.recordOperation(record)
        }
        Self.logger.notice("Completed cleanup of \(targets.count, privacy: .public) targets safely to Trash")
    }

    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
