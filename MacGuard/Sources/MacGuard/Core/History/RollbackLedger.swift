import Foundation
import Combine
import os

public struct OperationRecord: Identifiable, Codable, Sendable {
    public enum ActionType: String, Codable, Sendable {
        case moveToTrash = "Move to Trash"
        case moveFile = "Move File"
        case createDirectory = "Create Folder"
    }

    public let id: UUID
    public let timestamp: Date
    public let actionType: ActionType
    public let sourcePath: String
    public let destinationPath: String?
    public let fileSize: Int64?
    public let reason: String
    public var isRolledBack: Bool

    public var isReversible: Bool {
        return !isRolledBack
    }

    // MARK: - UI Helpers

    public var fileName: String {
        URL(fileURLWithPath: sourcePath).lastPathComponent
    }

    public var formattedSize: String {
        guard let size = fileSize, size > 0 else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private static let staticDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    public var formattedDate: String {
        Self.staticDateFormatter.string(from: timestamp)
    }

    public var systemImageName: String {
        switch actionType {
        case .moveToTrash:
            return "trash"
        case .moveFile:
            return "arrow.right.circle"
        case .createDirectory:
            return "folder.badge.plus"
        }
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        actionType: ActionType,
        sourcePath: String,
        destinationPath: String? = nil,
        fileSize: Int64? = nil,
        reason: String,
        isRolledBack: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actionType = actionType
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.fileSize = fileSize
        self.reason = reason
        self.isRolledBack = isRolledBack
    }
}

// MARK: - Operation Filter Types (Feature F17)

public enum OperationFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case trash = "Trash"
    case organize = "Organize"
    case consolidated = "Consolidated"
    case aiMaintenance = "AI Maintenance"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "tray.2"
        case .trash: return "trash"
        case .organize: return "folder.badge.gearshape"
        case .consolidated: return "arrow.triangle.merge"
        case .aiMaintenance: return "sparkles"
        }
    }
}

extension OperationRecord {
    /// Dynamically resolves byte-accurate file size, falling back to disk query if metadata was absent
    public var byteAccurateSize: Int64? {
        if let size = fileSize, size > 0 {
            return size
        }
        let checkPath = destinationPath ?? sourcePath
        if let attrs = try? FileManager.default.attributesOfItem(atPath: checkPath),
           let size = attrs[.size] as? Int64, size > 0 {
            return size
        }
        return fileSize
    }

    /// Formatted exact byte count string for tooltips and inspect popovers (e.g. "14,882,912 bytes")
    public var exactByteCountDescription: String {
        guard let size = byteAccurateSize ?? fileSize, size > 0 else {
            return "0 bytes"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: size)) ?? "\(size)") + " bytes"
    }

    /// Evaluates whether this record matches the specified filter chip
    public func matches(filter: OperationFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .trash:
            return actionType == .moveToTrash
        case .organize:
            return actionType == .moveFile || actionType == .createDirectory || reason.localizedCaseInsensitiveContains("organiz")
        case .consolidated:
            return reason.localizedCaseInsensitiveContains("consolidat")
        case .aiMaintenance:
            return reason.localizedCaseInsensitiveContains("ai assistant") ||
                   reason.localizedCaseInsensitiveContains("ai maintenance") ||
                   reason.localizedCaseInsensitiveContains("assistant")
        }
    }
}

public final class RollbackLedger: ObservableObject, @unchecked Sendable {
    public static let shared = RollbackLedger()
    private static let logger = Logger(subsystem: "com.macguard", category: "RollbackLedger")

    private let ledgerURL: URL
    private let lock = NSLock()
    private var inMemoryRecords: [OperationRecord] = []

