import Foundation
import CryptoKit
import UniformTypeIdentifiers
import os

public struct ScannedItem: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let path: String
    public let name: String
    public let size: Int64
    public let modificationDate: Date
    public let category: FileCategory
    public let isDirectory: Bool

    public init(url: URL, size: Int64, modificationDate: Date, category: FileCategory, isDirectory: Bool) {
        self.id = url.path
        self.url = url
        self.path = url.path
        self.name = url.lastPathComponent
        self.size = size
        self.modificationDate = modificationDate
        self.category = category
        self.isDirectory = isDirectory
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

public enum FileCategory: String, CaseIterable, Codable, Sendable {
    case installers = "Installers & Disk Images"
    case archives = "Compressed Archives"
    case documents = "Documents & Text"
    case media = "Audio & Video"
    case images = "Images & Photos"
    case code = "Code & Projects"
    case caches = "Caches & Logs"
    case other = "Other"

    public var systemIcon: String {
        switch self {
        case .installers: return "opticaldisc"
        case .archives: return "archivebox"
        case .documents: return "doc.text"
        case .media: return "film"
        case .images: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .caches: return "trash"
        case .other: return "doc"
        }
    }
}

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String // SHA-256 hash
    public let hash: String
    public let fileSize: Int64
    public let files: [ScannedItem]

    public var totalWastedSpace: Int64 {
        guard files.count > 1 else { return 0 }
        return fileSize * Int64(files.count - 1)
    }

    public var formattedWastedSpace: String {
        ByteCountFormatter.string(fromByteCount: totalWastedSpace, countStyle: .file)
    }
}

public final class SystemScanner: Sendable {
    public static let shared = SystemScanner()
    private static let logger = Logger(subsystem: "com.macguard", category: "SystemScanner")

    private init() {}

    /// Categorizes a file based on file extension and UniformTypeIdentifier
    public func categorize(url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()

        if ["dmg", "pkg", "iso", "appimage"].contains(ext) {
            return .installers
        }
        if ["zip", "tar", "gz", "bz2", "xz", "7z", "rar"].contains(ext) {
            return .archives
        }
        if ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "txt", "md", "csv", "pages", "numbers", "key"].contains(ext) {
            return .documents
        }
        if ["mp4", "mov", "m4v", "mkv", "avi", "mp3", "m4a", "wav", "flac", "aac"].contains(ext) {
            return .media
        }
        if ["png", "jpg", "jpeg", "heic", "webp", "gif", "svg", "tiff", "bmp"].contains(ext) {
            return .images
        }
        if ["swift", "py", "rs", "go", "js", "ts", "json", "yaml", "yml", "html", "css", "c", "cpp", "h"].contains(ext) {
            return .code
        }
        if ["log", "cache", "tmp", "bak", "dSYM"].contains(ext) {
            return .caches
        }

        return .other
    }

    /// Scans a specific directory recursively or shallowly
    public func scanDirectory(
        at directoryURL: URL,
        recursive: Bool = false,
        minFileSize: Int64 = 0
    ) throws -> [ScannedItem] {
        let validURL = try SecurityGuard.shared.validatePath(directoryURL.path)
        let fileManager = FileManager.default

        var items: [ScannedItem] = []
        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isDirectoryKey,
            .isPackageKey,
            .isRegularFileKey
        ]

        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: validURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }

            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                   let isDirectory = resourceValues.isDirectory,
                   !isDirectory,
                   let isRegularFile = resourceValues.isRegularFile,
                   isRegularFile {
                    let size = Int64(resourceValues.fileSize ?? 0)
                    if size >= minFileSize {
                        let modDate = resourceValues.contentModificationDate ?? Date.distantPast
                        let cat = categorize(url: fileURL)
                        items.append(ScannedItem(url: fileURL, size: size, modificationDate: modDate, category: cat, isDirectory: false))
                    }
                }
            }
        } else {
            let contents = try fileManager.contentsOfDirectory(
                at: validURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            for fileURL in contents {
                if let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) {
                    let isDirectory = resourceValues.isDirectory ?? false
                    let size = Int64(resourceValues.fileSize ?? 0)
                    let modDate = resourceValues.contentModificationDate ?? Date.distantPast
                    let cat = categorize(url: fileURL)

                    if !isDirectory && size >= minFileSize {
                        items.append(ScannedItem(url: fileURL, size: size, modificationDate: modDate, category: cat, isDirectory: false))
                    } else if isDirectory {
                        items.append(ScannedItem(url: fileURL, size: 0, modificationDate: modDate, category: cat, isDirectory: true))
                    }
                }
            }
        }

        return items
    }

    /// Fast multi-pass cryptographic duplicate detection
    public func findDuplicates(in directoryURL: URL, minFileSize: Int64 = 1024) throws -> [DuplicateGroup] {
        let allFiles = try scanDirectory(at: directoryURL, recursive: true, minFileSize: minFileSize) // Skip empty/trivial files

        // Pass 1: Group files by exact byte size
        var sizeMap: [Int64: [ScannedItem]] = [:]
        for file in allFiles {
            sizeMap[file.size, default: []].append(file)
        }

        // Keep only size collisions
        let candidates = sizeMap.filter { $0.value.count > 1 }

        // Pass 2: Cryptographic full SHA-256 hash for candidates
        var hashMap: [String: [ScannedItem]] = [:]
        for (_, files) in candidates {
            for file in files {
                if let hash = computeSHA256(for: file.url) {
                    hashMap[hash, default: []].append(file)
                }
            }
        }

        // Return confirmed duplicate groups
        var duplicateGroups: [DuplicateGroup] = []
        for (hash, groupFiles) in hashMap where groupFiles.count > 1 {
            let group = DuplicateGroup(
                id: hash,
                hash: hash,
                fileSize: groupFiles.first?.size ?? 0,
                files: groupFiles
            )
            duplicateGroups.append(group)
        }

        return duplicateGroups.sorted(by: { $0.totalWastedSpace > $1.totalWastedSpace })
    }

    /// Computes streaming SHA-256 hash without loading entire file into memory
    private func computeSHA256(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024 // 64 KB chunking

        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
