import Foundation
import os

public struct StorageOverview: Sendable {
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let usedCapacity: Int64
    public let categorySizes: [FileCategory: Int64]
    public let categoryFiles: [FileCategory: [ScannedItem]]
    public let largestFiles: [ScannedItem]
    public let reclaimableEstimate: Int64

    /// Backward compatibility alias for categorySizes
    public var categoryBreakdown: [FileCategory: Int64] {
        categorySizes
    }

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

    // MARK: - Retention & Proportional Helper Accessors

    /// Total bytes of all user-scanned files across all 12 categories
    public var scannedTotalBytes: Int64 {
        categorySizes.values.reduce(0, +)
    }

    public var formattedScannedTotal: String {
        ByteCountFormatter.string(fromByteCount: scannedTotalBytes, countStyle: .file)
    }

    /// APFS capacity consumed by macOS system binaries, System Data, local snapshots, and unscanned directories
    public var systemAndOtherBytes: Int64 {
        max(0, usedCapacity - scannedTotalBytes)
    }

    public var formattedSystemAndOther: String {
        ByteCountFormatter.string(fromByteCount: systemAndOtherBytes, countStyle: .file)
    }

    /// Retained scanned files for a specific category, sorted by size descending
    public func files(for category: FileCategory) -> [ScannedItem] {
        categoryFiles[category] ?? []
    }

    /// Discovered file count for a specific category
    public func fileCount(for category: FileCategory) -> Int {
        categoryFiles[category]?.count ?? 0
    }

    /// Total count of scanned files across all 12 categories
    public var totalScannedFileCount: Int {
        categoryFiles.values.reduce(0) { $0 + $1.count }
    }

    public init(
        totalCapacity: Int64,
        availableCapacity: Int64,
        usedCapacity: Int64,
        categorySizes: [FileCategory: Int64] = [:],
        categoryBreakdown: [FileCategory: Int64]? = nil,
        categoryFiles: [FileCategory: [ScannedItem]] = [:],
        largestFiles: [ScannedItem] = [],
        reclaimableEstimate: Int64? = nil
    ) {
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.usedCapacity = usedCapacity

        // Support either categorySizes or legacy categoryBreakdown
        var resolvedSizes = categoryBreakdown ?? categorySizes
        for cat in FileCategory.allCases {
            if resolvedSizes[cat] == nil {
                let computedSize = categoryFiles[cat]?.reduce(0) { $0 + $1.size } ?? 0
                resolvedSizes[cat] = computedSize
            }
        }
        self.categorySizes = resolvedSizes

        // Ensure all 12 categories are present in categoryFiles
        var resolvedFiles = categoryFiles
        for cat in FileCategory.allCases {
            if resolvedFiles[cat] == nil {
                resolvedFiles[cat] = []
            }
        }
        self.categoryFiles = resolvedFiles

        self.largestFiles = largestFiles

        if let reclaimable = reclaimableEstimate {
            self.reclaimableEstimate = reclaimable
        } else {
            self.reclaimableEstimate = (resolvedSizes[.installers] ?? 0) + (resolvedSizes[.archives] ?? 0)
        }
    }
}

public final class StorageAnalyzer: Sendable {
    public static let shared = StorageAnalyzer()
    private static let logger = Logger(subsystem: "com.macguard", category: "StorageAnalyzer")

    private init() {}

    /// Scans APFS volumes and user directories, grouping discovered files by category without discarding them.
    /// Supports optional `customTargets` for deterministic, isolated unit testing.
    public func scanSystemStorage(customTargets: [URL]? = nil) -> StorageOverview {
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

        // 2. Determine target directories
        let targets: [URL]
        if let customTargets = customTargets {
            targets = customTargets
        } else {
            var defaultTargets: [URL] = [
                homeURL.appendingPathComponent("Downloads"),
                homeURL.appendingPathComponent("Desktop")
            ]

            if PermissionManager.isFullDiskAccessGranted {
                defaultTargets.append(contentsOf: [
                    homeURL.appendingPathComponent("Documents"),
                    homeURL.appendingPathComponent("Pictures"),
                    homeURL.appendingPathComponent("Movies"),
                    homeURL.appendingPathComponent("Music")
                ])
            } else {
                let docURL = homeURL.appendingPathComponent("Documents")
                if fileManager.fileExists(atPath: docURL.path) {
                    defaultTargets.append(docURL)
                }
            }
            targets = defaultTargets
        }

        // Initialize collections for all 12 categories
        var categoryTotals: [FileCategory: Int64] = [:]
        var categoryFilesMap: [FileCategory: [ScannedItem]] = [:]
        for cat in FileCategory.allCases {
            categoryTotals[cat] = 0
            categoryFilesMap[cat] = []
        }

        var allDiscoveredFiles: [ScannedItem] = []
        let scanner = SystemScanner.shared

        for target in targets where fileManager.fileExists(atPath: target.path) {
            if let items = try? scanner.scanDirectory(at: target, recursive: true, minFileSize: 512) {
                for item in items where !item.isDirectory {
                    categoryTotals[item.category, default: 0] += item.size
                    categoryFilesMap[item.category, default: []].append(item)
                    allDiscoveredFiles.append(item)
                }
            }
        }

        // Sort each category by size descending for immediate drill-down readiness
        for cat in FileCategory.allCases {
            categoryFilesMap[cat]?.sort(by: { $0.size > $1.size })
        }

        // 3. Largest Files (top 25 discovered across all categories)
        let sortedLargest = allDiscoveredFiles.sorted(by: { $0.size > $1.size }).prefix(25)

        // 4. Calculate initial reclaimable estimate (old installers + archives in downloads)
        let reclaimable = (categoryTotals[.installers] ?? 0) + (categoryTotals[.archives] ?? 0)

        return StorageOverview(
            totalCapacity: totalSpace,
            availableCapacity: freeSpace,
            usedCapacity: usedSpace,
            categorySizes: categoryTotals,
            categoryFiles: categoryFilesMap,
            largestFiles: Array(sortedLargest),
            reclaimableEstimate: reclaimable
        )
    }

    /// Convenience wrapper preserving backward compatibility with existing callers.
    public func analyzeStorage() -> StorageOverview {
        scanSystemStorage(customTargets: nil)
    }

    public typealias LiveVolumeMetrics = MacGuard.LiveVolumeMetrics

    /// Reads live APFS volume metrics instantaneously without scanning directory contents.
    public func getLiveVolumeMetrics() -> LiveVolumeMetrics {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser

        var totalSpace: Int64 = 0
        var freeSpace: Int64 = 0

        if let values = try? homeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            totalSpace = Int64(values.volumeTotalCapacity ?? 0)
            freeSpace = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        let usedSpace = max(0, totalSpace - freeSpace)
        return LiveVolumeMetrics(totalCapacity: totalSpace, availableCapacity: freeSpace, usedCapacity: usedSpace)
    }
}

// MARK: - Live Volume Metrics (Feature F12)

public struct LiveVolumeMetrics: Sendable, Equatable {
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let usedCapacity: Int64

    public var usagePercentage: Double {
        guard totalCapacity > 0 else { return 0.0 }
        let ratio = Double(usedCapacity) / Double(totalCapacity)
        return min(1.0, max(0.0, ratio))
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

    public init(totalCapacity: Int64, availableCapacity: Int64, usedCapacity: Int64) {
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.usedCapacity = usedCapacity
    }
}

