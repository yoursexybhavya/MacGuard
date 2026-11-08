import Foundation
import os

public struct StorageOverview: Sendable {
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let usedCapacity: Int64
    public let categoryBreakdown: [FileCategory: Int64]
    public let largestFiles: [ScannedItem]
    public let reclaimableEstimate: Int64

    public var usagePercentage: Double {
        guard totalCapacity > 0 else { return 0.0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }

    public var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }

    public var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }

    public var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: reclaimableEstimate, countStyle: .file)
    }
}

public final class StorageAnalyzer: Sendable {
    public static let shared = StorageAnalyzer()
    private static let logger = Logger(subsystem: "com.macguard", category: "StorageAnalyzer")

    private init() {}

    public func analyzeStorage() -> StorageOverview {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser

        // 1. APFS Volume Capacity
        var totalSpace: Int64 = 0
        var freeSpace: Int64 = 0

        if let values = try? homeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            totalSpace = Int64(values.volumeTotalCapacity ?? 0)
            freeSpace = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        let usedSpace = max(0, totalSpace - freeSpace)

        // 2. Sample standard user directories for fast interactive breakdown.
        // If Full Disk Access is not yet granted, we avoid probing ~/Music and ~/Pictures
        // so macOS does not bombard the user with modal prompts (e.g. Apple Music / Photos).
        var targets: [URL] = [
            homeURL.appendingPathComponent("Downloads"),
            homeURL.appendingPathComponent("Desktop")
        ]

        if PermissionManager.isFullDiskAccessGranted {
            targets.append(contentsOf: [
                homeURL.appendingPathComponent("Documents"),
                homeURL.appendingPathComponent("Pictures"),
                homeURL.appendingPathComponent("Movies"),
                homeURL.appendingPathComponent("Music")
            ])
        } else {
            let docURL = homeURL.appendingPathComponent("Documents")
            if fileManager.fileExists(atPath: docURL.path) {
                targets.append(docURL)
            }
        }

        var categoryTotals: [FileCategory: Int64] = [:]
        for cat in FileCategory.allCases {
            categoryTotals[cat] = 0
        }

        var allDiscoveredFiles: [ScannedItem] = []
        let scanner = SystemScanner.shared

        for target in targets where fileManager.fileExists(atPath: target.path) {
            if let items = try? scanner.scanDirectory(at: target, recursive: true, minFileSize: 512) {
                for item in items where !item.isDirectory {
                    categoryTotals[item.category, default: 0] += item.size
                    allDiscoveredFiles.append(item)
                }
            }
        }

        // 3. Largest Files
        let sortedLargest = allDiscoveredFiles.sorted(by: { $0.size > $1.size }).prefix(25)

        // 4. Calculate initial reclaimable estimate (old installers + archives in downloads)
        let reclaimable = (categoryTotals[.installers] ?? 0) + (categoryTotals[.archives] ?? 0)

        return StorageOverview(
            totalCapacity: totalSpace,
            availableCapacity: freeSpace,
            usedCapacity: usedSpace,
            categoryBreakdown: categoryTotals,
            largestFiles: Array(sortedLargest),
            reclaimableEstimate: reclaimable
        )
    }
}
