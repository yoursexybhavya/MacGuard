import Foundation
import os

public struct FolderMergeProposal: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let destinationURL: URL
    public let itemCount: Int
    public let totalSize: Int64
    public let reason: String

    public var sourceName: String { sourceURL.lastPathComponent }
    public var destinationName: String { destinationURL.lastPathComponent }
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL,
        itemCount: Int,
        totalSize: Int64,
        reason: String
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.itemCount = itemCount
        self.totalSize = totalSize
        self.reason = reason
    }
}

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

        // Detect existing subdirectories to establish canonical target folders
        var existingFolderNames = Set<String>()
        if let contents = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for url in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    existingFolderNames.insert(url.lastPathComponent)
                }
            }
        }

        // Canonical folder resolvers (reuses user's existing naming convention)
        let academicFolder = existingFolderNames.first(where: { ["Academics & College", "College & Academics", "Academics", "College Notes"].contains($0) }) ?? "Academics & College"
        let creativeFolder = existingFolderNames.first(where: { ["Design & 3D Assets", "Creative Projects", "Design Assets"].contains($0) }) ?? "Design & 3D Assets"
        let skillsFolder = existingFolderNames.first(where: { ["Skills", "AI Skills"].contains($0) }) ?? "Skills"
        let docFolder = existingFolderNames.first(where: { ["Documents & Notes", "Documents"].contains($0) }) ?? "Documents & Notes"
        let mediaFolder = existingFolderNames.first(where: { ["Media & Entertainment", "Media"].contains($0) }) ?? "Media & Entertainment"
        let imgFolder = existingFolderNames.first(where: { ["Photos & Wallpapers", "Images & Photos", "Images"].contains($0) }) ?? "Photos & Wallpapers"
        let instFolder = existingFolderNames.first(where: { ["Software & Installers", "Installers"].contains($0) }) ?? "Software & Installers"
        let codeFolder = existingFolderNames.first(where: { ["Code & Projects", "Code", "Projects"].contains($0) }) ?? "Code & Projects"
        let archiveFolder = existingFolderNames.first(where: { ["Archives", "Compressed Archives"].contains($0) }) ?? "Archives"

        var proposals: [OrganizationProposal] = []

        for item in items where !item.isDirectory {
            // Ignore incomplete downloads or Windows junk in organization (handled by cleanup)
            if item.category == .junk { continue }

            let subfolderName: String
            var subSubFolder: String? = nil

            let nameLower = item.name.lowercased()
            let extLower = item.url.pathExtension.lowercased()

            switch item.category {
            case .academics:
                subfolderName = academicFolder

            case .creative:
                subfolderName = creativeFolder
                if ["drfx", "zxp", "ccx"].contains(extLower) || nameLower.contains("plugin") || nameLower.contains("effect") {
                    subSubFolder = "Plugins & Video Effects"
                } else if ["blend", "c4d", "obj", "fbx", "stl"].contains(extLower) {
                    subSubFolder = "3D Projects"
                }

            case .skills:
                subfolderName = skillsFolder

            case .media:
                subfolderName = mediaFolder
                if extLower == "opus" || nameLower.contains("whatsapp audio") || nameLower.contains("voice") {
                    subSubFolder = "Voice Notes"
                } else if ["mkv", "mp4", "avi"].contains(extLower) && (nameLower.contains("2160p") || nameLower.contains("1080p") || nameLower.contains("s01") || nameLower.contains("web-dl")) {
                    subSubFolder = "Movies & Shows"
                }

            case .documents:
                subfolderName = docFolder

            case .images:
                subfolderName = imgFolder

            case .installers:
                subfolderName = instFolder

            case .archives:
                subfolderName = archiveFolder

            case .code:
                subfolderName = codeFolder

            case .caches:
                subfolderName = "Temporary"

            case .other:
                continue

            case .junk:
                continue
            }

            var destDir = directoryURL.appendingPathComponent(subfolderName, isDirectory: true)
            if let sub = subSubFolder {
                destDir = destDir.appendingPathComponent(sub, isDirectory: true)
            }

            var finalDestination = destDir.appendingPathComponent(item.name)
            if fileManager.fileExists(atPath: finalDestination.path) {
                let nameWithoutExtension = item.url.deletingPathExtension().lastPathComponent
                let ext = item.url.pathExtension
                var counter = 1
                while fileManager.fileExists(atPath: finalDestination.path) {
                    let newName = ext.isEmpty ? "\(nameWithoutExtension) (\(counter))" : "\(nameWithoutExtension) (\(counter)).\(ext)"
                    finalDestination = destDir.appendingPathComponent(newName)
                    counter += 1
                }
            }

            let reason = "Organize into '\(subfolderName)\(subSubFolder != nil ? "/" + subSubFolder! : "")' based on content & format."
            proposals.append(OrganizationProposal(
                sourceURL: item.url,
                proposedDestinationURL: finalDestination,
                category: item.category,
                reason: reason,
                fileSize: item.size
            ))
        }

        return proposals
    }

    /// Plans the consolidation and merging of duplicate, redundant subfolders into a single clean hierarchy
    public func planFolderConsolidation(for directoryURL: URL) -> [FolderMergeProposal] {
        let fileManager = FileManager.default
        var existingFolderNames = Set<String>()
        if let contents = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for url in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    existingFolderNames.insert(url.lastPathComponent)
                }
            }
        }

        var folderMerges: [FolderMergeProposal] = []

        // 1. Documents vs Documents & Notes
        if existingFolderNames.contains("Documents") && existingFolderNames.contains("Documents & Notes") {
            let src = directoryURL.appendingPathComponent("Documents")
            let dst = directoryURL.appendingPathComponent("Documents & Notes")
            let count = (try? fileManager.contentsOfDirectory(atPath: src.path).count) ?? 0
            folderMerges.append(FolderMergeProposal(
                sourceURL: src,
                destinationURL: dst,
                itemCount: count,
                totalSize: calculateDirectorySize(at: src),
                reason: "Merge redundant 'Documents' folder into primary 'Documents & Notes'"
            ))
        }

        // 2. Media vs Media & Entertainment
        if existingFolderNames.contains("Media") && existingFolderNames.contains("Media & Entertainment") {
            let src = directoryURL.appendingPathComponent("Media")
            let dst = directoryURL.appendingPathComponent("Media & Entertainment")
            let count = (try? fileManager.contentsOfDirectory(atPath: src.path).count) ?? 0
            folderMerges.append(FolderMergeProposal(
                sourceURL: src,
                destinationURL: dst,
                itemCount: count,
                totalSize: calculateDirectorySize(at: src),
                reason: "Merge redundant 'Media' folder into primary 'Media & Entertainment'"
            ))
        }

        // 3. audio vs Media & Entertainment/Audio Projects
        if existingFolderNames.contains("audio") {
            let src = directoryURL.appendingPathComponent("audio")
            let targetParent = existingFolderNames.contains("Media & Entertainment") ? "Media & Entertainment" : "Media"
            let dst = directoryURL.appendingPathComponent(targetParent).appendingPathComponent("Audio Projects/The Long Pier Audio")
            let count = (try? fileManager.contentsOfDirectory(atPath: src.path).count) ?? 0
            folderMerges.append(FolderMergeProposal(
                sourceURL: src,
                destinationURL: dst,
                itemCount: count,
                totalSize: calculateDirectorySize(at: src),
                reason: "Consolidate 'audio' production tracks into '\(targetParent)/Audio Projects/The Long Pier Audio'"
            ))
        }

        // 4. Images vs Photos & Wallpapers
        if existingFolderNames.contains("Images") && existingFolderNames.contains("Photos & Wallpapers") {
            let src = directoryURL.appendingPathComponent("Images")
            let dst = directoryURL.appendingPathComponent("Photos & Wallpapers")
            let count = (try? fileManager.contentsOfDirectory(atPath: src.path).count) ?? 0
            folderMerges.append(FolderMergeProposal(
                sourceURL: src,
                destinationURL: dst,
                itemCount: count,
                totalSize: calculateDirectorySize(at: src),
                reason: "Merge redundant 'Images' folder into primary 'Photos & Wallpapers'"
            ))
        }

        // 5. Installers vs Software & Installers
        if existingFolderNames.contains("Installers") && existingFolderNames.contains("Software & Installers") {
            let src = directoryURL.appendingPathComponent("Installers")
            let dst = directoryURL.appendingPathComponent("Software & Installers")
            let count = (try? fileManager.contentsOfDirectory(atPath: src.path).count) ?? 0
            folderMerges.append(FolderMergeProposal(
                sourceURL: src,
                destinationURL: dst,
                itemCount: count,
                totalSize: calculateDirectorySize(at: src),
                reason: "Merge redundant 'Installers' folder into primary 'Software & Installers'"
            ))
        }

        // 6. basics of electrical and electronics engineering_resources -> Academics & College
        if existingFolderNames.contains("basics of electrical and electronics engineering_resources") && existingFolderNames.contains("Academics & College") {
            let src = directoryURL.appendingPathComponent("basics of electrical and electronics engineering_resources")
            let dst = directoryURL.appendingPathComponent("Academics & College/Electrical & Electronics Engineering")
            let count = (try? fileManager.contentsOfDirectory(atPath: src.path).count) ?? 0
            folderMerges.append(FolderMergeProposal(
                sourceURL: src,
                destinationURL: dst,
                itemCount: count,
                totalSize: calculateDirectorySize(at: src),
                reason: "Organize 'basics of electrical...' under 'Academics & College'"
            ))
        }

        // 7. build -> Code
        if existingFolderNames.contains("build") && existingFolderNames.contains("Code") {
            let src = directoryURL.appendingPathComponent("build")
            let dst = directoryURL.appendingPathComponent("Code/Build Artifacts")
            let count = (try? fileManager.contentsOfDirectory(atPath: src.path).count) ?? 0
            folderMerges.append(FolderMergeProposal(
                sourceURL: src,
                destinationURL: dst,
                itemCount: count,
                totalSize: calculateDirectorySize(at: src),
                reason: "Move 'build' folder under 'Code & Projects'"
            ))
        }

        return folderMerges
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

    /// Executes folder merges by moving all contents from source to destination and cleaning the empty folder
    public func executeFolderMerges(_ merges: [FolderMergeProposal]) throws {
        let fileManager = FileManager.default
        let securityGuard = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        for merge in merges {
            guard fileManager.fileExists(atPath: merge.sourceURL.path) else { continue }

            // Ensure destination directory exists
            if !fileManager.fileExists(atPath: merge.destinationURL.path) {
                try fileManager.createDirectory(at: merge.destinationURL, withIntermediateDirectories: true)
            }

            // Move each item from source to destination
            let contents = try fileManager.contentsOfDirectory(at: merge.sourceURL, includingPropertiesForKeys: nil)
            for item in contents {
                var targetDest = merge.destinationURL.appendingPathComponent(item.lastPathComponent)
                if fileManager.fileExists(atPath: targetDest.path) {
                    let ext = item.pathExtension
                    let base = item.deletingPathExtension().lastPathComponent
                    var c = 1
                    while fileManager.fileExists(atPath: targetDest.path) {
                        let newName = ext.isEmpty ? "\(base) (\(c))" : "\(base) (\(c)).\(ext)"
                        targetDest = merge.destinationURL.appendingPathComponent(newName)
                        c += 1
                    }
                }

                try securityGuard.safelyMoveItem(from: item, to: targetDest)
                ledger.recordOperation(OperationRecord(
                    actionType: .moveFile,
                    sourcePath: item.path,
                    destinationPath: targetDest.path,
                    fileSize: 0,
                    reason: "Consolidated from '\(merge.sourceName)' to '\(merge.destinationName)'"
                ))
            }

            // Safely remove empty source directory
            try? fileManager.removeItem(at: merge.sourceURL)
        }
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
