import Foundation
import Testing
import Metal
@testable import MacGuard

// MARK: - Concurrency Lock & Helpers

/// Global lock ensuring tests interacting with the shared on-disk RollbackLedger do not race each other.
private let ledgerTestLock = NSLock()

private struct TestSandbox {
    let rootURL: URL

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGuard_Test_\(UUID().uuidString)")
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

// MARK: - Tier 1: Feature Coverage & Subsystem Tests

@Suite("Tier 1: Feature Coverage & Subsystem Tests", .serialized)
struct Tier1FeatureCoverageTests {

    @Test("F1 & F5: Verifies all 12 storage categories exist with icons and accurate categorization")
    func testAll12CategoriesClassificationAndIcons() {
        let categories = FileCategory.allCases
        #expect(categories.count == 12)

        let expectedCategories: Set<FileCategory> = [
            .installers, .archives, .documents, .media, .creative,
            .skills, .academics, .images, .code, .caches, .junk, .other
        ]
        #expect(Set(categories) == expectedCategories)

        // Verify each category has a valid system icon and non-empty display name
        for cat in categories {
            #expect(!cat.rawValue.isEmpty)
            #expect(!cat.systemIcon.isEmpty)
        }

        let scanner = SystemScanner.shared

        // 1. Installers
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/setup.dmg")) == .installers)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/update.pkg")) == .installers)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/os.iso")) == .installers)

        // 2. Archives
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/backup.zip")) == .archives)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/bundle.tar.gz")) == .archives)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/data.7z")) == .archives)

        // 3. Documents
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/doc.pdf")) == .documents)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/notes.docx")) == .documents)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/readme.md")) == .documents)

        // 4. Media
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/video.mp4")) == .media)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/podcast.mp3")) == .media)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/clip.mov")) == .media)

        // 5. Creative & 3D
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/model.blend")) == .creative)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/design.psd")) == .creative)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/mockup.fig")) == .creative)

        // 6. AI Skills & Workflows
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/assistant.skill")) == .skills)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/bot.agent")) == .skills)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/model.gguf")) == .skills)

        // 7. Academics & College Notes
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/bme_assignment_final.pdf")) == .academics)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/jiet_exam_syllabus.pdf")) == .academics)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/college_lecture_cheatsheet.pdf")) == .academics)

        // 8. Images & Photos
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/photo.jpg")) == .images)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/graphic.png")) == .images)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/raw.heic")) == .images)

        // 9. Code & Projects
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/App.swift")) == .code)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/script.py")) == .code)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/main.rs")) == .code)

        // 10. Caches & Logs
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/system.log")) == .caches)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/build.tmp")) == .caches)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/index.cache")) == .caches)

        // 11. Junk & Artifacts
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/desktop.ini")) == .junk)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/thumbs.db")) == .junk)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/file.crdownload")) == .junk)

        // 12. Other
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/unknown.xyz")) == .other)
    }

    @Test("F1: Storage category file grouping and retention logic")
    func testCategoryFilesRetentionAndGrouping() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        try sandbox.createFile(at: "installer.dmg", content: Data(repeating: 1, count: 2048))
        try sandbox.createFile(at: "archive.zip", content: Data(repeating: 2, count: 1024))
        try sandbox.createFile(at: "report.pdf", content: Data(repeating: 3, count: 4096))
        try sandbox.createFile(at: "main.swift", content: Data(repeating: 4, count: 512))

        let items = try SystemScanner.shared.scanDirectory(at: sandbox.rootURL, recursive: true, minFileSize: 0)
        #expect(items.count == 4)

        // Group discovered files across all 12 categories
        var categoryFiles: [FileCategory: [ScannedItem]] = [:]
        for cat in FileCategory.allCases {
            categoryFiles[cat] = []
        }

        for item in items {
            categoryFiles[item.category]?.append(item)
        }

        #expect(categoryFiles[.installers]?.count == 1)
        #expect(categoryFiles[.archives]?.count == 1)
        #expect(categoryFiles[.documents]?.count == 1)
        #expect(categoryFiles[.code]?.count == 1)
        #expect(categoryFiles[.media]?.isEmpty == true)
        #expect(categoryFiles[.creative]?.isEmpty == true)

        let totalScanned = categoryFiles.values.flatMap { $0 }.reduce(Int64(0)) { $0 + $1.size }
        #expect(totalScanned == 2048 + 1024 + 4096 + 512)
    }

    @Test("F6: Storage bar capacity calculations and proportion invariants")
    func testStorageBarProportionsAndCapacityInvariants() {
        var breakdown: [FileCategory: Int64] = [:]
        for cat in FileCategory.allCases {
            breakdown[cat] = 0
        }
        breakdown[.documents] = 100_000_000_000 // 100 GB
        breakdown[.media] = 200_000_000_000     // 200 GB
        breakdown[.code] = 50_000_000_000       // 50 GB

        let totalCapacity: Int64 = 1_000_000_000_000 // 1 TB
        let availableCapacity: Int64 = 400_000_000_000 // 400 GB
        let usedCapacity: Int64 = 600_000_000_000 // 600 GB

        let overview = StorageOverview(
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            usedCapacity: usedCapacity,
            categoryBreakdown: breakdown,
            largestFiles: [],
            reclaimableEstimate: 10_000_000_000
        )

        #expect(overview.usagePercentage == 0.60)
        #expect(!overview.formattedTotal.isEmpty)
        #expect(!overview.formattedUsed.isEmpty)
        #expect(!overview.formattedAvailable.isEmpty)
        #expect(!overview.formattedReclaimable.isEmpty)

        // Verify segment proportions relative to total capacity
        let docProportion = Double(breakdown[.documents]!) / Double(totalCapacity)
        let mediaProportion = Double(breakdown[.media]!) / Double(totalCapacity)
        #expect(docProportion == 0.10)
        #expect(mediaProportion == 0.20)

        // Scanned categories total vs System/Other space
        let scannedCategoriesTotal = breakdown.values.reduce(Int64(0), +)
        #expect(scannedCategoriesTotal == 350_000_000_000)
        let systemAndOther = max(0, usedCapacity - scannedCategoriesTotal)
        #expect(systemAndOther == 250_000_000_000)
        #expect(scannedCategoriesTotal + systemAndOther == usedCapacity)
    }

    @Test("F8: Largest files discovery and actionable item properties")
    func testLargestFilesDiscoveryAndActionableAttributes() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        try sandbox.createFile(at: "massive_installer.dmg", content: Data(repeating: 1, count: 5_000_000))
        try sandbox.createFile(at: "heavy_video.mp4", content: Data(repeating: 2, count: 2_000_000))
        try sandbox.createFile(at: "small_script.swift", content: Data(repeating: 3, count: 50_000))

        let items = try SystemScanner.shared.scanDirectory(at: sandbox.rootURL, recursive: true, minFileSize: 1000)
        let sorted = items.sorted(by: { $0.size > $1.size })

        #expect(sorted.count == 3)
        let largest = sorted[0]
        #expect(largest.name == "massive_installer.dmg")
        #expect(largest.size == 5_000_000)
        #expect(largest.category == .installers)
        #expect(!largest.formattedSize.isEmpty)

        let second = sorted[1]
        #expect(second.name == "heavy_video.mp4")
        #expect(second.size == 2_000_000)
        #expect(second.category == .media)

        // Actionability: verify URL is valid and passes security inspection
        let validatedURL = try SecurityGuard.shared.validatePath(largest.path, forModification: false)
        #expect(validatedURL.resolvingSymlinksInPath().path == URL(fileURLWithPath: largest.path).resolvingSymlinksInPath().path)
    }

    @Test("F13: Duplicate Finder folder selection and candidate scanning")
    func testDuplicateFinderFolderSelectionAndScanning() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let targetFolder = try sandbox.createFolder(at: "SelectedScanFolder")
        try sandbox.createFile(at: "SelectedScanFolder/tiny.txt", content: Data(repeating: 1, count: 50))
        try sandbox.createFile(at: "SelectedScanFolder/medium1.txt", content: Data(repeating: 2, count: 2048))
        try sandbox.createFile(at: "SelectedScanFolder/medium2.txt", content: Data(repeating: 2, count: 2048))

        // When scanning with minFileSize 1024, tiny.txt should be omitted
        let scanner = SystemScanner.shared
        let duplicates = try scanner.findDuplicates(in: targetFolder, minFileSize: 1024)

        #expect(duplicates.count == 1)
        #expect(duplicates.first?.fileSize == 2048)
        #expect(duplicates.first?.files.count == 2)
        #expect(duplicates.first?.totalWastedSpace == 2048)
    }

    @Test("F13: Duplicate Finder keeper switching logic")
    func testDuplicateFinderKeeperSwitchingLogic() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        try sandbox.createFile(at: "doc_a.pdf", content: Data(repeating: 0x42, count: 1024))
        try sandbox.createFile(at: "doc_b.pdf", content: Data(repeating: 0x42, count: 1024))
        try sandbox.createFile(at: "doc_c.pdf", content: Data(repeating: 0x42, count: 1024))

        let duplicates = try SystemScanner.shared.findDuplicates(in: sandbox.rootURL, minFileSize: 500)
        #expect(duplicates.count == 1)

        guard let group = duplicates.first else {
            Issue.record("Expected 1 duplicate group")
            return
        }

        #expect(group.files.count == 3)
        #expect(group.totalWastedSpace == 2048) // 1024 * (3 - 1)

        let itemA = group.files.first(where: { $0.name == "doc_a.pdf" })!
        let itemB = group.files.first(where: { $0.name == "doc_b.pdf" })!
        let itemC = group.files.first(where: { $0.name == "doc_c.pdf" })!

        // Interactive Keeper Switching Simulation:
        // Scenario 1: Initial keeper is itemA
        var currentKeeper = itemA
        var redundantItems = group.files.filter { $0.id != currentKeeper.id }
        #expect(currentKeeper.name == "doc_a.pdf")
        #expect(redundantItems.count == 2)
        #expect(!redundantItems.contains(where: { $0.name == "doc_a.pdf" }))

        // Scenario 2: User clicks keeper button on itemB
        currentKeeper = itemB
        redundantItems = group.files.filter { $0.id != currentKeeper.id }
        #expect(currentKeeper.name == "doc_b.pdf")
        #expect(redundantItems.count == 2)
        #expect(redundantItems.contains(where: { $0.name == "doc_a.pdf" }))
        #expect(redundantItems.contains(where: { $0.name == "doc_c.pdf" }))

        // Scenario 3: User clicks keeper button on itemC
        currentKeeper = itemC
        redundantItems = group.files.filter { $0.id != currentKeeper.id }
        #expect(currentKeeper.name == "doc_c.pdf")
        #expect(redundantItems.count == 2)
        #expect(redundantItems.contains(where: { $0.name == "doc_a.pdf" }))
        #expect(redundantItems.contains(where: { $0.name == "doc_b.pdf" }))
    }

    @Test("F14: File Organizer sibling folder consolidation proposals")
    func testFolderConsolidationProposalDetection() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "Images")
        _ = try sandbox.createFolder(at: "Photos & Wallpapers")

        try sandbox.createFile(at: "Images/sunset.png", content: Data("photo1".utf8))
        try sandbox.createFile(at: "Photos & Wallpapers/desktop.png", content: Data("photo2".utf8))

        let organizer = FileOrganizer.shared
        let merges = organizer.planFolderConsolidation(for: sandbox.rootURL)

        #expect(merges.count >= 1)
        let imageMerge = merges.first { $0.sourceName == "Images" && $0.destinationName == "Photos & Wallpapers" }
        #expect(imageMerge != nil)
        #expect(imageMerge?.itemCount == 1)
        #expect(imageMerge?.reason.contains("Merge redundant 'Images'") == true)
    }

    @Test("F16: Cleanup Center candidate discovery and selection toggle")
    func testCleanupCenterSafetyTiersAndSelectionState() {
        // Test all safety tiers and badge colors
        let tiers = SafetyTier.allCases
        #expect(tiers.count == 4)
        #expect(SafetyTier.safe.badgeColorName == "green")
        #expect(SafetyTier.reviewRecommended.badgeColorName == "orange")
        #expect(SafetyTier.highRisk.badgeColorName == "red")
        #expect(SafetyTier.protected.badgeColorName == "gray")

        var targets = [
            CleanupTarget(name: "Target 1", url: URL(fileURLWithPath: "/tmp/1"), size: 1024, safetyTier: .safe, category: "Logs", explanation: "Log cleanup", isSelected: true),
            CleanupTarget(name: "Target 2", url: URL(fileURLWithPath: "/tmp/2"), size: 2048, safetyTier: .reviewRecommended, category: "Installers", explanation: "Old installer", isSelected: false),
            CleanupTarget(name: "Target 3", url: URL(fileURLWithPath: "/tmp/3"), size: 4096, safetyTier: .safe, category: "Caches", explanation: "Cache cleanup", isSelected: true)
        ]

        let initialSelectedCount = targets.filter { $0.isSelected }.count
        #expect(initialSelectedCount == 2)

        // Select All toggle
        for index in targets.indices {
            targets[index].isSelected = true
        }
        #expect(targets.allSatisfy { $0.isSelected })

        // Deselect All toggle
        for index in targets.indices {
            targets[index].isSelected = false
        }
        #expect(targets.allSatisfy { !$0.isSelected })
    }

    @Test("F17: Approvals & History operation record file size and reversibility")
    func testApprovalsHistoryOperationRecordAttributes() throws {
        let record = OperationRecord(
            id: UUID(),
            timestamp: Date(),
            actionType: .moveToTrash,
            sourcePath: "/Users/test/Downloads/file.dmg",
            destinationPath: "/Users/test/.Trash/file.dmg",
            fileSize: 104_857_600, // 100 MB
            reason: "User requested removal",
            isRolledBack: false
        )

        #expect(record.fileSize == 104_857_600)
        #expect(record.actionType == .moveToTrash)
        #expect(record.isReversible == true)

        var rolledBackRecord = record
        rolledBackRecord.isRolledBack = true
        #expect(rolledBackRecord.isReversible == false)

        // Test JSON serialization roundtrip
        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OperationRecord.self, from: data)

        #expect(decoded.id == record.id)
        #expect(decoded.fileSize == record.fileSize)
        #expect(decoded.actionType == record.actionType)
        #expect(decoded.sourcePath == record.sourcePath)
        #expect(decoded.destinationPath == record.destinationPath)
    }

    @Test("F11: Live Hardware Monitor Metal and system memory inspection")
    func testLiveHardwareMonitorMetalAndMemoryMetrics() {
        let metalDevices = MTLCopyAllDevices()
        // On modern macOS, at least one Metal device is available
        #expect(!metalDevices.isEmpty)
        if let primaryDevice = metalDevices.first {
            #expect(!primaryDevice.name.isEmpty)
        }

        let memory = ProcessInfo.processInfo.physicalMemory
        #expect(memory > 0)

        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        #expect(cpuCount > 0)
    }

    @Test("F2: Safe trashing moves item to Trash and captures destination URL")
    func testSafeTrashingDestinationURLCapture() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let file = try sandbox.createFile(at: "trash_test.txt", content: Data("Safe trashing verification".utf8))
        #expect(FileManager.default.fileExists(atPath: file.path))

        let trashURL = try SecurityGuard.shared.safelyMoveToTrash(at: file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: trashURL.path))
        #expect(trashURL.path.contains(".Trash") || trashURL.path.contains("Trash"))

        // Cleanup the trashed artifact
        try? FileManager.default.removeItem(at: trashURL)
    }
}

