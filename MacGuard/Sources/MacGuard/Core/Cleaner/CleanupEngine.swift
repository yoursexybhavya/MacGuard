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

public struct CleanupSubItem: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let path: String
    public let size: Int64
    public let isDirectory: Bool
    public let modificationDate: Date?

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        size: Int64,
        isDirectory: Bool = false,
        modificationDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.path = url.path
        self.size = size
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
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
    public var isDirectory: Bool
    public var subItems: [CleanupSubItem]

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
        isSelected: Bool = true,
        isDirectory: Bool? = nil,
        subItems: [CleanupSubItem] = []
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
        if let isDir = isDirectory {
            self.isDirectory = isDir
        } else {
            var isDirObj: ObjCBool = false
            self.isDirectory = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirObj) && isDirObj.boolValue
        }
        self.subItems = subItems
    }
}

public final class CleanupEngine: Sendable {
    public static let shared = CleanupEngine()
    private static let logger = Logger(subsystem: "com.macguard", category: "CleanupEngine")

    private init() {}

    /// Inspects immediate children of a directory target to enumerate sub-items and their sizes
    public func inspectSubItems(at url: URL, limit: Int = 100) -> [CleanupSubItem] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [CleanupSubItem] = []
        for itemURL in contents.prefix(limit) {
            let values = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey])
            let isDir = values?.isDirectory ?? false
            let modDate = values?.contentModificationDate
            let itemSize: Int64
            if isDir {
                itemSize = calculateDirectorySize(at: itemURL)
            } else {
                itemSize = Int64(values?.fileSize ?? 0)
            }
            items.append(CleanupSubItem(
                name: itemURL.lastPathComponent,
                url: itemURL,
                size: itemSize,
                isDirectory: isDir,
                modificationDate: modDate
            ))
        }
        return items.sorted(by: { $0.size > $1.size })
    }

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
                let subs = inspectSubItems(at: derivedData)
                targets.append(CleanupTarget(
                    name: "Xcode DerivedData Cache",
                    url: derivedData,
                    size: size,
                    safetyTier: .safe,
                    category: "Developer Caches",
                    explanation: "Build artifacts and intermediate index files safely regenerated during compilation.",
                    isDirectory: true,
                    subItems: subs
                ))
            }
        }

        // 2. User Crash Logs (Safe)
        let diagnosticReports = homeURL.appendingPathComponent("Library/Logs/DiagnosticReports")
        if fileManager.fileExists(atPath: diagnosticReports.path) {
            let size = calculateDirectorySize(at: diagnosticReports)
            if size > 1024 * 1024 { // > 1MB
                let subs = inspectSubItems(at: diagnosticReports)
                targets.append(CleanupTarget(
                    name: "Old System Diagnostic Logs",
                    url: diagnosticReports,
                    size: size,
                    safetyTier: .safe,
                    category: "System Logs",
                    explanation: "Past application crash and diagnostic reports no longer needed for system diagnostics.",
                    isDirectory: true,
                    subItems: subs
                ))
            }
        }

        // 3. Old Disk Images & Installers in Downloads (Review Recommended)
        let downloads = homeURL.appendingPathComponent("Downloads")
        if fileManager.fileExists(atPath: downloads.path),
           let items = try? SystemScanner.shared.scanDirectory(at: downloads, recursive: false) {
            for item in items {
                var isDirObj: ObjCBool = false
                let isDir = fileManager.fileExists(atPath: item.url.path, isDirectory: &isDirObj) && isDirObj.boolValue
                let subs = isDir ? inspectSubItems(at: item.url) : []

                if item.category == .installers {
                    targets.append(CleanupTarget(
                        name: item.name,
                        url: item.url,
                        size: item.size,
                        safetyTier: .reviewRecommended,
                        category: "Old Installers",
                        explanation: "Downloaded .dmg/.pkg installer that can usually be safely removed after software installation.",
                        isDirectory: isDir,
                        subItems: subs
                    ))
                } else if item.category == .junk {
                    targets.append(CleanupTarget(
                        name: item.name,
                        url: item.url,
                        size: item.size,
                        safetyTier: .safe,
                        category: "Incomplete & Artifacts",
                        explanation: "Unfinished browser download (.crdownload) or Windows artifact ($RECYCLE.BIN, desktop.ini) safe to remove.",
                        isDirectory: isDir,
                        subItems: subs
                    ))
                }
            }
        }

        return targets.sorted(by: { $0.size > $1.size })
    }

    /// Executes approved cleanups by sending them to macOS Trash (100% reversible) and logging
    @discardableResult
    public func executeCleanup(targets: [CleanupTarget]) throws -> [OperationRecord] {
        let securityGuard = SecurityGuard.shared
        let ledger = RollbackLedger.shared
        var records: [OperationRecord] = []

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
            records.append(record)
        }
        Self.logger.notice("Completed cleanup of \(targets.count, privacy: .public) targets safely to Trash")
        return records
    }

    public func calculateDirectorySize(at url: URL) -> Int64 {
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
