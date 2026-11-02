import Foundation
import os

public struct OrganizationProposal: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let proposedDestinationURL: URL
    public let category: FileCategory
    public let reason: String
    public let fileSize: Int64

    public var sourcePath: String { sourceURL.path }
    public var destinationPath: String { proposedDestinationURL.path }
    public var fileName: String { sourceURL.lastPathComponent }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        proposedDestinationURL: URL,
        category: FileCategory,
        reason: String,
        fileSize: Int64
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.proposedDestinationURL = proposedDestinationURL
        self.category = category
        self.reason = reason
        self.fileSize = fileSize
    }
}

public final class FileOrganizer: Sendable {
    public static let shared = FileOrganizer()
    private static let logger = Logger(subsystem: "com.macguard", category: "FileOrganizer")

    private init() {}

    /// Analyzes a directory and generates a structured organization plan without moving anything
    public func planOrganization(for directoryURL: URL) throws -> [OrganizationProposal] {
        let scanner = SystemScanner.shared
        let items = try scanner.scanDirectory(at: directoryURL, recursive: false)
        let fileManager = FileManager.default

        var proposals: [OrganizationProposal] = []

        for item in items where !item.isDirectory {
            // Determine subfolder name based on file category
            let subfolderName: String
            switch item.category {
            case .installers: subfolderName = "Installers"
            case .archives: subfolderName = "Archives"
            case .documents: subfolderName = "Documents"
            case .media: subfolderName = "Media"
            case .images: subfolderName = "Images"
            case .code: subfolderName = "Code"
            case .caches: subfolderName = "Temporary"
            case .other: continue // Leave miscellaneous items untouched
            }

            let destinationFolder = directoryURL.appendingPathComponent(subfolderName, isDirectory: true)
            var finalDestination = destinationFolder.appendingPathComponent(item.name)

            // Safe collision avoidance: append counter if target already exists
            if fileManager.fileExists(atPath: finalDestination.path) {
                let nameWithoutExtension = item.url.deletingPathExtension().lastPathComponent
                let ext = item.url.pathExtension
                var counter = 1
                while fileManager.fileExists(atPath: finalDestination.path) {
                    let newName = ext.isEmpty ? "\(nameWithoutExtension) (\(counter))" : "\(nameWithoutExtension) (\(counter)).\(ext)"
                    finalDestination = destinationFolder.appendingPathComponent(newName)
                    counter += 1
                }
            }

            let reason = "Group \(item.category.rawValue) into organized '\(subfolderName)' folder."
            let proposal = OrganizationProposal(
                sourceURL: item.url,
                proposedDestinationURL: finalDestination,
                category: item.category,
                reason: reason,
                fileSize: item.size
            )
            proposals.append(proposal)
        }

        return proposals
    }

    /// Executes approved organization proposals atomically and logs to Rollback Ledger
    public func executeProposals(_ proposals: [OrganizationProposal]) throws {
        let securityGuard = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        for proposal in proposals {
            try securityGuard.safelyMoveItem(from: proposal.sourceURL, to: proposal.proposedDestinationURL)

            let record = OperationRecord(
                actionType: .moveFile,
                sourcePath: proposal.sourcePath,
                destinationPath: proposal.destinationPath,
                fileSize: proposal.fileSize,
                reason: proposal.reason
            )
            ledger.recordOperation(record)
        }
        Self.logger.notice("Successfully executed \(proposals.count, privacy: .public) file organization operations")
    }
}