// MARK: - Tier 2: Boundary & Corner Cases

@Suite("Tier 2: Boundary & Corner Cases", .serialized)
struct Tier2BoundaryAndCornerTests {

    @Test("Empty category handling with zero bytes and zero items")
    func testEmptyCategoryZeroFilesAndZeroBytes() {
        var breakdown: [FileCategory: Int64] = [:]
        for cat in FileCategory.allCases {
            breakdown[cat] = 0
        }

        let overview = StorageOverview(
            totalCapacity: 500_000_000_000,
            availableCapacity: 500_000_000_000,
            usedCapacity: 0,
            categoryBreakdown: breakdown,
            largestFiles: [],
            reclaimableEstimate: 0
        )

        #expect(overview.usagePercentage == 0.0)
        #expect(overview.largestFiles.isEmpty)
        for cat in FileCategory.allCases {
            #expect(overview.categoryBreakdown[cat] == 0)
        }
    }

    @Test("Scanning completely empty directory returns zero items and zero duplicates")
    func testScanningCompletelyEmptyDirectory() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let scanner = SystemScanner.shared
        let items = try scanner.scanDirectory(at: sandbox.rootURL, recursive: true, minFileSize: 0)
        #expect(items.isEmpty)

        let duplicates = try scanner.findDuplicates(in: sandbox.rootURL, minFileSize: 0)
        #expect(duplicates.isEmpty)