    @Published public private(set) var operations: [OperationRecord] = []

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let macGuardDir = appSupport.appendingPathComponent("MacGuard", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: macGuardDir.path) {
            try? FileManager.default.createDirectory(at: macGuardDir, withIntermediateDirectories: true)
        }
        self.ledgerURL = macGuardDir.appendingPathComponent("operations_ledger.json")
        let loaded = Self.readRecordsFromDisk(at: ledgerURL)
        self.inMemoryRecords = loaded
        self.operations = loaded
    }

    public func loadHistory() -> [OperationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryRecords
    }

    /// Re-reads the operations ledger from disk and updates reactive published state
    public func reloadFromDisk() {
        lock.lock()
        let loaded = Self.readRecordsFromDisk(at: ledgerURL)
        self.inMemoryRecords = loaded
        lock.unlock()
        updatePublishedOperations(loaded)
    }

    /// Reactive accessor returning the operations list in reverse chronological order
    public var recentOperations: [OperationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryRecords
    }

    public func recordOperation(_ record: OperationRecord) {
        lock.lock()
        defer { lock.unlock() }

        var current = inMemoryRecords
        current.insert(record, at: 0)
        self.inMemoryRecords = current
        saveHistoryToDisk(current)
        updatePublishedOperations(current)
        Self.logger.info("Recorded operation \(record.id.uuidString, privacy: .public): \(record.actionType.rawValue, privacy: .public)")
    }

    @discardableResult
    public func recordOperation(
        actionType: OperationRecord.ActionType,
        sourcePath: String,
        destinationPath: String? = nil,
        fileSize: Int64? = nil,
        reason: String
    ) -> OperationRecord {
        var resolvedSize = fileSize
        if resolvedSize == nil || resolvedSize == 0 {
            let checkPath = destinationPath ?? sourcePath
            if let attrs = try? FileManager.default.attributesOfItem(atPath: checkPath),
               let size = attrs[.size] as? Int64, size > 0 {
                resolvedSize = size
            }
        }

        let record = OperationRecord(
            actionType: actionType,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            fileSize: resolvedSize,
            reason: reason
        )
        recordOperation(record)
        return record
    }

    @discardableResult
    public func rollback(operationId: UUID) throws -> URL {
        try performRollback(forId: operationId)
    }

    @discardableResult
    public func rollback(recordId: UUID) throws -> URL {
        try performRollback(forId: recordId)
    }

    @discardableResult
    public func rollbackAll(recordIds: [UUID]) throws -> Int {
        guard !recordIds.isEmpty else { return 0 }

        lock.lock()
        defer { lock.unlock() }

        var records = inMemoryRecords
        let targetIdSet = Set(recordIds)

        // Sort eligible records in reverse-chronological order (newest first)
        let eligibleIndices = records.indices
            .filter { targetIdSet.contains(records[$0].id) && !records[$0].isRolledBack }
            .sorted { records[$0].timestamp > records[$1].timestamp }

        guard !eligibleIndices.isEmpty else { return 0 }

        var rolledBackCount = 0
        var errors: [(UUID, Error)] = []

        for index in eligibleIndices {
            var record = records[index]
            do {
                _ = try performRollbackFilesystemAction(for: &record)
                record.isRolledBack = true
                records[index] = record
                rolledBackCount += 1
            } catch {
                Self.logger.error("Failed to rollback operation \(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                errors.append((record.id, error))
            }
        }

        if rolledBackCount > 0 {
            self.inMemoryRecords = records
            saveHistoryToDisk(records)
            updatePublishedOperations(records)
        }

        if !errors.isEmpty && rolledBackCount == 0 {
            throw errors[0].1
        }

        return rolledBackCount
    }

    // MARK: - Internal Filesystem Action & Collision Resolution

    private func performRollback(forId recordId: UUID) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        var records = inMemoryRecords
        guard let index = records.firstIndex(where: { $0.id == recordId }) else {
            throw NSError(domain: "MacGuard", code: 404, userInfo: [NSLocalizedDescriptionKey: "Operation record not found for id \(recordId)"])
        }

        var record = records[index]
        guard !record.isRolledBack else {
            throw NSError(domain: "MacGuard", code: 400, userInfo: [NSLocalizedDescriptionKey: "Operation has already been rolled back"])
        }

        let restoredURL = try performRollbackFilesystemAction(for: &record)

        record.isRolledBack = true
        records[index] = record
        self.inMemoryRecords = records
        saveHistoryToDisk(records)
        updatePublishedOperations(records)
        Self.logger.notice("Successfully rolled back operation \(recordId.uuidString, privacy: .public) to \(restoredURL.path, privacy: .public)")
        return restoredURL
    }

    private func performRollbackFilesystemAction(for record: inout OperationRecord) throws -> URL {
        let fileManager = FileManager.default
        let securityGuard = SecurityGuard.shared

        switch record.actionType {
        case .moveFile:
            guard let dest = record.destinationPath else {
                throw NSError(domain: "MacGuard", code: 400, userInfo: [NSLocalizedDescriptionKey: "Move operation record missing destination path"])
            }
            let currentURL = URL(fileURLWithPath: dest)
            guard fileManager.fileExists(atPath: currentURL.path) else {
                throw NSError(domain: "MacGuard", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target file no longer exists at destination '\(dest)'"])
            }

            let desiredURL = URL(fileURLWithPath: record.sourcePath)
            let destinationURL = Self.resolveNonCollidingURL(for: desiredURL)
            try securityGuard.safelyMoveItem(from: currentURL, to: destinationURL)
            return destinationURL

        case .moveToTrash:
            guard let dest = record.destinationPath else {
                throw NSError(domain: "MacGuard", code: 400, userInfo: [NSLocalizedDescriptionKey: "File is in macOS Trash. Please open Trash to restore it directly."])
            }
            guard fileManager.fileExists(atPath: dest) else {
                throw NSError(domain: "MacGuard", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target file no longer exists in macOS Trash at '\(dest)'"])
            }

            let currentURL = URL(fileURLWithPath: dest)
            let desiredURL = URL(fileURLWithPath: record.sourcePath)
            let destinationURL = Self.resolveNonCollidingURL(for: desiredURL)
            try securityGuard.safelyMoveItem(from: currentURL, to: destinationURL)
            return destinationURL

        case .createDirectory:
            let dirURL = URL(fileURLWithPath: record.sourcePath)
            if fileManager.fileExists(atPath: dirURL.path) {
                let contents = (try? fileManager.contentsOfDirectory(atPath: dirURL.path)) ?? []
                if contents.isEmpty {
                    _ = try? securityGuard.safelyMoveToTrash(at: dirURL)
                } else {
                    Self.logger.warning("Directory at '\(dirURL.path)' is not empty; skipping deletion on rollback to prevent data loss")
                }
            }
            return dirURL
        }
    }

    /// Resolves a non-colliding file destination URL by appending numeric suffixes if the file already exists.
    public static func resolveNonCollidingURL(for url: URL, suffix: String = "Restored") -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let parentDir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent

        let initialSuffix = suffix.isEmpty ? " (1)" : " (\(suffix))"
        let initialCandidate = parentDir.appendingPathComponent(
            ext.isEmpty ? "\(base)\(initialSuffix)" : "\(base)\(initialSuffix).\(ext)"
        )
        if !fileManager.fileExists(atPath: initialCandidate.path) {
            return initialCandidate
        }

        var index = 2
        while true {
            let numberedSuffix = suffix.isEmpty ? " (\(index))" : " (\(suffix) \(index))"
            let candidate = parentDir.appendingPathComponent(
                ext.isEmpty ? "\(base)\(numberedSuffix)" : "\(base)\(numberedSuffix).\(ext)"
            )
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    // MARK: - Persistence & Thread-Safe Publishing

    private func updatePublishedOperations(_ records: [OperationRecord]) {
        if Thread.isMainThread {
            self.operations = records
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.operations = records
            }
        }
    }

    private static func readRecordsFromDisk(at url: URL) -> [OperationRecord] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([OperationRecord].self, from: data) else {
            return []
        }
        return records.sorted(by: { $0.timestamp > $1.timestamp })
    }

    private func saveHistoryToDisk(_ records: [OperationRecord]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: ledgerURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist operation ledger: \(error.localizedDescription, privacy: .public)")
        }
    }
}
