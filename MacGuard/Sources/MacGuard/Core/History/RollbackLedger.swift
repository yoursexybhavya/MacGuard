import Foundation
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
    public let fileSize: Int64
    public let reason: String
    public var isRolledBack: Bool

    public var isReversible: Bool {
        return !isRolledBack
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        actionType: ActionType,
        sourcePath: String,
        destinationPath: String? = nil,
        fileSize: Int64 = 0,
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

public final class RollbackLedger: Sendable {
    public static let shared = RollbackLedger()
    private static let logger = Logger(subsystem: "com.macguard", category: "RollbackLedger")

    private let ledgerURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let macGuardDir = appSupport.appendingPathComponent("MacGuard", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: macGuardDir.path) {
            try? FileManager.default.createDirectory(at: macGuardDir, withIntermediateDirectories: true)
        }
        self.ledgerURL = macGuardDir.appendingPathComponent("operations_ledger.json")
    }

    public func loadHistory() -> [OperationRecord] {
        guard FileManager.default.fileExists(atPath: ledgerURL.path),
              let data = try? Data(contentsOf: ledgerURL),
              let records = try? JSONDecoder().decode([OperationRecord].self, from: data) else {
            return []
        }
        return records.sorted(by: { $0.timestamp > $1.timestamp })
    }

    public func recordOperation(_ record: OperationRecord) {
        var current = loadHistory()
        current.insert(record, at: 0)
        saveHistory(current)
        Self.logger.info("Recorded operation \(record.id.uuidString, privacy: .public): \(record.actionType.rawValue, privacy: .public)")
    }

    public func rollback(operationId: UUID) throws {
        var records = loadHistory()
        guard let index = records.firstIndex(where: { $0.id == operationId }) else {
            throw NSError(domain: "MacGuard", code: 404, userInfo: [NSLocalizedDescriptionKey: "Operation record not found"])
        }

        var record = records[index]
        guard !record.isRolledBack else {
            throw NSError(domain: "MacGuard", code: 400, userInfo: [NSLocalizedDescriptionKey: "Operation has already been rolled back"])
        }

        let fileManager = FileManager.default
        let securityGuard = SecurityGuard.shared

        switch record.actionType {
        case .moveFile:
            guard let dest = record.destinationPath else { break }
            let currentURL = URL(fileURLWithPath: dest)
            let originalURL = URL(fileURLWithPath: record.sourcePath)

            guard fileManager.fileExists(atPath: currentURL.path) else {
                throw NSError(domain: "MacGuard", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target file no longer exists at destination '\(dest)'"])
            }

            try securityGuard.safelyMoveItem(from: currentURL, to: originalURL)

        case .moveToTrash:
            if let dest = record.destinationPath, fileManager.fileExists(atPath: dest) {
                let currentURL = URL(fileURLWithPath: dest)
                let originalURL = URL(fileURLWithPath: record.sourcePath)
                try securityGuard.safelyMoveItem(from: currentURL, to: originalURL)
            } else {
                throw NSError(domain: "MacGuard", code: 400, userInfo: [NSLocalizedDescriptionKey: "File is in macOS Trash. Please open Trash to restore it directly."])
            }

        case .createDirectory:
            let dirURL = URL(fileURLWithPath: record.sourcePath)
            if fileManager.fileExists(atPath: dirURL.path) {
                try? fileManager.removeItem(at: dirURL)
            }
        }

        record.isRolledBack = true
        records[index] = record
        saveHistory(records)
        Self.logger.notice("Successfully rolled back operation \(operationId.uuidString, privacy: .public)")
    }

    private func saveHistory(_ records: [OperationRecord]) {
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