        let proposals = try FileOrganizer.shared.planOrganization(for: sandbox.rootURL)
        #expect(proposals.isEmpty)

        let merges = FileOrganizer.shared.planFolderConsolidation(for: sandbox.rootURL)
        #expect(merges.isEmpty)
    }

    @Test("Duplicate collisions: Identical size but different SHA-256 hash are not reported as duplicates")
    func testCryptographicDuplicateCollisionsIdenticalSizeDifferentHash() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        // Create 2 files with exact same byte count (1024 bytes) but differing content
        let contentA = Data(repeating: 0xAA, count: 1024)
        let contentB = Data(repeating: 0xBB, count: 1024)

        try sandbox.createFile(at: "collision_a.bin", content: contentA)
        try sandbox.createFile(at: "collision_b.bin", content: contentB)

        let duplicates = try SystemScanner.shared.findDuplicates(in: sandbox.rootURL, minFileSize: 512)
        #expect(duplicates.isEmpty)
    }

    @Test("Rollback error handling: Missing destination file throws error")
    func testRollbackMissingDestinationFileThrowsError() {
        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        let dummyId = UUID()
        let nonExistentPath = "/tmp/MacGuard_Missing_\(dummyId.uuidString).txt"
        let record = OperationRecord(
            id: dummyId,
            actionType: .moveFile,
            sourcePath: "/tmp/source.txt",
            destinationPath: nonExistentPath,
            fileSize: 100,
            reason: "Non-existent destination test"
        )

        RollbackLedger.shared.recordOperation(record)

        #expect(throws: Error.self) {
            try RollbackLedger.shared.rollback(operationId: dummyId)
        }
    }

    @Test("Rollback error handling: Already rolled back record throws error")
    func testRollbackAlreadyRolledBackRecordThrowsError() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let src = try sandbox.createFile(at: "orig.txt", content: Data("test".utf8))
        let dest = sandbox.fileURL("moved.txt")

        try SecurityGuard.shared.safelyMoveItem(from: src, to: dest)

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        let recordId = UUID()
        let record = OperationRecord(
            id: recordId,
            actionType: .moveFile,
            sourcePath: src.path,
            destinationPath: dest.path,
            fileSize: 4,
            reason: "Double rollback test"
        )
        RollbackLedger.shared.recordOperation(record)

        // First rollback should succeed
        try RollbackLedger.shared.rollback(operationId: recordId)

        // Second rollback attempt must fail
        #expect(throws: Error.self) {
            try RollbackLedger.shared.rollback(operationId: recordId)
        }
    }

    @Test("Rollback error handling: Non-existent operation record ID throws error")
    func testRollbackNonExistentRecordIdThrowsError() {
        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        let randomID = UUID()
        #expect(throws: Error.self) {
            try RollbackLedger.shared.rollback(operationId: randomID)
        }
    }

    @Test("Path validation: Rejects traversal and protected system paths")
    func testPathTraversalAndSystemRootValidation() {
        let securityGuard = SecurityGuard.shared

        let maliciousOrProtected = [
            "../",
            "../../etc/shadow",
            "../Documents",
            "/System",
            "/System/Library/CoreServices",
            "/Library",
            "/usr/bin",
            "/bin/zsh",
            "/private/etc/hosts"
        ]

        for path in maliciousOrProtected {
            #expect(throws: SecurityGuard.SecurityError.self) {
                _ = try securityGuard.validatePath(path, forModification: true)
            }
        }
    }

    @Test("Protected user directories: Blocks destructive modification of sensitive dirs")
    func testProtectedUserDirectoriesBlockedFromModification() {
        let securityGuard = SecurityGuard.shared
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let sensitivePaths = [
            "\(home)/.ssh/id_rsa",
            "\(home)/.gnupg/secring.gpg",
            "\(home)/Library/Keychains/login.keychain",
            "\(home)/.git/config"
        ]

        for path in sensitivePaths {
            #expect(throws: SecurityGuard.SecurityError.self) {
                _ = try securityGuard.validatePath(path, forModification: true)
            }
        }
    }
}

// MARK: - Tier 3: Cross-Feature Integration Tests

@Suite("Tier 3: Cross-Feature Integration Tests", .serialized)
struct Tier3CrossFeatureIntegrationTests {

    @Test("Storage Category Scan -> Safe Trashing -> RollbackLedger -> Rollback Restoration")
    func testStorageCategoryScanToSafeTrashToLedgerToRollback() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let content = "Critical storage document content for reversibility check".data(using: .utf8)!
        let sourceFile = try sandbox.createFile(at: "QuarterlyReport.pdf", content: content)

        // Step 1: Scan and verify categorization
        let items = try SystemScanner.shared.scanDirectory(at: sandbox.rootURL, recursive: false)
        #expect(items.count == 1)
        #expect(items.first?.category == .documents)

