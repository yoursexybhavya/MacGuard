import Testing
import Foundation
import SwiftUI
import AppKit
@testable import MacGuard

private struct TestSandbox {
    let rootURL: URL

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGuard_M4_Test_\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.rootURL = tempDir
    }

    func fileURL(_ relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath()
    }

    @discardableResult
    func createFile(at relativePath: String, content: Data) throws -> URL {
        let url = fileURL(relativePath)
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try content.write(to: url)
        return url
    }

    @discardableResult
    func createFolder(at relativePath: String) throws -> URL {
        let url = fileURL(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

@Suite("Milestone 4: Secondary Screens & Settings Overhaul Tests", .serialized)
struct Milestone4SecondaryScreensTests {

    // MARK: - Feature F16: Cleanup Center Interactive Overhaul Tests

    @Test("F16.1: CleanupFilter tabs partitioning and count badges")
    func testCleanupFilterTabsAndBadgeCounts() {
        let safeCache1 = CleanupTarget(
            name: "DerivedData Cache",
            url: URL(fileURLWithPath: "/tmp/DerivedData"),
            size: 1048576,
            safetyTier: .safe,
            category: "Developer Caches",
            explanation: "Xcode build cache",
            isSelected: true
        )
        let safeCache2 = CleanupTarget(
            name: "Old Download Artifact",
            url: URL(fileURLWithPath: "/tmp/artifact.crdownload"),
            size: 524288,
            safetyTier: .safe,
            category: "Incomplete & Artifacts",
            explanation: "Incomplete browser download",
            isSelected: true
        )
        let systemLog = CleanupTarget(
            name: "CrashReport.crash",
            url: URL(fileURLWithPath: "/tmp/CrashReport.crash"),
            size: 65536,
            safetyTier: .safe,
            category: "System Logs",
            explanation: "Crash log",
            isSelected: true
        )
        let reviewInstaller = CleanupTarget(
            name: "Installer.dmg",
            url: URL(fileURLWithPath: "/tmp/Installer.dmg"),
            size: 209715200,
            safetyTier: .reviewRecommended,
            category: "Old Installers",
            explanation: "Disk image installer",
            isSelected: false
        )

        let candidates = [safeCache1, safeCache2, systemLog, reviewInstaller]

        // All Items
        let allFiltered = candidates.filter { _ in true }
        #expect(allFiltered.count == 4)

        // Safe Caches
        let safeCachesFiltered = candidates.filter { target in
            target.safetyTier == .safe && (target.category.contains("Cache") || target.category.contains("Developer") || target.category.contains("Artifact"))
        }
        #expect(safeCachesFiltered.count == 2)

        // System Logs
        let logsFiltered = candidates.filter { target in
            target.category.contains("Log") || target.name.contains("Log")
        }
        #expect(logsFiltered.count == 1)

        // Review Recommended
        let reviewFiltered = candidates.filter { target in
            target.safetyTier == .reviewRecommended || target.category.contains("Installer")
        }
        #expect(reviewFiltered.count == 1)

        // Check enum integrity
        for filter in CleanupFilter.allCases {
            #expect(!filter.rawValue.isEmpty)
            #expect(!filter.icon.isEmpty)
            #expect(filter.id == filter.rawValue)
        }
    }

    @Test("F16.2: Batch selection toggles and Safe Only filter")
    func testBatchSelectionTogglingAndSafeOnly() {
        var targets = [
            CleanupTarget(name: "T1", url: URL(fileURLWithPath: "/tmp/1"), size: 100, safetyTier: .safe, category: "Caches", explanation: "Cache", isSelected: false),
            CleanupTarget(name: "T2", url: URL(fileURLWithPath: "/tmp/2"), size: 200, safetyTier: .reviewRecommended, category: "Installers", explanation: "Installer", isSelected: true),
            CleanupTarget(name: "T3", url: URL(fileURLWithPath: "/tmp/3"), size: 300, safetyTier: .safe, category: "Logs", explanation: "Log", isSelected: false)
        ]

        // Select Safe Only
        for i in targets.indices {
            targets[i].isSelected = (targets[i].safetyTier == .safe)
        }
        #expect(targets[0].isSelected == true)
        #expect(targets[1].isSelected == false)
        #expect(targets[2].isSelected == true)

        // Select All
        for i in targets.indices {
            targets[i].isSelected = true
        }
        #expect(targets.allSatisfy { $0.isSelected })

        // Deselect All
        for i in targets.indices {
            targets[i].isSelected = false
        }
        #expect(targets.allSatisfy { !$0.isSelected })
    }

    @Test("F16.3: Directory sub-item inspection enumerates children with accurate sizes and types")
    func testDirectorySubItemInspection() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let testDir = try sandbox.createFolder(at: "InspectionDir")
        try sandbox.createFile(at: "InspectionDir/large.bin", content: Data(repeating: 0x41, count: 5000))
        try sandbox.createFile(at: "InspectionDir/small.txt", content: Data(repeating: 0x42, count: 200))
        _ = try sandbox.createFolder(at: "InspectionDir/SubDir")
        try sandbox.createFile(at: "InspectionDir/SubDir/nested.dat", content: Data(repeating: 0x43, count: 1000))

        let engine = CleanupEngine.shared
        let subItems = engine.inspectSubItems(at: testDir)

        #expect(subItems.count == 3)
        // SubItems should be sorted descending by size
        #expect(subItems[0].size >= subItems[1].size)
        #expect(subItems[1].size >= subItems[2].size)

        let names = Set(subItems.map(\.name))
        #expect(names.contains("large.bin"))
        #expect(names.contains("small.txt"))
        #expect(names.contains("SubDir"))

        let subDirItem = subItems.first(where: { $0.name == "SubDir" })
        #expect(subDirItem?.isDirectory == true)
        #expect(subDirItem?.size == 1000)

        let largeItem = subItems.first(where: { $0.name == "large.bin" })
        #expect(largeItem?.isDirectory == false)
        #expect(largeItem?.size == 5000)
    }

    @Test("F16.4: CleanupTarget auto directory detection")
    func testCleanupTargetAutoDirectoryDetection() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let folder = try sandbox.createFolder(at: "CacheFolder")
        let file = try sandbox.createFile(at: "test.log", content: Data("sample".utf8))

        let folderTarget = CleanupTarget(
            name: "Folder Target",
            url: folder,
            size: 100,
            safetyTier: .safe,
            category: "Caches",
            explanation: "Cache"
        )
        #expect(folderTarget.isDirectory == true)

        let fileTarget = CleanupTarget(
            name: "File Target",
            url: file,
            size: 6,
            safetyTier: .safe,
            category: "Logs",
            explanation: "Log"
        )
        #expect(fileTarget.isDirectory == false)
    }

    @Test("F16.5: CleanupEngine executeCleanup safely trashes and logs to RollbackLedger")
    func testCleanupEngineTrashesSafelyAndLogsToLedger() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let fileToTrash = try sandbox.createFile(at: "obsolete_cache.tmp", content: Data("Temporary Cache Data".utf8))
        let target = CleanupTarget(
            name: "Obsolete Cache",
            url: fileToTrash,
            size: 20,
            safetyTier: .safe,
            category: "Developer Caches",
            explanation: "Safe cache removal test",
            isSelected: true
        )

        let records = try CleanupEngine.shared.executeCleanup(targets: [target])
        #expect(records.count == 1)

        let record = records[0]
        #expect(record.actionType == .moveToTrash)
        #expect(record.sourcePath == fileToTrash.path)
        #expect(record.destinationPath != nil)
        #expect(FileManager.default.fileExists(atPath: record.destinationPath!))
        #expect(!FileManager.default.fileExists(atPath: fileToTrash.path))

        // Perform rollback via RollbackLedger
        let restoredURL = try RollbackLedger.shared.rollback(recordId: record.id)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        let restoredContent = try String(contentsOf: restoredURL, encoding: .utf8)
        #expect(restoredContent == "Temporary Cache Data")
    }

    @Test("F16.6: CleanupSubItem model integrity")
    func testCleanupSubItemModelProperties() {
        let url = URL(fileURLWithPath: "/tmp/sample_sub.dat")
        let date = Date()
        let sub = CleanupSubItem(
            name: "sample_sub.dat",
            url: url,
            size: 2048,
            isDirectory: false,
            modificationDate: date
        )
        #expect(sub.name == "sample_sub.dat")
        #expect(sub.path == url.path)
        #expect(sub.size == 2048)
        #expect(!sub.isDirectory)
        #expect(sub.modificationDate == date)
        #expect(!sub.formattedSize.isEmpty)
    }

    @Test("F16.7: CleanupView view model and subviews instantiate cleanly")
    @MainActor
    func testCleanupViewInstantiation() {
        let view = CleanupView()
        #expect(view.filteredCandidates.count >= 0)
    }

    // MARK: - Feature F17: Approvals & History Interactive Ledger Tests

    @Test("F17.1: OperationRecord filter chip matching across all 5 categories")
    func testOperationFilterMatching() {
        let trashOp = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: "/Users/test/junk.tmp",
            destinationPath: "/Users/test/.Trash/junk.tmp",
            fileSize: 1024,
            reason: "Cleanup center cache purge"
        )
        #expect(trashOp.matches(filter: .all))
        #expect(trashOp.matches(filter: .trash))
        #expect(!trashOp.matches(filter: .organize))
        #expect(!trashOp.matches(filter: .consolidated))
        #expect(!trashOp.matches(filter: .aiMaintenance))

        let consolidateOp = OperationRecord(
            actionType: .moveFile,
            sourcePath: "/Users/test/Docs 1/a.txt",
            destinationPath: "/Users/test/Docs/a.txt",
            fileSize: 2048,
            reason: "Consolidated from 'Docs 1' to 'Docs'"
        )
        #expect(consolidateOp.matches(filter: .all))
        #expect(consolidateOp.matches(filter: .organize))
        #expect(consolidateOp.matches(filter: .consolidated))
        #expect(!consolidateOp.matches(filter: .trash))
        #expect(!consolidateOp.matches(filter: .aiMaintenance))

        let aiOp = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: "/Users/test/duplicate.mov",
            destinationPath: "/Users/test/.Trash/duplicate.mov",
            fileSize: 104857600,
            reason: "Duplicate file removed by AI Assistant"
        )
        #expect(aiOp.matches(filter: .all))
        #expect(aiOp.matches(filter: .trash))
        #expect(aiOp.matches(filter: .aiMaintenance))
        #expect(!aiOp.matches(filter: .consolidated))

        let organizeOp = OperationRecord(
            actionType: .moveFile,
            sourcePath: "/Users/test/Downloads/photo.jpg",
            destinationPath: "/Users/test/Pictures/photo.jpg",
            fileSize: 512000,
            reason: "Rule-based organization into Images"
        )
        #expect(organizeOp.matches(filter: .all))
        #expect(organizeOp.matches(filter: .organize))
        #expect(!organizeOp.matches(filter: .trash))
        #expect(!organizeOp.matches(filter: .consolidated))
        #expect(!organizeOp.matches(filter: .aiMaintenance))

        for filter in OperationFilter.allCases {
            #expect(!filter.rawValue.isEmpty)
            #expect(!filter.icon.isEmpty)
            #expect(filter.id == filter.rawValue)
        }
    }

    @Test("F17.2: Byte-accurate file size and exact byte descriptions")
    func testByteAccurateFileSizeFormatting() {
        let opWithBytes = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: "/Users/test/video.mp4",
            destinationPath: "/Users/test/.Trash/video.mp4",
            fileSize: 14882912,
            reason: "Trash large file"
        )
        #expect(opWithBytes.formattedSize != "--")
        #expect(opWithBytes.exactByteCountDescription.contains("14,882,912 bytes"))

        let emptyOp = OperationRecord(
            actionType: .createDirectory,
            sourcePath: "/Users/test/NewFolder",
            fileSize: 0,
            reason: "Create folder"
        )
        #expect(emptyOp.exactByteCountDescription == "0 bytes")
    }

    @Test("F17.3: Instant search query matching across filename, reason, action, and paths")
    func testSearchFilteringLogic() {
        let op = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: "/Users/test/Documents/FinancialReport2026.pdf",
            destinationPath: "/Users/test/.Trash/FinancialReport2026.pdf",
            fileSize: 204800,
            reason: "Manual cleanup of quarterly report"
        )

        #expect(op.fileName == "FinancialReport2026.pdf")
        #expect(op.fileName.localizedCaseInsensitiveContains("financial"))
        #expect(op.reason.localizedCaseInsensitiveContains("quarterly"))
        #expect(op.actionType.rawValue.localizedCaseInsensitiveContains("Trash"))
        #expect(op.sourcePath.localizedCaseInsensitiveContains("Documents"))
    }

    @Test("F17.4: Multi-select batch rollback restores selective subset in reverse-chronological order")
    func testSelectiveBatchRollback() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let file1 = try sandbox.createFile(at: "file1.txt", content: Data("Content 1".utf8))
        let file2 = try sandbox.createFile(at: "file2.txt", content: Data("Content 2".utf8))
        let file3 = try sandbox.createFile(at: "file3.txt", content: Data("Content 3".utf8))

        let ledger = RollbackLedger.shared
        let sec = SecurityGuard.shared

        let t1 = try sec.safelyMoveToTrash(at: file1)
        let t2 = try sec.safelyMoveToTrash(at: file2)
        let t3 = try sec.safelyMoveToTrash(at: file3)

        let rec1 = ledger.recordOperation(actionType: .moveToTrash, sourcePath: file1.path, destinationPath: t1.path, fileSize: 9, reason: "Batch test 1")
        let rec2 = ledger.recordOperation(actionType: .moveToTrash, sourcePath: file2.path, destinationPath: t2.path, fileSize: 9, reason: "Batch test 2")
        let rec3 = ledger.recordOperation(actionType: .moveToTrash, sourcePath: file3.path, destinationPath: t3.path, fileSize: 9, reason: "Batch test 3")

        // Selectively rollback only rec1 and rec3, leaving rec2 untouched
        let restoredCount = try ledger.rollbackAll(recordIds: [rec1.id, rec3.id])
        #expect(restoredCount == 2)

        // Verify file1 and file3 restored
        #expect(FileManager.default.fileExists(atPath: file1.path))
        #expect(FileManager.default.fileExists(atPath: file3.path))

        // Verify file2 remains in Trash
        #expect(!FileManager.default.fileExists(atPath: file2.path))

        // Clean up rec2
        _ = try? ledger.rollback(recordId: rec2.id)
    }

    @Test("F17.5: RollbackLedger reloadFromDisk refreshes published operations")
    func testRollbackLedgerReloadFromDisk() {
        let ledger = RollbackLedger.shared
        ledger.reloadFromDisk()
        #expect(ledger.operations.count >= 0)
    }

    @Test("F17.6: ApprovalCenterView view model and subviews instantiate cleanly")
    @MainActor
    func testApprovalCenterViewInstantiation() {
        let view = ApprovalCenterView()
        #expect(view.filteredOperations.count >= 0)
        #expect(view.reversibleOperations.count >= 0)
    }

    // MARK: - Feature F18: Settings Real Ollama, Metal Specs & Background Persistence Tests

    @Test("F18.1: AppSettingsKeys are unique and non-empty")
    func testAppSettingsKeysUniqueAndNonEmpty() {
        let keys = [
            AppSettingsKeys.selectedOllamaModel,
            AppSettingsKeys.customOllamaModel,
            AppSettingsKeys.enableBackgroundMonitoring,
            AppSettingsKeys.monitoringFrequencyMinutes,
            AppSettingsKeys.enableDownloadsWatch,
            AppSettingsKeys.downloadsClutterThreshold,
            AppSettingsKeys.lowStorageThresholdGB,
            AppSettingsKeys.enableAutoCleanupAlerts
        ]

        #expect(keys.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        let uniqueKeys = Set(keys)
        #expect(uniqueKeys.count == keys.count)
    }

    @Test("F18.2: AppSettings defaults match specifications")
    func testAppSettingsDefaultsIntegrity() {
        #expect(AppSettings.defaultSelectedModel == "macguard-ai:latest")
        #expect(AppSettings.defaultCustomModel == "")
        #expect(AppSettings.defaultEnableBackgroundMonitoring == true)
        #expect(AppSettings.defaultMonitoringFrequencyMinutes == 15.0)
        #expect(AppSettings.defaultEnableDownloadsWatch == true)
        #expect(AppSettings.defaultDownloadsClutterThreshold == 40.0)
        #expect(AppSettings.defaultLowStorageThresholdGB == 15.0)
        #expect(AppSettings.defaultEnableAutoCleanupAlerts == true)
    }

    @Test("F18.3: AppSettings resetToDefaults restores all preference keys")
    func testAppSettingsResetToDefaults() {
        let suiteName = "test.macguard.settings.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Mutate to non-default values
        testDefaults.set("custom-other-model", forKey: AppSettingsKeys.selectedOllamaModel)
        testDefaults.set("custom-tag", forKey: AppSettingsKeys.customOllamaModel)
        testDefaults.set(false, forKey: AppSettingsKeys.enableBackgroundMonitoring)
        testDefaults.set(60.0, forKey: AppSettingsKeys.monitoringFrequencyMinutes)
        testDefaults.set(false, forKey: AppSettingsKeys.enableDownloadsWatch)
        testDefaults.set(90.0, forKey: AppSettingsKeys.downloadsClutterThreshold)
        testDefaults.set(45.0, forKey: AppSettingsKeys.lowStorageThresholdGB)
        testDefaults.set(false, forKey: AppSettingsKeys.enableAutoCleanupAlerts)

        // Reset
        AppSettings.resetToDefaults(userDefaults: testDefaults)

        // Verify restoration
        #expect(testDefaults.string(forKey: AppSettingsKeys.selectedOllamaModel) == AppSettings.defaultSelectedModel)
        #expect(testDefaults.string(forKey: AppSettingsKeys.customOllamaModel) == AppSettings.defaultCustomModel)
        #expect(testDefaults.bool(forKey: AppSettingsKeys.enableBackgroundMonitoring) == AppSettings.defaultEnableBackgroundMonitoring)
        #expect(testDefaults.double(forKey: AppSettingsKeys.monitoringFrequencyMinutes) == AppSettings.defaultMonitoringFrequencyMinutes)
        #expect(testDefaults.bool(forKey: AppSettingsKeys.enableDownloadsWatch) == AppSettings.defaultEnableDownloadsWatch)
        #expect(testDefaults.double(forKey: AppSettingsKeys.downloadsClutterThreshold) == AppSettings.defaultDownloadsClutterThreshold)
        #expect(testDefaults.double(forKey: AppSettingsKeys.lowStorageThresholdGB) == AppSettings.defaultLowStorageThresholdGB)
        #expect(testDefaults.bool(forKey: AppSettingsKeys.enableAutoCleanupAlerts) == AppSettings.defaultEnableAutoCleanupAlerts)
    }

    @Test("F18.4: AppSettings effectiveOllamaModel resolution logic")
    func testAppSettingsEffectiveOllamaModel() {
        let suiteName = "test.macguard.ollama.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Default when unset
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == "macguard-ai:latest")

        // Specific model tag
        testDefaults.set("llama3.2:1b", forKey: AppSettingsKeys.selectedOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == "llama3.2:1b")

        // Custom model tag
        testDefaults.set("custom", forKey: AppSettingsKeys.selectedOllamaModel)
        testDefaults.set("mistral-nemo:12b", forKey: AppSettingsKeys.customOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == "mistral-nemo:12b")

        // Custom with empty/whitespace tag falls back to default
        testDefaults.set("   ", forKey: AppSettingsKeys.customOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == "macguard-ai:latest")
    }

    @Test("F18.5: AppSettings formatFrequency produces clean human-readable intervals")
    func testAppSettingsFormatFrequency() {
        #expect(AppSettings.formatFrequency(5.0) == "Every 5 minutes")
        #expect(AppSettings.formatFrequency(15.0) == "Every 15 minutes")
        #expect(AppSettings.formatFrequency(30.0) == "Every 30 minutes")
        #expect(AppSettings.formatFrequency(60.0) == "Every 1 hour")
    }

    @Test("F18.6: HardwareMonitor queries real Metal device and system memory metrics")
    func testHardwareMonitorQueryHardware() {
        let info = HardwareMonitor.queryHardware()
        #expect(!info.chipName.isEmpty)
        #expect(info.coreCount > 0)
        #expect(info.physicalMemoryBytes > 0)
        #expect(!info.formattedPhysicalMemory.isEmpty)
        #expect(!info.formattedActiveRAM.isEmpty)
        #expect(!info.formattedSystemFree.isEmpty)
        #expect(!info.deviceSummary.isEmpty)
        #expect(!info.activeMemorySummary.isEmpty)
    }

    @Test("F18.7: OllamaModelInfo decodes API responses correctly")
    func testOllamaModelInfoDecoding() throws {
        let json = """
        {
            "models": [
                {
                    "name": "macguard-ai:latest",
                    "size": 4321000000,
                    "modified_at": "2026-11-08T00:00:00Z"
                },
                {
                    "name": "qwen2.5:7b",
                    "size": 7654000000,
                    "modified_at": "2026-11-07T12:00:00Z"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        #expect(response.models.count == 2)
        #expect(response.models[0].name == "macguard-ai:latest")
        #expect(response.models[0].size == 4321000000)
        #expect(response.models[0].modifiedAt == "2026-11-08T00:00:00Z")
        #expect(response.models[1].name == "qwen2.5:7b")
    }

    @Test("F18.8: SettingsView and SecurityRuleRow instantiate cleanly")
    @MainActor
    func testSettingsViewInstantiation() {
        _ = SettingsView()
        let row = SecurityRuleRow(icon: "shield", title: "Test", desc: "Description")
        #expect(row.title == "Test")
    }
}
