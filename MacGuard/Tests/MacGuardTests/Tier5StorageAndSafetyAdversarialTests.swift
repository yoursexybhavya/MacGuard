import Foundation
import Testing
@testable import MacGuard

private let tier5LedgerLock = NSLock()

private struct Tier5Sandbox {
    let rootURL: URL

    init(prefix: String = "MacGuard_T5") throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.rootURL = tempDir.resolvingSymlinksInPath()
    }

    func fileURL(_ relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath()
    }

    @discardableResult
    func createFile(at relativePath: String, content: Data = Data()) throws -> URL {
        let url = fileURL(relativePath)
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try content.write(to: url)
        return url.resolvingSymlinksInPath()
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

@Suite("Tier 5 Adversarial Coverage Hardening: Storage, Safety & Reversibility Tests", .serialized)
struct Tier5StorageAndSafetyAdversarialTests {

    // MARK: - Challenge 1: Zero-Byte Files Across Pipeline

    @Test("Adversarial: Zero-byte files categorization, scanning, trashing, and reversibility")
    func testZeroByteFilesAcrossStorageAndSafetyPipeline() throws {
        let sandbox = try Tier5Sandbox(prefix: "ZeroByte")
        defer { sandbox.cleanup() }

        let zeroTxt = try sandbox.createFile(at: "empty_document.txt", content: Data())
        _ = try sandbox.createFile(at: "empty_code.swift", content: Data())
        _ = try sandbox.createFile(at: "empty_image.png", content: Data())
        _ = try sandbox.createFile(at: "empty_installer.dmg", content: Data())

        // 1. SystemScanner with minFileSize = 0 discovers all 4 zero-byte items
        let scanned = try SystemScanner.shared.scanDirectory(at: sandbox.rootURL, recursive: true, minFileSize: 0)
        #expect(scanned.count == 4)
        for item in scanned {
            #expect(item.size == 0)
            #expect(item.formattedSize.contains("Zero") || item.formattedSize.contains("0 bytes"))
        }

        let catMap = Dictionary(grouping: scanned, by: { $0.category })
        #expect(catMap[.documents]?.count == 1)
        #expect(catMap[.code]?.count == 1)
        #expect(catMap[.images]?.count == 1)
        #expect(catMap[.installers]?.count == 1)

        // 2. StorageOverview with 0 total capacity and 0 used capacity handles usagePercentage cleanly
        let emptyOverview = StorageOverview(
            totalCapacity: 0,
            availableCapacity: 0,
            usedCapacity: 0,
            categorySizes: [:],
            categoryFiles: catMap,
            largestFiles: scanned
        )
        #expect(emptyOverview.usagePercentage == 0.0)
        #expect(emptyOverview.scannedTotalBytes == 0)
        #expect(emptyOverview.systemAndOtherBytes == 0)
        #expect(emptyOverview.totalScannedFileCount == 4)

        // 3. SecurityGuard safely trashes 0-byte file without error
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: zeroTxt, reason: "Adversarial 0-byte trash")
        #expect(!FileManager.default.fileExists(atPath: zeroTxt.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))

        // 4. RollbackLedger records and restores 0-byte file cleanly
        tier5LedgerLock.lock()
        defer { tier5LedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let record = ledger.recordOperation(
            actionType: .moveToTrash,
            sourcePath: zeroTxt.path,
            destinationPath: trashedURL.path,
            fileSize: 0,
            reason: "Zero-byte rollback test"
        )
        #expect(record.formattedSize == "--")
        #expect(record.exactByteCountDescription == "0 bytes")

        let restoredURL = try ledger.rollback(recordId: record.id)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        #expect(restoredURL.path == zeroTxt.path)
        let restoredAttrs = try FileManager.default.attributesOfItem(atPath: restoredURL.path)
        #expect((restoredAttrs[.size] as? Int64) == 0)

        try? FileManager.default.removeItem(at: restoredURL)
    }

    // MARK: - Challenge 2: Huge Simulated Files & Multi-TB Boundaries

    @Test("Adversarial: Multi-Terabyte capacity, huge simulated files (>100GB), and clamped invariants")
    func testHugeSimulatedFilesBoundaryAndProportionCalculations() {
        let fourTB: Int64 = 4_000_000_000_000 // 4 TB
        let oneAndHalfTB: Int64 = 1_500_000_000_000 // 1.5 TB available
        let twoAndHalfTB: Int64 = 2_500_000_000_000 // 2.5 TB used

        let videoSize: Int64 = 128_849_018_880 // ~120 GB
        let vmImageSize: Int64 = 483_183_820_800 // ~450 GB
        let backupArchiveSize: Int64 = 858_993_459_200 // ~800 GB

        let videoItem = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/Movies/raw_4k_footage.mov"),
            size: videoSize,
            modificationDate: Date(),
            category: .media,
            isDirectory: false
        )
        let vmItem = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/Downloads/VirtualDisk.dmg"),
            size: vmImageSize,
            modificationDate: Date(),
            category: .installers,
            isDirectory: false
        )
        let archiveItem = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/Downloads/CompleteSystemBackup.tar.gz"),
            size: backupArchiveSize,
            modificationDate: Date(),
            category: .archives,
            isDirectory: false
        )

        let totalScanned = videoSize + vmImageSize + backupArchiveSize // 1,471,026,298,880 bytes

        let categorySizes: [FileCategory: Int64] = [
            .media: videoSize,
            .installers: vmImageSize,
            .archives: backupArchiveSize
        ]

        let categoryFiles: [FileCategory: [ScannedItem]] = [
            .media: [videoItem],
            .installers: [vmItem],
            .archives: [archiveItem]
        ]

        let overview = StorageOverview(
            totalCapacity: fourTB,
            availableCapacity: oneAndHalfTB,
            usedCapacity: twoAndHalfTB,
            categorySizes: categorySizes,
            categoryFiles: categoryFiles,
            largestFiles: [archiveItem, vmItem, videoItem]
        )

        #expect(overview.scannedTotalBytes == totalScanned)
        #expect(overview.systemAndOtherBytes == (twoAndHalfTB - totalScanned))
        #expect(overview.usagePercentage == 0.625)
        #expect(overview.reclaimableEstimate == (vmImageSize + backupArchiveSize))
        #expect(overview.formattedTotal.contains("4") && (overview.formattedTotal.contains("TB") || overview.formattedTotal.contains("TiB") || overview.formattedTotal.contains("ТБ")))
        #expect(overview.files(for: .archives).first?.size == backupArchiveSize)

        // Extreme boundary: Sparse files or container where scanned total exceeds used capacity
        let extremeOverview = StorageOverview(
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000,
            usedCapacity: 500_000_000_000,
            categorySizes: [.archives: 800_000_000_000],
            categoryFiles: [.archives: [archiveItem]],
            largestFiles: [archiveItem]
        )
        // systemAndOtherBytes must clamp safely to 0 without underflow
        #expect(extremeOverview.systemAndOtherBytes == 0)

        // LiveVolumeMetrics clamped usage percentage
        let liveOverCapacity = LiveVolumeMetrics(
            totalCapacity: 1000,
            availableCapacity: 0,
            usedCapacity: 1500
        )
        #expect(liveOverCapacity.usagePercentage == 1.0)
    }

    // MARK: - Challenge 3: Special Characters, Emojis, Spaces, and Unicode in Paths

    @Test("Adversarial: Unicode, emojis, spaces, quotes, and percent escapes in file paths")
    func testSpecialCharactersEmojisAndSpacesInPathsAcrossAllSubsystems() throws {
        let sandbox = try Tier5Sandbox(prefix: "Unicode_Adv")
        defer { sandbox.cleanup() }

        // Construct pathological paths with emojis, spaces, CJK, Cyrillic, brackets, quotes
        let exoticSubdir = "📁 Dossier Projet 2026 [Électronique] & Спецификация"
        _ = try sandbox.createFolder(at: exoticSubdir)

        let file1Path = "\(exoticSubdir)/📊 Rapport Financier #1 (v2.0) + Notes!.pdf"
        let file2Path = "\(exoticSubdir)/🤖 Modèle IA_深度学习_v1.0.safetensors"
        let file3Path = "\(exoticSubdir)/🎵 Piste Audio — 48kHz 24-bit (Mix).wav"

        let content1 = Data("Financial report content with UTF-8 data".utf8)
        let content2 = Data("AI Model weights placeholder tensor".utf8)
        let content3 = Data("Audio waveform byte stream".utf8)

        let file1URL = try sandbox.createFile(at: file1Path, content: content1)
        let file2URL = try sandbox.createFile(at: file2Path, content: content2)
        let file3URL = try sandbox.createFile(at: file3Path, content: content3)

        // 1. SystemScanner categorizes exotic paths correctly
        let scanned = try SystemScanner.shared.scanDirectory(at: sandbox.rootURL, recursive: true, minFileSize: 1)
        #expect(scanned.count == 3)
        let catMap = Dictionary(grouping: scanned, by: { $0.category })
        #expect(catMap[.documents]?.count == 1)
        #expect(catMap[.skills]?.count == 1)
        #expect(catMap[.media]?.count == 1)

        // Verify all 3 URLs were discovered and matched
        let discoveredNames = Set(scanned.map { $0.url.lastPathComponent })
        #expect(discoveredNames.contains(file1URL.lastPathComponent))
        #expect(discoveredNames.contains(file2URL.lastPathComponent))
        #expect(discoveredNames.contains(file3URL.lastPathComponent))

        // 2. SecurityGuard validation handles non-ASCII and emojis without false rejection
        let validated1 = try SecurityGuard.shared.validatePath(file1URL.path, forModification: true)
        #expect(validated1.path == file1URL.path)

        // 3. Move file with emojis and spaces to Trash
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: file1URL, reason: "Unicode trashing test")
        #expect(!FileManager.default.fileExists(atPath: file1URL.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))

        tier5LedgerLock.lock()
        defer { tier5LedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let recId = UUID()
        ledger.recordOperation(OperationRecord(
            id: recId,
            actionType: .moveToTrash,
            sourcePath: file1URL.path,
            destinationPath: trashedURL.path,
            fileSize: Int64(content1.count),
            reason: "Unicode rollback test"
        ))

        // 4. Create an adversarial replacement at file1URL before rollback to test collision with unicode
        let adversaryData = Data("Adversary replacing financial report".utf8)
        try adversaryData.write(to: file1URL)

        // 5. Rollback resolves collision with (Restored)
        let restoredURL = try ledger.rollback(recordId: recId)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        #expect(restoredURL.path != file1URL.path)
        #expect(restoredURL.lastPathComponent.contains("(Restored)"))
        #expect(restoredURL.lastPathComponent.contains("📊 Rapport Financier"))

        // Bitwise content validation: both original and replacement remain intact
        let file1Data = try Data(contentsOf: file1URL)
        let restoredData = try Data(contentsOf: restoredURL)
        #expect(file1Data == adversaryData)
        #expect(restoredData == content1)

        try? FileManager.default.removeItem(at: restoredURL)
    }

    // MARK: - Challenge 4: Deep Nested Directories (15 Levels Deep)

    @Test("Adversarial: Deep nested directory traversal (15 levels deep) during scanning, planning, and execution")
    func testDeepNestedDirectoryTraversalAndOrganization() throws {
        let sandbox = try Tier5Sandbox(prefix: "DeepNest")
        defer { sandbox.cleanup() }

        // Build 15 nested directory levels
        var currentRelativePath = ""
        for i in 1...15 {
            currentRelativePath += (i == 1 ? "lvl\(i)" : "/lvl\(i)")
        }

        let level15Folder = try sandbox.createFolder(at: currentRelativePath)

        let deepCode = try sandbox.createFile(at: "\(currentRelativePath)/DeepAlgorithm.swift", content: Data(repeating: 0x41, count: 1024))
        let deepArchive = try sandbox.createFile(at: "\(currentRelativePath)/DeepAssets.tar.gz", content: Data(repeating: 0x42, count: 1024))
        let deepDoc = try sandbox.createFile(at: "\(currentRelativePath)/DeepSpec.pdf", content: Data(repeating: 0x43, count: 1024))

        // 1. SystemScanner recursive scan traverses all 15 levels
        let allScanned = try SystemScanner.shared.scanDirectory(at: sandbox.rootURL, recursive: true, minFileSize: 1)
        #expect(allScanned.count == 3)
        let categories = Set(allScanned.map { $0.category })
        #expect(categories.contains(.code))
        #expect(categories.contains(.archives))
        #expect(categories.contains(.documents))

        // 2. StorageAnalyzer scan retains deep files
        let overview = StorageAnalyzer.shared.scanSystemStorage(customTargets: [sandbox.rootURL])
        #expect(overview.totalScannedFileCount == 3)
        #expect(overview.files(for: .code).count == 1)
        #expect(overview.files(for: .archives).count == 1)
        #expect(overview.files(for: .documents).count == 1)
        #expect(overview.largestFiles.count == 3)

        // 3. FileOrganizer plans organization directly at level 15
        let proposals = try FileOrganizer.shared.planOrganization(for: level15Folder)
        #expect(proposals.count == 3)

        tier5LedgerLock.lock()
        defer { tier5LedgerLock.unlock() }

        let ledger = RollbackLedger.shared

        // 4. Execute proposals inside 15-level-deep folder
        try FileOrganizer.shared.executeProposals(proposals)

        #expect(!FileManager.default.fileExists(atPath: deepCode.path))
        #expect(!FileManager.default.fileExists(atPath: deepArchive.path))
        #expect(!FileManager.default.fileExists(atPath: deepDoc.path))

        let codeDest = level15Folder.appendingPathComponent("Code & Projects/DeepAlgorithm.swift")
        let archiveDest = level15Folder.appendingPathComponent("Archives/DeepAssets.tar.gz")
        let docDest = level15Folder.appendingPathComponent("Documents & Notes/DeepSpec.pdf")

        #expect(FileManager.default.fileExists(atPath: codeDest.path))
        #expect(FileManager.default.fileExists(atPath: archiveDest.path))
        #expect(FileManager.default.fileExists(atPath: docDest.path))

        // 5. Batch rollback restores all 3 deep files to level 15 root
        let afterHistory = ledger.loadHistory()
        let newRecords = afterHistory.filter { $0.sourcePath.contains("DeepNest") && !$0.isRolledBack }
        #expect(newRecords.count == 3)

        let rollbackCount = try ledger.rollbackAll(recordIds: newRecords.map { $0.id })
        #expect(rollbackCount == 3)

        #expect(FileManager.default.fileExists(atPath: deepCode.path))
        #expect(FileManager.default.fileExists(atPath: deepArchive.path))
        #expect(FileManager.default.fileExists(atPath: deepDoc.path))
    }

    // MARK: - Challenge 5: Symlink Traversal Rejection

    @Test("Adversarial: Symlink traversal pointing to /System, /usr/bin, /etc, ~/.ssh, and ~/.git blocked")
    func testSymlinkTraversalRejection() throws {
        let sandbox = try Tier5Sandbox(prefix: "Symlink_Adv")
        defer { sandbox.cleanup() }

        let fileManager = FileManager.default

        // 1. Symlink pointing to /System
        let symlinkToSystem = sandbox.fileURL("evil_system_link")
        try fileManager.createSymbolicLink(at: symlinkToSystem, withDestinationURL: URL(fileURLWithPath: "/System"))

        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try SecurityGuard.shared.validatePath(symlinkToSystem.path)
        }

        // 2. Symlink pointing to /usr/bin
        let symlinkToUsrBin = sandbox.fileURL("evil_usr_bin")
        try fileManager.createSymbolicLink(at: symlinkToUsrBin, withDestinationURL: URL(fileURLWithPath: "/usr/bin"))

        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try SecurityGuard.shared.validatePath(symlinkToUsrBin.path)
        }

        // 3. Symlink pointing to /private/etc
        let symlinkToEtc = sandbox.fileURL("evil_etc")
        try fileManager.createSymbolicLink(at: symlinkToEtc, withDestinationURL: URL(fileURLWithPath: "/private/etc"))

        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try SecurityGuard.shared.validatePath(symlinkToEtc.path)
        }

        // 4. Symlink pointing to ~/.ssh (modification check)
        let home = fileManager.homeDirectoryForCurrentUser
        let sshURL = home.appendingPathComponent(".ssh")
        let symlinkToSSH = sandbox.fileURL("evil_ssh")
        try fileManager.createSymbolicLink(at: symlinkToSSH, withDestinationURL: sshURL)

        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try SecurityGuard.shared.validatePath(symlinkToSSH.path, forModification: true)
        }

        // 5. Nested path with relative traversal inside symlink
        let relativeTraversalPath = "\(sandbox.rootURL.path)/sub/../../System/Library"
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try SecurityGuard.shared.validatePath(relativeTraversalPath)
        }
    }

    // MARK: - Challenge 6: Direct Trash Modification and Re-Trashing Blocked

    @Test("Adversarial: Direct trashing of ~/.Trash or re-trashing items already inside .Trash is rejected")
    func testDirectTrashModificationAndReTrashingBlocked() throws {
        let sandbox = try Tier5Sandbox(prefix: "Trash_Guard")
        defer { sandbox.cleanup() }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let userTrash = home.appendingPathComponent(".Trash")

        // 1. Direct validation of ~/.Trash for modification is blocked
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try SecurityGuard.shared.validatePath(userTrash.path, forModification: true)
        }

        // 2. Move a dummy file to Trash
        let testFile = try sandbox.createFile(at: "ToBeTrashedOnce.txt", content: Data("Trash me once".utf8))
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: testFile, reason: "First legitimate trash")
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))

        // 3. Attempting to trash the item a SECOND time while it is already inside .Trash is blocked
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try SecurityGuard.shared.safelyMoveToTrash(at: trashedURL, reason: "Malicious second trash attempt")
        }

        // Clean up
        try? FileManager.default.removeItem(at: trashedURL)
    }

    // MARK: - Challenge 7: Missing Trash Item Rollback Failure Mode

    @Test("Adversarial: Rollback on purged/missing trash item throws 404 and preserves ledger state")
    func testMissingTrashItemRollbackFailureMode() throws {
        let sandbox = try Tier5Sandbox(prefix: "PurgedTrash")
        defer { sandbox.cleanup() }

        let file = try sandbox.createFile(at: "PurgeMe.txt", content: Data("Will be purged".utf8))
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: file, reason: "Purge test")

        tier5LedgerLock.lock()
        defer { tier5LedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let recId = UUID()
        ledger.recordOperation(OperationRecord(
            id: recId,
            actionType: .moveToTrash,
            sourcePath: file.path,
            destinationPath: trashedURL.path,
            fileSize: 14,
            reason: "Purge test record"
        ))

        // Simulate external trash emptying by an adversary or system purge
        try FileManager.default.removeItem(at: trashedURL)
        #expect(!FileManager.default.fileExists(atPath: trashedURL.path))

        // Rollback on non-existent trash destination must throw 404
        #expect(throws: NSError.self) {
            _ = try ledger.rollback(recordId: recId)
        }

        // Crucial invariant: Record must NOT be marked isRolledBack = true!
        let history = ledger.loadHistory()
        let matching = history.first(where: { $0.id == recId })
        #expect(matching?.isRolledBack == false)
        #expect(matching?.isReversible == true)
    }

    // MARK: - Challenge 8: Parent Directory Recreation on Rollback

    @Test("Adversarial: Rollback recreates deleted intermediate parent directories")
    func testRollbackParentDirectoryRecreation() throws {
        let sandbox = try Tier5Sandbox(prefix: "ParentRecreation")
        defer { sandbox.cleanup() }

        let deepParent = "DeepProject/InternalModule/SubModule"
        let file = try sandbox.createFile(at: "\(deepParent)/Engine.swift", content: Data("class Engine {}".utf8))

        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: file, reason: "Parent recreation test")

        tier5LedgerLock.lock()
        defer { tier5LedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let recId = UUID()
        ledger.recordOperation(OperationRecord(
            id: recId,
            actionType: .moveToTrash,
            sourcePath: file.path,
            destinationPath: trashedURL.path,
            fileSize: 15,
            reason: "Parent recreation test"
        ))

        // Delete the entire parent folder DeepProject
        let projectRoot = sandbox.fileURL("DeepProject")
        try FileManager.default.removeItem(at: projectRoot)
        #expect(!FileManager.default.fileExists(atPath: projectRoot.path))

        // Trigger rollback: SecurityGuard.safelyMoveItem must recreate intermediate directories
        let restoredURL = try ledger.rollback(recordId: recId)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        #expect(restoredURL.path == file.path)

        let content = try String(contentsOf: restoredURL, encoding: .utf8)
        #expect(content == "class Engine {}")

        try? FileManager.default.removeItem(at: projectRoot)
    }

    // MARK: - Challenge 9: Multi-Step Chained Moves Rollback

    @Test("Adversarial: 4-hop chained move unraveled cleanly back to original source")
    func testComplexMultiStepChainedRollback() throws {
        let sandbox = try Tier5Sandbox(prefix: "ChainedMoves")
        defer { sandbox.cleanup() }

        let p0 = sandbox.fileURL("Step0.bin")
        let p1 = sandbox.fileURL("Hop1/Step1.bin")
        let p2 = sandbox.fileURL("Hop2/Sub/Step2.bin")
        let p3 = sandbox.fileURL("Hop3/Step3.bin")

        let originalData = Data("Chained 4-hop move payload".utf8)
        try originalData.write(to: p0)

        let security = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        tier5LedgerLock.lock()
        defer { tier5LedgerLock.unlock() }

        // Hop 1: p0 -> p1
        try security.safelyMoveItem(from: p0, to: p1)
        let id1 = UUID()
        ledger.recordOperation(OperationRecord(
            id: id1,
            timestamp: Date(timeIntervalSince1970: 100),
            actionType: .moveFile,
            sourcePath: p0.path,
            destinationPath: p1.path,
            fileSize: Int64(originalData.count),
            reason: "Hop 1"
        ))

        // Hop 2: p1 -> p2
        try security.safelyMoveItem(from: p1, to: p2)
        let id2 = UUID()
        ledger.recordOperation(OperationRecord(
            id: id2,
            timestamp: Date(timeIntervalSince1970: 200),
            actionType: .moveFile,
            sourcePath: p1.path,
            destinationPath: p2.path,
            fileSize: Int64(originalData.count),
            reason: "Hop 2"
        ))

        // Hop 3: p2 -> p3
        try security.safelyMoveItem(from: p2, to: p3)
        let id3 = UUID()
        ledger.recordOperation(OperationRecord(
            id: id3,
            timestamp: Date(timeIntervalSince1970: 300),
            actionType: .moveFile,
            sourcePath: p2.path,
            destinationPath: p3.path,
            fileSize: Int64(originalData.count),
            reason: "Hop 3"
        ))

        // Hop 4: p3 -> Trash
        let trashed = try security.safelyMoveToTrash(at: p3, reason: "Hop 4 trash")
        let id4 = UUID()
        ledger.recordOperation(OperationRecord(
            id: id4,
            timestamp: Date(timeIntervalSince1970: 400),
            actionType: .moveToTrash,
            sourcePath: p3.path,
            destinationPath: trashed.path,
            fileSize: Int64(originalData.count),
            reason: "Hop 4"
        ))

        #expect(!FileManager.default.fileExists(atPath: p0.path))
        #expect(!FileManager.default.fileExists(atPath: p1.path))
        #expect(!FileManager.default.fileExists(atPath: p2.path))
        #expect(!FileManager.default.fileExists(atPath: p3.path))
        #expect(FileManager.default.fileExists(atPath: trashed.path))

        // Unravel entire 4-hop chain via rollbackAll
        let restoredCount = try ledger.rollbackAll(recordIds: [id1, id2, id3, id4])
        #expect(restoredCount == 4)

        // File must be back at original p0!
        #expect(FileManager.default.fileExists(atPath: p0.path))
        let restoredData = try Data(contentsOf: p0)
        #expect(restoredData == originalData)

        try? FileManager.default.removeItem(at: p0)
    }

    // MARK: - Challenge 10: Folder Consolidation Self & Circular Merge Guard

    @Test("Adversarial: Folder consolidation guards against self-merges and circular child-into-parent moves")
    func testFolderConsolidationSelfAndCircularMergeGuard() throws {
        let sandbox = try Tier5Sandbox(prefix: "ConsolidationGuard")
        defer { sandbox.cleanup() }

        let folderA = try sandbox.createFolder(at: "FolderA")
        let fileA = try sandbox.createFile(at: "FolderA/sample.txt", content: Data("sample".utf8))

        // 1. Self merge attempt: source == destination
        let selfMergeProposal = FolderMergeProposal(
            sourceURL: folderA,
            destinationURL: folderA,
            itemCount: 1,
            totalSize: 6,
            reason: "Malicious self-merge"
        )

        // Should skip cleanly without destroying files
        try FileOrganizer.shared.executeFolderMerges([selfMergeProposal])
        #expect(FileManager.default.fileExists(atPath: fileA.path))

        // 2. Circular merge attempt: moving parent into child
        let childFolder = try sandbox.createFolder(at: "FolderA/NestedChild")
        let circularProposal = FolderMergeProposal(
            sourceURL: folderA,
            destinationURL: childFolder,
            itemCount: 1,
            totalSize: 6,
            reason: "Malicious circular merge"
        )

        // Should detect destination is inside source and skip safely
        try FileOrganizer.shared.executeFolderMerges([circularProposal])
        #expect(FileManager.default.fileExists(atPath: fileA.path))
    }

    // MARK: - Challenge 11: Concurrent Thread Safety on RollbackLedger

    @Test("Adversarial: Concurrent multi-threaded recording and reading maintains ledger integrity")
    func testConcurrentLedgerOperationsThreadSafety() throws {
        tier5LedgerLock.lock()
        defer { tier5LedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let initialCount = ledger.loadHistory().count

        let operationCount = 20

        DispatchQueue.concurrentPerform(iterations: operationCount) { i in
            let record = OperationRecord(
                id: UUID(),
                timestamp: Date(),
                actionType: .moveFile,
                sourcePath: "/dummy/source_\(i).txt",
                destinationPath: "/dummy/dest_\(i).txt",
                fileSize: Int64(i * 1000),
                reason: "Concurrent stress test \(i)"
            )
            ledger.recordOperation(record)
            _ = ledger.loadHistory()
            _ = ledger.recentOperations
        }

        let updatedHistory = ledger.loadHistory()
        #expect(updatedHistory.count >= initialCount + operationCount)
    }

    // MARK: - Challenge 12: Organization Proposal Numbered Sequence Collision Avoidance

    @Test("Adversarial: Pre-existing collisions in target folder correctly advance sequence to '(3)'")
    func testOrganizationProposalCollisionAvoidanceNumberedSequence() throws {
        let sandbox = try Tier5Sandbox(prefix: "Sequence_Collision")
        defer { sandbox.cleanup() }

        // Pre-create target folder with Main.swift, Main (1).swift, Main (2).swift
        let targetDir = try sandbox.createFolder(at: "Code & Projects")
        try Data("v0".utf8).write(to: targetDir.appendingPathComponent("Main.swift"))
        try Data("v1".utf8).write(to: targetDir.appendingPathComponent("Main (1).swift"))
        try Data("v2".utf8).write(to: targetDir.appendingPathComponent("Main (2).swift"))

        // Create new file at root to be organized
        _ = try sandbox.createFile(at: "Main.swift", content: Data("v3 fresh".utf8))

        let proposals = try FileOrganizer.shared.planOrganization(for: sandbox.rootURL)
        let mainProposal = proposals.first(where: { $0.fileName == "Main.swift" })

        #expect(mainProposal != nil)
        #expect(mainProposal?.proposedDestinationURL.lastPathComponent == "Main (3).swift")

        tier5LedgerLock.lock()
        defer { tier5LedgerLock.unlock() }

        try FileOrganizer.shared.executeProposals(proposals)

        let placedURL = targetDir.appendingPathComponent("Main (3).swift")
        #expect(FileManager.default.fileExists(atPath: placedURL.path))
        let placedContent = try String(contentsOf: placedURL, encoding: .utf8)
        #expect(placedContent == "v3 fresh")

        // Invariants: prior versions remain completely unmodified
        #expect(try String(contentsOf: targetDir.appendingPathComponent("Main.swift"), encoding: .utf8) == "v0")
        #expect(try String(contentsOf: targetDir.appendingPathComponent("Main (1).swift"), encoding: .utf8) == "v1")
        #expect(try String(contentsOf: targetDir.appendingPathComponent("Main (2).swift"), encoding: .utf8) == "v2")
    }

    // MARK: - Challenge 13: Exotic Categories and Uppercase Extensions

    @Test("Adversarial: Uppercase extensions, compound extensions, and keyword semantics")
    func testExoticFileCategoriesAndUppercaseExtensions() {
        let scanner = SystemScanner.shared

        // 1. Uppercase extensions
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/IMAGE.PNG")) == .images)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/SETUP.DMG")) == .installers)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/SOURCE.SWIFT")) == .code)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/VIDEO.MP4")) == .media)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/ARCHIVE.ZIP")) == .archives)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/DOC.PDF")) == .documents)

        // 2. Creative formats
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/lut_profile.cube")) == .creative)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/color_grade.look")) == .creative)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/motion_graphics.aep")) == .creative)

        // 3. AI Skills & Weights
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/assistant.agent")) == .skills)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/vision.onnx")) == .skills)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/model_q4.gguf")) == .skills)

        // 4. Academic keywords in filename override general extension
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/cs101_cheatsheet.pdf")) == .academics)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/midterm_exam_study_guide.docx")) == .academics)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/jiet_syllabus_2026.txt")) == .academics)

        // 5. Windows artifacts & Junk
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/desktop.ini")) == .junk)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/Thumbs.db")) == .junk)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/huge_download.crdownload")) == .junk)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/test/torrent_movie.part")) == .junk)
    }

    // MARK: - Challenge 14: Cryptographic Duplicate Collisions & False Positive Prevention

    @Test("Adversarial: Cryptographic duplicate detection avoids false positives on identical byte sizes")
    func testLargeDuplicateClusterCryptographicIntegrity() throws {
        let sandbox = try Tier5Sandbox(prefix: "Duplicates_Adv")
        defer { sandbox.cleanup() }

        let targetDir = try sandbox.createFolder(at: "DuplicateTest")

        // 3 files with identical size (4096 bytes) and identical content
        let dupData = Data(repeating: 0x41, count: 4096)
        let dup1 = targetDir.appendingPathComponent("copy1.dat")
        let dup2 = targetDir.appendingPathComponent("copy2.dat")
        let dup3 = targetDir.appendingPathComponent("copy3.dat")
        try dupData.write(to: dup1)
        try dupData.write(to: dup2)
        try dupData.write(to: dup3)

        // 2 files with IDENTICAL SIZE (4096 bytes) but DIFFERENT content (different hashes)
        var diffData1 = Data(repeating: 0x42, count: 4096)
        diffData1[100] = 0xFF
        var diffData2 = Data(repeating: 0x43, count: 4096)
        diffData2[200] = 0xAA
        let diff1 = targetDir.appendingPathComponent("different1.dat")
        let diff2 = targetDir.appendingPathComponent("different2.dat")
        try diffData1.write(to: diff1)
        try diffData2.write(to: diff2)

        let duplicateGroups = try SystemScanner.shared.findDuplicates(in: targetDir, minFileSize: 1024)

        // Must find exactly ONE duplicate group (for copy1, copy2, copy3)
        #expect(duplicateGroups.count == 1)
        let group = duplicateGroups[0]
        #expect(group.files.count == 3)
        #expect(group.fileSize == 4096)
        #expect(group.totalWastedSpace == 4096 * 2)

        // Must NOT contain different1 or different2
        let groupPaths = group.files.map { $0.url.lastPathComponent }
        #expect(groupPaths.contains("copy1.dat"))
        #expect(groupPaths.contains("copy2.dat"))
        #expect(groupPaths.contains("copy3.dat"))
        #expect(!groupPaths.contains("different1.dat"))
        #expect(!groupPaths.contains("different2.dat"))
    }
}