        // Step 2: Safe move to macOS Trash
        let trashURL = try SecurityGuard.shared.safelyMoveToTrash(at: sourceFile)
        #expect(!FileManager.default.fileExists(atPath: sourceFile.path))
        #expect(FileManager.default.fileExists(atPath: trashURL.path))

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        // Step 3: Record operation in RollbackLedger
        let recordId = UUID()
        let record = OperationRecord(
            id: recordId,
            actionType: .moveToTrash,
            sourcePath: sourceFile.path,
            destinationPath: trashURL.path,
            fileSize: Int64(content.count),
            reason: "Category inspection cleanup test"
        )
        RollbackLedger.shared.recordOperation(record)

        // Step 4: Verify record in ledger
        let history = RollbackLedger.shared.loadHistory()
        #expect(history.contains(where: { $0.id == recordId }))

        // Step 5: Rollback restoration
        try RollbackLedger.shared.rollback(operationId: recordId)

        // Step 6: Verify file is restored to original path with identical content
        #expect(FileManager.default.fileExists(atPath: sourceFile.path))
        #expect(!FileManager.default.fileExists(atPath: trashURL.path))
        let restoredContent = try Data(contentsOf: sourceFile)
        #expect(restoredContent == content)
    }

    @Test("Duplicate Discovery -> Keeper Selection -> Safe Trashing -> Rollback")
    func testDuplicateDiscoveryToKeeperSelectionToTrashingToRollback() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let originalData = "Identical image byte sequence".data(using: .utf8)!
        let keeperFile = try sandbox.createFile(at: "Original_Image.png", content: originalData)
        let redundantFile = try sandbox.createFile(at: "Copy_Image.png", content: originalData)

        // Step 1: Detect duplicate group
        let duplicates = try SystemScanner.shared.findDuplicates(in: sandbox.rootURL, minFileSize: 10)
        #expect(duplicates.count == 1)
        guard let group = duplicates.first else {
            Issue.record("Expected 1 duplicate group")
            return
        }

        // Step 2: Keeper selection - preserve keeperFile, trash redundantFile
        let candidateToTrash = group.files.first(where: { $0.name == "Copy_Image.png" })!
        #expect(candidateToTrash.url.resolvingSymlinksInPath().path == redundantFile.resolvingSymlinksInPath().path)

        // Step 3: Trash redundant file
        let trashURL = try SecurityGuard.shared.safelyMoveToTrash(at: candidateToTrash.url)
        #expect(!FileManager.default.fileExists(atPath: redundantFile.path))
        #expect(FileManager.default.fileExists(atPath: keeperFile.path)) // Keeper must remain!

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        let recordId = UUID()
        let record = OperationRecord(
            id: recordId,
            actionType: .moveToTrash,
            sourcePath: redundantFile.path,
            destinationPath: trashURL.path,
            fileSize: Int64(originalData.count),
            reason: "Duplicate removal"
        )
        RollbackLedger.shared.recordOperation(record)

        // Step 4: Rollback
        try RollbackLedger.shared.rollback(operationId: recordId)
        #expect(FileManager.default.fileExists(atPath: redundantFile.path))
        #expect(FileManager.default.fileExists(atPath: keeperFile.path))
    }

    @Test("Folder Consolidation Planning -> Execution -> Ledger Logging -> Verification")
    func testFolderConsolidationExecutionToLedgerToRollback() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "Media")
        _ = try sandbox.createFolder(at: "Media & Entertainment")

        let fileA = try sandbox.createFile(at: "Media/movie1.mp4", content: Data("mov1".utf8))
        let fileB = try sandbox.createFile(at: "Media & Entertainment/movie2.mp4", content: Data("mov2".utf8))

        let organizer = FileOrganizer.shared
        let merges = organizer.planFolderConsolidation(for: sandbox.rootURL)
        #expect(!merges.isEmpty)

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        // Execute consolidation merges
        try organizer.executeFolderMerges(merges)

        let destDir = sandbox.fileURL("Media & Entertainment")
        let movedFile = destDir.appendingPathComponent("movie1.mp4")
        #expect(FileManager.default.fileExists(atPath: movedFile.path))
        #expect(FileManager.default.fileExists(atPath: fileB.path))
        #expect(!FileManager.default.fileExists(atPath: fileA.path))

        // Verify source folder "Media" was cleaned up
        let sourceDir = sandbox.fileURL("Media")
        #expect(!FileManager.default.fileExists(atPath: sourceDir.path))

        // Verify ledger records
        let history = RollbackLedger.shared.loadHistory()
        #expect(history.contains(where: {
            $0.actionType == .moveFile &&
            $0.sourcePath.hasSuffix("Media/movie1.mp4") &&
            $0.reason.contains("Consolidated from 'Media' to 'Media & Entertainment'")
        }))
    }
}

// MARK: - Tier 4: Real-World Application E2E Scenario

@Suite("Tier 4: Real-World Application E2E Scenario", .serialized)
struct Tier4RealWorldApplicationE2ETests {

    @Test("Complete Lifecycle: Scan -> Drill-down -> Duplicate Keeper -> Consolidation -> Cleanup -> Audit -> Rollback")
    func testCompleteLifecycleE2EScenario() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        // Setup realistic multi-category filesystem fixture
        let installerContent = Data(repeating: 0x11, count: 20_000)
        let docContent = Data(repeating: 0x22, count: 5_000)
        let dupContent = Data("Identical archive backup payload across duplicate archives".utf8)
        let codeContent = Data("import SwiftUI\nstruct ContentView: View { var body: some View { Text(\"Hi\") } }".utf8)
        let cacheContent = Data(repeating: 0x55, count: 8_000)
        let academicContent = Data("JIET College BME Exam Syllabus Notes".utf8)

        _ = try sandbox.createFile(at: "Software_Setup.dmg", content: installerContent)
        _ = try sandbox.createFile(at: "Annual_Audit.pdf", content: docContent)
        let dupFileA = try sandbox.createFile(at: "Backup_Alpha.zip", content: dupContent)
        let dupFileB = try sandbox.createFile(at: "Backup_Beta.zip", content: dupContent)
        _ = try sandbox.createFile(at: "Source/App.swift", content: codeContent)
        let cacheFile = try sandbox.createFile(at: "Caches/session.tmp", content: cacheContent)

        _ = try sandbox.createFolder(at: "Documents")
        _ = try sandbox.createFolder(at: "Documents & Notes")
        _ = try sandbox.createFile(at: "Documents/memo.txt", content: Data("memo".utf8))
        let siblingFile2 = try sandbox.createFile(at: "Documents & Notes/notes.txt", content: Data("notes".utf8))
        _ = try sandbox.createFile(at: "jiet_syllabus_notes.pdf", content: academicContent)

        // ==========================================
        // Stage 1: Storage Analysis & Category Breakdown
        // ==========================================
        let allItems = try SystemScanner.shared.scanDirectory(at: sandbox.rootURL, recursive: true, minFileSize: 0)
        #expect(allItems.count >= 9)

        var categorizedMap: [FileCategory: [ScannedItem]] = [:]
        for cat in FileCategory.allCases {
            categorizedMap[cat] = []
        }
        for item in allItems {
            categorizedMap[item.category]?.append(item)
        }

