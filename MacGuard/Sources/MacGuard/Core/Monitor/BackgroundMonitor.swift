import Foundation
import os

public final class BackgroundMonitor: Sendable {
    public static let shared = BackgroundMonitor()
    private static let logger = Logger(subsystem: "com.macguard", category: "BackgroundMonitor")

    public struct Status: Sendable {
        public let isMonitoring: Bool
        public let watchedDirectory: String
        public let lowStorageAlertThresholdGB: Int
        public let lastInspectionTime: Date?
    }

    private init() {}

    public func getCurrentStatus() -> Status {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let downloads = home.appendingPathComponent("Downloads").path
        return Status(
            isMonitoring: true,
            watchedDirectory: downloads,
            lowStorageAlertThresholdGB: 15,
            lastInspectionTime: Date()
        )
    }

    /// Inspects system storage and downloads accumulation; returns alert string if threshold triggered
    public func runHealthCheck() -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        // 1. Check volume storage
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let freeBytes = values.volumeAvailableCapacityForImportantUsage {
            let freeGB = freeBytes / (1024 * 1024 * 1024)
            if freeGB < 15 {
                return "Low Storage Warning: Only \(freeGB) GB remaining on your startup disk."
            }
        }

        // 2. Check Downloads folder item count
        let downloads = home.appendingPathComponent("Downloads")
        if let contents = try? fileManager.contentsOfDirectory(atPath: downloads.path) {
            let visibleCount = contents.filter { !$0.hasPrefix(".") }.count
            if visibleCount > 40 {
                return "Downloads Folder Notice: You have \(visibleCount) items in Downloads that could be organized."
            }
        }

        return nil
    }
}