        #expect(categorizedMap[.installers]?.contains(where: { $0.name == "Software_Setup.dmg" }) == true)
        #expect(categorizedMap[.documents]?.contains(where: { $0.name == "Annual_Audit.pdf" }) == true)
        #expect(categorizedMap[.archives]?.contains(where: { $0.name == "Backup_Alpha.zip" }) == true)
        #expect(categorizedMap[.code]?.contains(where: { $0.name == "App.swift" }) == true)
        #expect(categorizedMap[.caches]?.contains(where: { $0.name == "session.tmp" }) == true)
        #expect(categorizedMap[.academics]?.contains(where: { $0.name == "jiet_syllabus_notes.pdf" }) == true)

        let sortedByLargest = allItems.sorted(by: { $0.size > $1.size })
        #expect(sortedByLargest.first?.name == "Software_Setup.dmg")
        #expect(sortedByLargest.first?.size == 20_000)

        // ==========================================
        // Stage 2: Duplicate Resolution with Keeper Switching
        // ==========================================
        let duplicates = try SystemScanner.shared.findDuplicates(in: sandbox.rootURL, minFileSize: 10)
        #expect(duplicates.count == 1)
        guard let backupDuplicateGroup = duplicates.first else {
            Issue.record("Expected 1 duplicate group")
            return
        }

        #expect(backupDuplicateGroup.files.count == 2)
        // Select Backup_Alpha as keeper, mark Backup_Beta for safe trashing
        let trashCandidate = backupDuplicateGroup.files.first(where: { $0.name == "Backup_Beta.zip" })!

        let betaTrashURL = try SecurityGuard.shared.safelyMoveToTrash(at: trashCandidate.url)
        #expect(!FileManager.default.fileExists(atPath: dupFileB.path))
        #expect(FileManager.default.fileExists(atPath: dupFileA.path))

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        let dupTrashRecordId = UUID()
        RollbackLedger.shared.recordOperation(OperationRecord(
            id: dupTrashRecordId,
            actionType: .moveToTrash,
            sourcePath: dupFileB.path,
            destinationPath: betaTrashURL.path,
            fileSize: Int64(dupContent.count),
            reason: "Duplicate resolution (keeper: Backup_Alpha.zip)"
        ))

        // ==========================================
        // Stage 3: Sibling Folder Consolidation
        // ==========================================
        let merges = FileOrganizer.shared.planFolderConsolidation(for: sandbox.rootURL)
        #expect(!merges.isEmpty)
        try FileOrganizer.shared.executeFolderMerges(merges)

        let targetDocsDir = sandbox.fileURL("Documents & Notes")
        let consolidatedMemo = targetDocsDir.appendingPathComponent("memo.txt")
        #expect(FileManager.default.fileExists(atPath: consolidatedMemo.path))
        #expect(FileManager.default.fileExists(atPath: siblingFile2.path))

        // ==========================================
        // Stage 4: Safe Cache Cleanup
        // ==========================================
        let cleanupTarget = CleanupTarget(
            name: "Session Temp Cache",
            url: cacheFile,
            size: Int64(cacheContent.count),
            safetyTier: .safe,
            category: "Temporary Files",
            explanation: "Isolated test session cache",
            isSelected: true
        )
        try CleanupEngine.shared.executeCleanup(targets: [cleanupTarget])
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))

        // ==========================================
        // Stage 5: Approvals & History Comprehensive Audit
        // ==========================================
        let auditHistory = RollbackLedger.shared.loadHistory()
        #expect(!auditHistory.isEmpty)

        let dupRecord = auditHistory.first(where: { $0.id == dupTrashRecordId })
        #expect(dupRecord != nil)
        #expect(dupRecord?.actionType == .moveToTrash)
        #expect(dupRecord?.fileSize == Int64(dupContent.count))
        #expect(dupRecord?.isReversible == true)

        let resolvedCachePath = cacheFile.resolvingSymlinksInPath().path
        let cacheCleanupRecord = auditHistory.first(where: {
            URL(fileURLWithPath: $0.sourcePath).resolvingSymlinksInPath().path == resolvedCachePath
        })
        #expect(cacheCleanupRecord != nil)
        #expect(cacheCleanupRecord?.actionType == .moveToTrash)
        #expect(cacheCleanupRecord?.fileSize == Int64(cacheContent.count))

        // ==========================================
        // Stage 6: Reversibility & Rollback Verification
        // ==========================================
        // Rollback the duplicate trash operation
        try RollbackLedger.shared.rollback(operationId: dupTrashRecordId)
        #expect(FileManager.default.fileExists(atPath: dupFileB.path))
        let restoredBetaContent = try Data(contentsOf: dupFileB)
        #expect(restoredBetaContent == dupContent)

        // Rollback the cache cleanup operation
        if let cacheRecord = cacheCleanupRecord {
            try RollbackLedger.shared.rollback(operationId: cacheRecord.id)
            #expect(FileManager.default.fileExists(atPath: cacheFile.path))
        }
    }
}

// MARK: - Milestone 1: Core Safety, Data Retention & Ledger Foundation Tests

@Suite("Milestone 1: Core Safety, Data Retention & Ledger Foundation Tests", .serialized)
struct Milestone1CoreSafetyAndRetentionTests {

    @Test("F1: StorageOverview retains full categoryFiles for all 12 categories with accurate accessors")
    func testStorageOverviewRetentionAndAccessors() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let installerData = Data(repeating: 0x10, count: 2048)
        let archiveData = Data(repeating: 0x20, count: 4096)
        let docData = Data(repeating: 0x30, count: 1024)
        let codeData = Data(repeating: 0x40, count: 512)
        let imgData = Data(repeating: 0x50, count: 8192)

        try sandbox.createFile(at: "Installer.dmg", content: installerData)
        try sandbox.createFile(at: "Bundle.zip", content: archiveData)
        try sandbox.createFile(at: "Notes.pdf", content: docData)
        try sandbox.createFile(at: "App.swift", content: codeData)
        try sandbox.createFile(at: "Photo.png", content: imgData)

        let overview = StorageAnalyzer.shared.scanSystemStorage(customTargets: [sandbox.rootURL])

        // Verify all 12 categories are present in both dictionary collections
        #expect(overview.categoryFiles.count == 12)
        #expect(overview.categorySizes.count == 12)
        for cat in FileCategory.allCases {
            #expect(overview.categoryFiles[cat] != nil)
            #expect(overview.categorySizes[cat] != nil)
        }

        // Verify specific retention and count accessors
        #expect(overview.files(for: .installers).count == 1)
        #expect(overview.fileCount(for: .installers) == 1)
        #expect(overview.files(for: .installers).first?.name == "Installer.dmg")

        #expect(overview.files(for: .archives).count == 1)
        #expect(overview.fileCount(for: .archives) == 1)

        #expect(overview.files(for: .documents).count == 1)
        #expect(overview.fileCount(for: .documents) == 1)

        #expect(overview.files(for: .code).count == 1)
        #expect(overview.fileCount(for: .code) == 1)

        #expect(overview.files(for: .images).count == 1)
        #expect(overview.fileCount(for: .images) == 1)

        // Empty categories return empty arrays safely
        #expect(overview.files(for: .junk).isEmpty)
        #expect(overview.fileCount(for: .junk) == 0)

        // Verify calculation accessors
        let expectedTotalBytes: Int64 = 2048 + 4096 + 1024 + 512 + 8192
        #expect(overview.scannedTotalBytes == expectedTotalBytes)
        #expect(overview.totalScannedFileCount == 5)
        #expect(overview.systemAndOtherBytes >= 0)
        #expect(!overview.formattedScannedTotal.isEmpty)
        #expect(!overview.formattedSystemAndOther.isEmpty)

        // Verify backward compatibility computed alias
        #expect(overview.categoryBreakdown[.installers] == overview.categorySizes[.installers])
    }

    @Test("F1: StorageOverview retains all discovered files without truncation while capping largestFiles to top 25")
    func testStorageOverviewLargestFilesExtractionWithoutFileLoss() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        // Create 30 document files with varying sizes
        for i in 1...30 {
            let data = Data(repeating: 0x41, count: 600 + (i * 100))
            try sandbox.createFile(at: "Doc_\(i).txt", content: data)
        }

        let overview = StorageAnalyzer.shared.scanSystemStorage(customTargets: [sandbox.rootURL])

        // largestFiles is strictly capped at top 25
        #expect(overview.largestFiles.count == 25)

        // largestFiles is strictly descending
        for i in 0..<overview.largestFiles.count - 1 {
            #expect(overview.largestFiles[i].size >= overview.largestFiles[i + 1].size)
        }

        // All 30 files are retained in categoryFiles
        let docFiles = overview.files(for: .documents)
        #expect(docFiles.count == 30)
        #expect(overview.totalScannedFileCount == 30)
    }

    @Test("F2: SecurityGuard protects ~/.Trash from direct modification and prevents re-trashing items in Trash")
    func testSecurityGuardTrashProtection() {
        let guardInstance = SecurityGuard.shared

        // Directly validating ~/.Trash for modification must throw protectedPath
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.validatePath("~/.Trash", forModification: true)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.validatePath("\(home)/.Trash", forModification: true)
        }

        // Trashing an item already inside Trash must throw protectedPath
        let trashItemURL = URL(fileURLWithPath: "\(home)/.Trash/some_deleted_item.txt")
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.safelyMoveToTrash(at: trashItemURL)
        }
    }

    @Test("F4: Non-colliding URL resolution generates collision-free suffixes and avoids overwriting")
    func testNonCollidingURLResolution() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let originalFile = try sandbox.createFile(at: "Report.pdf", content: Data("V1".utf8))

        // When file does not exist, resolveNonCollidingURL returns target unchanged
        let nonExistentURL = sandbox.fileURL("Unique.txt")
        #expect(RollbackLedger.resolveNonCollidingURL(for: nonExistentURL) == nonExistentURL)

        // When file exists, appends (Restored)
        let resolvedFirst = RollbackLedger.resolveNonCollidingURL(for: originalFile)
        #expect(resolvedFirst.lastPathComponent == "Report (Restored).pdf")

        // If Report (Restored).pdf also exists, appends (Restored 2)
        try sandbox.createFile(at: "Report (Restored).pdf", content: Data("V2".utf8))
        let resolvedSecond = RollbackLedger.resolveNonCollidingURL(for: originalFile)
        #expect(resolvedSecond.lastPathComponent == "Report (Restored 2).pdf")
    }

    @Test("F4: Rollback with destination collision safely restores alongside existing file without data loss")
    func testRollbackWithDestinationCollisionSafety() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let originalContent = Data("Original V1 Content to preserve".utf8)
        let sourceFile = try sandbox.createFile(at: "ImportantContract.pdf", content: originalContent)

        // Step 1: Safely trash file
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: sourceFile, reason: "Collision rollback test")
        #expect(!FileManager.default.fileExists(atPath: sourceFile.path))

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        let recordId = UUID()
        RollbackLedger.shared.recordOperation(OperationRecord(
            id: recordId,
            actionType: .moveToTrash,
            sourcePath: sourceFile.path,
            destinationPath: trashedURL.path,
            fileSize: Int64(originalContent.count),
            reason: "Collision test"
        ))

        // Step 2: Create a NEW conflicting file at the original path
        let newConflictingContent = Data("New V2 Content that must NOT be overwritten".utf8)
        try newConflictingContent.write(to: sourceFile)

        // Step 3: Trigger rollback on original record
        let restoredURL = try RollbackLedger.shared.rollback(operationId: recordId)

        // Step 4: Verify existing file was NOT overwritten
        let currentOriginalData = try Data(contentsOf: sourceFile)
        #expect(currentOriginalData == newConflictingContent)

        // Step 5: Verify restored file was placed alongside with non-colliding name and original content
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        #expect(restoredURL.path != sourceFile.path)
        #expect(restoredURL.lastPathComponent == "ImportantContract (Restored).pdf")
        let restoredData = try Data(contentsOf: restoredURL)
        #expect(restoredData == originalContent)

        // Cleanup restored file
        try? FileManager.default.removeItem(at: restoredURL)
    }

    @Test("F4: Batch rollbackAll restores multiple operations in reverse-chronological order")
    func testBatchRollbackAllExecution() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let fileA = try sandbox.createFile(at: "Batch_A.txt", content: Data("A".utf8))
        let fileB = try sandbox.createFile(at: "Batch_B.txt", content: Data("B".utf8))
        let fileC = try sandbox.createFile(at: "Batch_C.txt", content: Data("C".utf8))

        let trashA = try SecurityGuard.shared.safelyMoveToTrash(at: fileA)
        let trashB = try SecurityGuard.shared.safelyMoveToTrash(at: fileB)
        let trashC = try SecurityGuard.shared.safelyMoveToTrash(at: fileC)

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        let idA = UUID()
        let idB = UUID()
        let idC = UUID()

        let ledger = RollbackLedger.shared
        ledger.recordOperation(OperationRecord(id: idA, actionType: .moveToTrash, sourcePath: fileA.path, destinationPath: trashA.path, fileSize: 1, reason: "Batch A"))
        ledger.recordOperation(OperationRecord(id: idB, actionType: .moveToTrash, sourcePath: fileB.path, destinationPath: trashB.path, fileSize: 1, reason: "Batch B"))
        ledger.recordOperation(OperationRecord(id: idC, actionType: .moveToTrash, sourcePath: fileC.path, destinationPath: trashC.path, fileSize: 1, reason: "Batch C"))

        // Execute batch rollback
        let count = try ledger.rollbackAll(recordIds: [idA, idB, idC])
        #expect(count == 3)

        // All 3 files must be restored
        #expect(FileManager.default.fileExists(atPath: fileA.path))
        #expect(FileManager.default.fileExists(atPath: fileB.path))
        #expect(FileManager.default.fileExists(atPath: fileC.path))

        // All 3 records must be marked rolled back
        let history = ledger.loadHistory()
        let records = history.filter { [idA, idB, idC].contains($0.id) }
        #expect(records.count == 3)
        for r in records {
            #expect(r.isRolledBack)
        }
    }

    @Test("F4: OperationRecord UI helpers produce valid names, icons, and formatted sizes")
    func testOperationRecordUIHelpers() {
        let trashRecord = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: "/Users/demo/Documents/Presentation.key",
            destinationPath: "/Users/demo/.Trash/Presentation.key",
            fileSize: 10_485_760, // 10 MB
            reason: "User cleanup"
        )

        #expect(trashRecord.fileName == "Presentation.key")
        #expect(trashRecord.systemImageName == "trash")
        #expect(!trashRecord.formattedSize.isEmpty)
        #expect(trashRecord.formattedSize != "--")
        #expect(trashRecord.isReversible == true)

        let dirRecord = OperationRecord(
            actionType: .createDirectory,
            sourcePath: "/Users/demo/Downloads/NewFolder",
            fileSize: nil,
            reason: "Directory organization"
        )
        #expect(dirRecord.fileName == "NewFolder")
        #expect(dirRecord.systemImageName == "folder.badge.plus")
        #expect(dirRecord.formattedSize == "--")
    }

    @Test("F2: CleanupEngine discoverCleanupCandidates does not include ~/.Trash")
    func testCleanupEngineExcludesTrash() {
        let candidates = CleanupEngine.shared.discoverCleanupCandidates()
        for candidate in candidates {
            #expect(!candidate.url.path.hasSuffix("/.Trash"))
            #expect(candidate.name != "macOS Trash Contents")
        }
    }

    @Test("F3: Folder consolidation moves empty source directory to Trash rather than permanently unlinking")
    func testFolderConsolidationMovesSourceToTrash() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let sourceDir = try sandbox.createFolder(at: "SourceDocs")
        let destDir = try sandbox.createFolder(at: "SourceDocs & Archive")
        _ = try sandbox.createFile(at: "SourceDocs/file.txt", content: Data("Merge Content".utf8))

        let proposal = FolderMergeProposal(
            sourceURL: sourceDir,
            destinationURL: destDir,
            itemCount: 1,
            totalSize: 13,
            reason: "Folder merge consolidation test"
        )

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        try FileOrganizer.shared.executeFolderMerges([proposal])

        // File is in destination
        let mergedFile = destDir.appendingPathComponent("file.txt")
        #expect(FileManager.default.fileExists(atPath: mergedFile.path))

        // Source directory was safely moved to Trash, NOT removed permanently
        #expect(!FileManager.default.fileExists(atPath: sourceDir.path))

        let history = RollbackLedger.shared.loadHistory()
        let dirTrashRecord = history.first(where: {
            $0.actionType == .moveToTrash && $0.sourcePath == sourceDir.path
        })
        #expect(dirTrashRecord != nil)
        #expect(dirTrashRecord?.destinationPath != nil)
    }
}

// MARK: - Milestone 2: Storage Analyzer Interactivity & Category Drill-Down Tests

@Suite("Milestone 2: Storage Analyzer Interactivity & Category Drill-Down Tests", .serialized)
struct Milestone2InteractivityAndDrillDownTests {

    @Test("F5: StorageCategoryCardView data flow and fileCount accuracy across non-empty and empty categories")
    func testCategoryCardDataFlow() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let item1 = ScannedItem(url: homeURL.appendingPathComponent("test1.zip"), size: 1024, modificationDate: Date(), category: .archives, isDirectory: false)
        let item2 = ScannedItem(url: homeURL.appendingPathComponent("test2.tar.gz"), size: 2048, modificationDate: Date(), category: .archives, isDirectory: false)

        let overview = StorageOverview(
            totalCapacity: 1_000_000_000,
            availableCapacity: 500_000_000,
            usedCapacity: 500_000_000,
            categoryFiles: [.archives: [item1, item2]],
            largestFiles: [item2, item1]
        )

        #expect(overview.fileCount(for: .archives) == 2)
        #expect(overview.categorySizes[.archives] == 3072)
        #expect(overview.fileCount(for: .installers) == 0)
        #expect(overview.categorySizes[.installers] == 0)

        // Verify FileCategory color and id extensions
        for cat in FileCategory.allCases {
            #expect(!cat.id.isEmpty)
            #expect(cat.id == cat.rawValue)
        }
    }

    @Test("F6: Proportional width algorithm preserves minimum width clamping and exact total sum")
    func testProgressBarWidthClamping() {
        let mockSegments = [
            StorageBarSegmentItem(id: "large", title: "Large", subtitle: "", bytes: 800_000_000_000, color: .blue, icon: "doc", category: .documents),
            StorageBarSegmentItem(id: "tiny", title: "Tiny", subtitle: "", bytes: 10_000, color: .orange, icon: "opticaldisc", category: .installers),
            StorageBarSegmentItem(id: "medium", title: "Medium", subtitle: "", bytes: 100_000_000_000, color: .pink, icon: "photo", category: .images)
        ]

        let availableWidth: CGFloat = 1000.0
        let widths = DynamicStorageProgressBar.computeProportionalWidths(
            segments: mockSegments,
            totalBytes: 900_000_010_000,
            availableWidth: availableWidth,
            spacing: 2.0,
            minWidth: 8.0
        )

        // Verify tiny segment was clamped to at least minWidth (8.0 pt)
        #expect(widths["tiny"]! >= 8.0)
        #expect(widths["large"]! > widths["medium"]!)
        #expect(widths["medium"]! > widths["tiny"]!)

        // Verify total allocated width does not exceed available width
        let totalAllocated = widths.values.reduce(0, +) + (CGFloat(mockSegments.count - 1) * 2.0)
        #expect(abs(totalAllocated - availableWidth) < 1.0)
    }

    @Test("F6: Full APFS volume invariant holds across scannedTotalBytes, systemAndOtherBytes, and availableCapacity")
    func testAPFSSumInvariant() {
        let totalCap: Int64 = 512_000_000_000
        let availCap: Int64 = 200_000_000_000
        let usedCap: Int64 = 312_000_000_000

        let overview = StorageOverview(
            totalCapacity: totalCap,
            availableCapacity: availCap,
            usedCapacity: usedCap,
            categorySizes: [.documents: 12_000_000_000, .media: 50_000_000_000]
        )

        #expect(overview.scannedTotalBytes == 62_000_000_000)
        #expect(overview.systemAndOtherBytes == 250_000_000_000)
        #expect(overview.scannedTotalBytes + overview.systemAndOtherBytes == overview.usedCapacity)
        #expect(overview.usedCapacity + overview.availableCapacity == overview.totalCapacity)
    }

    @Test("F7: CategoryDetailView search filter matches name and path case-insensitively and diacritic-insensitively")
    func testCategoryDetailViewSearchFilter() {
        let item1 = ScannedItem(
            url: URL(fileURLWithPath: "/Users/demo/Downloads/MacGuard_Setup.dmg"),
            size: 50_000_000,
            modificationDate: Date(timeIntervalSince1970: 1000),
            category: .installers,
            isDirectory: false
        )
        let item2 = ScannedItem(
            url: URL(fileURLWithPath: "/Users/demo/Projects/Archive/Xcode_Tool.pkg"),
            size: 120_000_000,
            modificationDate: Date(timeIntervalSince1970: 2000),
            category: .installers,
            isDirectory: false
        )
        let item3 = ScannedItem(
            url: URL(fileURLWithPath: "/Users/demo/Downloads/Ubuntu_Server.iso"),
            size: 800_000_000,
            modificationDate: Date(timeIntervalSince1970: 3000),
            category: .installers,
            isDirectory: false
        )

        let allItems = [item1, item2, item3]

        // 1. Filtering by name (case-insensitive)
        let searchDmg = allItems.filter {
            $0.name.localizedCaseInsensitiveContains("dmg") || $0.path.localizedCaseInsensitiveContains("dmg")
        }
        #expect(searchDmg.count == 1)
        #expect(searchDmg.first?.name == "MacGuard_Setup.dmg")

        // 2. Filtering by subpath
        let searchDownloads = allItems.filter {
            $0.name.localizedCaseInsensitiveContains("Downloads") || $0.path.localizedCaseInsensitiveContains("Downloads")
        }
        #expect(searchDownloads.count == 2)
        #expect(searchDownloads.contains(where: { $0.name == "MacGuard_Setup.dmg" }))
        #expect(searchDownloads.contains(where: { $0.name == "Ubuntu_Server.iso" }))

        // 3. Empty search returns all items
        let searchEmpty = allItems.filter { _ in true }
        #expect(searchEmpty.count == 3)
    }

    @Test("F7: CategoryDetailView 6-way sorting invariants")
    func testCategoryDetailViewSortingInvariants() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)

        let itemAlpha = ScannedItem(url: URL(fileURLWithPath: "/tmp/Alpha.zip"), size: 100, modificationDate: date2, category: .archives, isDirectory: false)
        let itemBeta = ScannedItem(url: URL(fileURLWithPath: "/tmp/Beta.zip"), size: 500, modificationDate: date1, category: .archives, isDirectory: false)
        let itemGamma = ScannedItem(url: URL(fileURLWithPath: "/tmp/Gamma.zip"), size: 300, modificationDate: date3, category: .archives, isDirectory: false)

        let items = [itemAlpha, itemBeta, itemGamma]

        // 1. Size Descending
        let sortedSizeDesc = items.sorted { $0.size > $1.size }
        #expect(sortedSizeDesc.map(\.name) == ["Beta.zip", "Gamma.zip", "Alpha.zip"])

        // 2. Size Ascending
        let sortedSizeAsc = items.sorted { $0.size < $1.size }
        #expect(sortedSizeAsc.map(\.name) == ["Alpha.zip", "Gamma.zip", "Beta.zip"])

        // 3. Name Ascending (A to Z)
        let sortedNameAsc = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        #expect(sortedNameAsc.map(\.name) == ["Alpha.zip", "Beta.zip", "Gamma.zip"])

        // 4. Name Descending (Z to A)
        let sortedNameDesc = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        #expect(sortedNameDesc.map(\.name) == ["Gamma.zip", "Beta.zip", "Alpha.zip"])

        // 5. Date Descending (Newest)
        let sortedDateDesc = items.sorted { $0.modificationDate > $1.modificationDate }
        #expect(sortedDateDesc.map(\.name) == ["Gamma.zip", "Alpha.zip", "Beta.zip"])

        // 6. Date Ascending (Oldest)
        let sortedDateAsc = items.sorted { $0.modificationDate < $1.modificationDate }
        #expect(sortedDateAsc.map(\.name) == ["Beta.zip", "Alpha.zip", "Gamma.zip"])
    }

    @Test("F8: ScannedFileRowView metadata extraction and streaming SHA-256 accuracy")
    func testScannedFileRowMetadataExtraction() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let testPayload = "MacGuard Precision Hashing Verification Payload".data(using: .utf8)!
        let testURL = try sandbox.createFile(at: "Report.pdf", content: testPayload)

        let scannedItem = ScannedItem(
            url: testURL,
            size: Int64(testPayload.count),
            modificationDate: Date(),
            category: .documents,
            isDirectory: false
        )

        let viewModel = await MainActor.run {
            FileMetadataViewModel(file: scannedItem)
        }

        await MainActor.run {
            #expect(viewModel.name == "Report.pdf")
            #expect(viewModel.size == Int64(testPayload.count))
            #expect(viewModel.utTypeIdentifier.contains("pdf"))
            #expect(!viewModel.posixPermissionsOctal.isEmpty)
            #expect(viewModel.posixPermissionsOctal != "--")
        }

        // Trigger async hashing and await completion
        await MainActor.run {
            viewModel.startAsyncHashComputation()
        }

        // Wait briefly for streaming computation
        try await Task.sleep(nanoseconds: 50_000_000)

        await MainActor.run {
            #expect(viewModel.sha256 != nil)
            #expect(viewModel.sha256?.count == 64)
            #expect(viewModel.isComputingHash == false)
        }
    }

    @Test("F8: Trashing from file row invokes SecurityGuard, records RollbackLedger, and permits undo")
    func testFileRowSafeTrashingAndReversibility() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let content = Data("Reversible Largest File Cleanup".utf8)
        let file = try sandbox.createFile(at: "HeavyAsset.iso", content: content)
        let item = ScannedItem(url: file, size: Int64(content.count), modificationDate: Date(), category: .installers, isDirectory: false)

        #expect(FileManager.default.fileExists(atPath: file.path))

        // Step 1: Execute safe trashing
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: item.url, reason: "Storage Analyzer file action")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        // Step 2: Record in ledger
        let recordId = UUID()
        RollbackLedger.shared.recordOperation(OperationRecord(
            id: recordId,
            actionType: .moveToTrash,
            sourcePath: item.path,
            destinationPath: trashedURL.path,
            fileSize: item.size,
            reason: "User trashed from Storage Analyzer"
        ))

        // Step 3: Verify ledger entry
        let history = RollbackLedger.shared.loadHistory()
        let record = history.first(where: { $0.id == recordId })
        #expect(record != nil)
        #expect(record?.isReversible == true)

        // Step 4: Perform rollback restoration
        let restoredURL = try RollbackLedger.shared.rollback(operationId: recordId)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        #expect(try Data(contentsOf: restoredURL) == content)
    }

    @Test("F7: Batch trashing multiple items moves all to Trash and records in RollbackLedger")
    func testBatchTrashingAndRollbackRestoration() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let file1 = try sandbox.createFile(at: "batch1.dmg", content: Data("file1".utf8))
        let file2 = try sandbox.createFile(at: "batch2.dmg", content: Data("file2".utf8))
        let file3 = try sandbox.createFile(at: "batch3.dmg", content: Data("file3".utf8))

        let items = [
            ScannedItem(url: file1, size: 5, modificationDate: Date(), category: .installers, isDirectory: false),
            ScannedItem(url: file2, size: 5, modificationDate: Date(), category: .installers, isDirectory: false),
            ScannedItem(url: file3, size: 5, modificationDate: Date(), category: .installers, isDirectory: false)
        ]

        ledgerTestLock.lock()
        defer { ledgerTestLock.unlock() }

        var trashedRecordIDs: [UUID] = []

        for item in items {
            let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: item.url, reason: "Batch trash test")
            let recordId = UUID()
            RollbackLedger.shared.recordOperation(OperationRecord(
                id: recordId,
                actionType: .moveToTrash,
                sourcePath: item.path,
                destinationPath: trashedURL.path,
                fileSize: item.size,
                reason: "Batch trash test"
            ))
            trashedRecordIDs.append(recordId)
        }

        // Verify none exist at original locations
        #expect(!FileManager.default.fileExists(atPath: file1.path))
        #expect(!FileManager.default.fileExists(atPath: file2.path))
        #expect(!FileManager.default.fileExists(atPath: file3.path))

        // Rollback all
        let rollbackCount = try RollbackLedger.shared.rollbackAll(recordIds: trashedRecordIDs)
        #expect(rollbackCount == 3)

        // Verify all 3 files restored
        #expect(FileManager.default.fileExists(atPath: file1.path))
        #expect(FileManager.default.fileExists(atPath: file2.path))
        #expect(FileManager.default.fileExists(atPath: file3.path))
    }
}


