import Testing
import Foundation
import SwiftUI
import AppKit
@testable import MacGuard

// MARK: - Test Sandbox Helper

private struct M4ChallengerSandbox {
    let rootURL: URL

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGuard_M4_Challenger_\(UUID().uuidString)")
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

// MARK: - Suite: Features F16 & F17 Empirical Challenger Stress Tests

@Suite("Features F16 & F17 Challenger: Empirical Stress & Hardening Tests", .serialized)
struct F16F17ChallengerStressTests {

    // =========================================================================
    // SECTION 1: CleanupEngine.inspectSubItems Directory Discovery & Inspection
    // =========================================================================

    @Test("F16 Stress: Inspecting empty directory returns empty array without error")
    func testInspectSubItemsEmptyDirectory() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let emptyFolder = try sandbox.createFolder(at: "EmptyFolder")
        let subItems = CleanupEngine.shared.inspectSubItems(at: emptyFolder)

        #expect(subItems.isEmpty)
    }

    @Test("F16 Stress: Inspecting non-existent path or file path returns empty array gracefully")
    func testInspectSubItemsNonExistentOrFilePath() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let nonExistentURL = sandbox.fileURL("DoesNotExist_\(UUID().uuidString)")
        let nonExistentItems = CleanupEngine.shared.inspectSubItems(at: nonExistentURL)
        #expect(nonExistentItems.isEmpty)

        let fileURL = try sandbox.createFile(at: "justAFile.txt", content: Data("sample".utf8))
        let fileItems = CleanupEngine.shared.inspectSubItems(at: fileURL)
        #expect(fileItems.isEmpty)
    }

    @Test("F16 Stress: Inspecting directory with permission-denied permissions handles gracefully")
    func testInspectSubItemsPermissionDeniedDirectory() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let lockedFolder = try sandbox.createFolder(at: "LockedFolder")
        try sandbox.createFile(at: "LockedFolder/secret.txt", content: Data("private".utf8))

        // Restrict read permissions on the directory (chmod 0000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedFolder.path)
        defer {
            // Restore permissions so sandbox cleanup can delete it
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedFolder.path)
        }

        // Must not crash, should return empty array
        let subItems = CleanupEngine.shared.inspectSubItems(at: lockedFolder)
        #expect(subItems.isEmpty)
    }

    @Test("F16 Stress: Directory containing permission-denied child directory calculates size safely")
    func testInspectSubItemsWithPermissionDeniedChild() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let parentFolder = try sandbox.createFolder(at: "ParentWithLockedChild")
        let childLocked = try sandbox.createFolder(at: "ParentWithLockedChild/LockedSub")
        try sandbox.createFile(at: "ParentWithLockedChild/normal.txt", content: Data(repeating: 0x41, count: 2048))

        // Restrict child permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: childLocked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: childLocked.path)
        }

        let subItems = CleanupEngine.shared.inspectSubItems(at: parentFolder)
        #expect(subItems.count == 2)

        let normalItem = subItems.first(where: { $0.name == "normal.txt" })
        #expect(normalItem?.size == 2048)
        #expect(normalItem?.isDirectory == false)

        let lockedItem = subItems.first(where: { $0.name == "LockedSub" })
        #expect(lockedItem?.isDirectory == true)
        // Child cannot be enumerated, so size resolves to 0 without crashing
        #expect(lockedItem?.size == 0)
    }

    @Test("F16 Stress: Deeply nested directory hierarchy aggregates total recursive size accurately")
    func testInspectSubItemsDeeplyNestedHierarchy() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let rootDir = try sandbox.createFolder(at: "DeepRoot")
        var currentPath = "DeepRoot"
        var totalDeepBytes: Int64 = 0

        // Create 10 levels of nesting with files at each level
        for depth in 1...10 {
            currentPath += "/level_\(depth)"
            _ = try sandbox.createFolder(at: currentPath)
            let fileBytes = 512 * depth
            try sandbox.createFile(at: "\(currentPath)/data_\(depth).bin", content: Data(repeating: UInt8(depth), count: fileBytes))
            totalDeepBytes += Int64(fileBytes)
        }

        // Also create a standalone sibling file at root
        try sandbox.createFile(at: "DeepRoot/root_file.txt", content: Data(repeating: 0x58, count: 100))

        let subItems = CleanupEngine.shared.inspectSubItems(at: rootDir)
        // Only immediate children of DeepRoot should be enumerated: "level_1" and "root_file.txt"
        #expect(subItems.count == 2)

        let level1Item = subItems.first(where: { $0.name == "level_1" })
        #expect(level1Item != nil)
        #expect(level1Item?.isDirectory == true)
        #expect(level1Item?.size == totalDeepBytes)

        let rootFileItem = subItems.first(where: { $0.name == "root_file.txt" })
        #expect(rootFileItem != nil)
        #expect(rootFileItem?.isDirectory == false)
        #expect(rootFileItem?.size == 100)

        // Subitems must be sorted descending by size: level_1 (larger) before root_file.txt
        #expect(subItems[0].name == "level_1")
        #expect(subItems[1].name == "root_file.txt")
    }

    @Test("F16 Stress: Inspection limit parameter bounds output correctly")
    func testInspectSubItemsLimitParameter() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let testDir = try sandbox.createFolder(at: "LimitFolder")
        for i in 1...10 {
            try sandbox.createFile(at: "LimitFolder/file_\(i).txt", content: Data(repeating: UInt8(i), count: i * 100))
        }

        let engine = CleanupEngine.shared

        // Limit = 0 -> empty
        let itemsLimit0 = engine.inspectSubItems(at: testDir, limit: 0)
        #expect(itemsLimit0.isEmpty)

        // Limit = 3 -> exactly 3 largest items
        let itemsLimit3 = engine.inspectSubItems(at: testDir, limit: 3)
        #expect(itemsLimit3.count == 3)
        #expect(itemsLimit3[0].size >= itemsLimit3[1].size)
        #expect(itemsLimit3[1].size >= itemsLimit3[2].size)

        // Limit = 100 on 10 items -> returns all 10
        let itemsLimit100 = engine.inspectSubItems(at: testDir, limit: 100)
        #expect(itemsLimit100.count == 10)
    }

    // =========================================================================
    // SECTION 2: CleanupEngine.executeCleanup Safe Trashing & Reversibility
    // =========================================================================

    @Test("F16 & F17 Stress: Multi-target real file trashing and single rollback restoration")
    func testExecuteCleanupMultiTargetSafeTrashingAndRollback() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let file1 = try sandbox.createFile(at: "cache1.bin", content: Data("Cache Payload One".utf8))
        let file2 = try sandbox.createFile(at: "cache2.bin", content: Data("Cache Payload Two".utf8))
        let folder1 = try sandbox.createFolder(at: "folderCache")
        try sandbox.createFile(at: "folderCache/inner.txt", content: Data("Inner Payload".utf8))

        let target1 = CleanupTarget(
            name: "Cache One",
            url: file1,
            size: 17,
            safetyTier: .safe,
            category: "Developer Caches",
            explanation: "Xcode cache 1",
            isSelected: true
        )
        let target2 = CleanupTarget(
            name: "Cache Two",
            url: file2,
            size: 17,
            safetyTier: .safe,
            category: "Developer Caches",
            explanation: "Xcode cache 2",
            isSelected: true
        )
        let target3 = CleanupTarget(
            name: "Folder Cache",
            url: folder1,
            size: 13,
            safetyTier: .safe,
            category: "Developer Caches",
            explanation: "Directory cache",
            isSelected: true,
            isDirectory: true
        )

        let records = try CleanupEngine.shared.executeCleanup(targets: [target1, target2, target3])
        #expect(records.count == 3)

        // Verify source paths NO LONGER exist
        #expect(!FileManager.default.fileExists(atPath: file1.path))
        #expect(!FileManager.default.fileExists(atPath: file2.path))
        #expect(!FileManager.default.fileExists(atPath: folder1.path))

        // Verify destination paths exist in Trash
        for rec in records {
            #expect(rec.actionType == .moveToTrash)
            #expect(rec.destinationPath != nil)
            #expect(FileManager.default.fileExists(atPath: rec.destinationPath!))
            #expect(rec.byteAccurateSize != nil && rec.byteAccurateSize! > 0)
        }

        // Test single rollback for each record
        for rec in records {
            let restoredURL = try RollbackLedger.shared.rollback(recordId: rec.id)
            #expect(FileManager.default.fileExists(atPath: restoredURL.path))
            #expect(!FileManager.default.fileExists(atPath: rec.destinationPath!))
        }

        // Verify content restored identically
        let c1 = try String(contentsOf: file1, encoding: .utf8)
        let c2 = try String(contentsOf: file2, encoding: .utf8)
        let c3 = try String(contentsOf: folder1.appendingPathComponent("inner.txt"), encoding: .utf8)
        #expect(c1 == "Cache Payload One")
        #expect(c2 == "Cache Payload Two")
        #expect(c3 == "Inner Payload")

        // Verify second rollback attempt on already-restored item throws code 400
        #expect(throws: Error.self) {
            try RollbackLedger.shared.rollback(recordId: records[0].id)
        }
    }

    // =========================================================================
    // SECTION 3: Batch Rollback with Adversarial Edge Cases
    // =========================================================================

    @Test("F17 Stress: Batch rollbackAll handles partial success when some trash files are missing")
    func testRollbackAllPartialSuccessWithMissingTrashFiles() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let file1 = try sandbox.createFile(at: "batch_survivor_1.txt", content: Data("Survivor 1".utf8))
        let file2 = try sandbox.createFile(at: "batch_deleted_externally.txt", content: Data("Deleted In Trash".utf8))
        let file3 = try sandbox.createFile(at: "batch_survivor_2.txt", content: Data("Survivor 2".utf8))

        let sec = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        let t1 = try sec.safelyMoveToTrash(at: file1)
        let t2 = try sec.safelyMoveToTrash(at: file2)
        let t3 = try sec.safelyMoveToTrash(at: file3)

        let rec1 = ledger.recordOperation(actionType: .moveToTrash, sourcePath: file1.path, destinationPath: t1.path, fileSize: 10, reason: "Batch resilient test 1")
        let rec2 = ledger.recordOperation(actionType: .moveToTrash, sourcePath: file2.path, destinationPath: t2.path, fileSize: 16, reason: "Batch resilient test 2")
        let rec3 = ledger.recordOperation(actionType: .moveToTrash, sourcePath: file3.path, destinationPath: t3.path, fileSize: 10, reason: "Batch resilient test 3")

        // Simulate external deletion of t2 (e.g. user emptied or permanently deleted this file from Trash)
        try FileManager.default.removeItem(at: t2)
        #expect(!FileManager.default.fileExists(atPath: t2.path))

        // Execute batch rollback containing rec1, rec2, and rec3
        let restoredCount = try ledger.rollbackAll(recordIds: [rec1.id, rec2.id, rec3.id])

        // Must restore 2 records and not crash or abort
        #expect(restoredCount == 2)

        // Verify rec1 and rec3 were restored successfully
        #expect(FileManager.default.fileExists(atPath: file1.path))
        #expect(FileManager.default.fileExists(atPath: file3.path))

        // Check ledger status: rec1 and rec3 are rolled back, rec2 is NOT rolled back
        let currentRecords = ledger.loadHistory()
        let updatedRec1 = currentRecords.first(where: { $0.id == rec1.id })
        let updatedRec2 = currentRecords.first(where: { $0.id == rec2.id })
        let updatedRec3 = currentRecords.first(where: { $0.id == rec3.id })

        #expect(updatedRec1?.isRolledBack == true)
        #expect(updatedRec2?.isRolledBack == false)
        #expect(updatedRec3?.isRolledBack == true)
    }

    @Test("F17 Stress: Batch rollbackAll throws error when ALL requested items fail")
    func testRollbackAllThrowsWhenAllItemsFail() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let file1 = try sandbox.createFile(at: "ghost_file.txt", content: Data("Ghost".utf8))
        let sec = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        let t1 = try sec.safelyMoveToTrash(at: file1)
        let rec = ledger.recordOperation(actionType: .moveToTrash, sourcePath: file1.path, destinationPath: t1.path, fileSize: 5, reason: "Ghost test")

        // Remove from Trash externally
        try FileManager.default.removeItem(at: t1)

        // When all eligible items fail, rollbackAll must throw the underlying error
        #expect(throws: Error.self) {
            try ledger.rollbackAll(recordIds: [rec.id])
        }
    }

    @Test("F17 Stress: Batch rollbackAll with empty array or non-existent IDs returns 0 safely")
    func testRollbackAllEmptyOrNonExistentIDs() throws {
        let ledger = RollbackLedger.shared

        let zero1 = try ledger.rollbackAll(recordIds: [])
        #expect(zero1 == 0)

        let fakeUUID = UUID()
        let zero2 = try ledger.rollbackAll(recordIds: [fakeUUID])
        #expect(zero2 == 0)
    }

    @Test("F17 Stress: Chained file movements restored in strict reverse-chronological (LIFO) order")
    func testRollbackAllStrictLIFOChainedMovement() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let path1 = sandbox.fileURL("origin.txt")
        let path2 = sandbox.fileURL("intermediate.txt")
        let path3 = sandbox.fileURL("final_staging.txt")

        try Data("Chained Movement Integrity".utf8).write(to: path1)

        let sec = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        // Step 1: Move origin -> intermediate
        try sec.safelyMoveItem(from: path1, to: path2)
        let rec1 = ledger.recordOperation(actionType: .moveFile, sourcePath: path1.path, destinationPath: path2.path, fileSize: 26, reason: "Step 1: Move to intermediate")

        // Step 2: Move intermediate -> final_staging
        try sec.safelyMoveItem(from: path2, to: path3)
        let rec2 = ledger.recordOperation(actionType: .moveFile, sourcePath: path2.path, destinationPath: path3.path, fileSize: 26, reason: "Step 2: Move to staging")

        // Step 3: Trash from final_staging -> Trash
        let trashURL = try sec.safelyMoveToTrash(at: path3)
        let rec3 = ledger.recordOperation(actionType: .moveToTrash, sourcePath: path3.path, destinationPath: trashURL.path, fileSize: 26, reason: "Step 3: Move to trash")

        // Verify current state: file only exists in Trash
        #expect(!FileManager.default.fileExists(atPath: path1.path))
        #expect(!FileManager.default.fileExists(atPath: path2.path))
        #expect(!FileManager.default.fileExists(atPath: path3.path))
        #expect(FileManager.default.fileExists(atPath: trashURL.path))

        // Batch rollback all 3 operations: [rec1, rec2, rec3]
        // If executed in LIFO order:
        // rec3 (newest) reverses: Trash -> path3
        // rec2 reverses: path3 -> path2
        // rec1 reverses: path2 -> path1
        // File ends up at original path1!
        let restoredCount = try ledger.rollbackAll(recordIds: [rec1.id, rec2.id, rec3.id])
        #expect(restoredCount == 3)

        #expect(FileManager.default.fileExists(atPath: path1.path))
        #expect(!FileManager.default.fileExists(atPath: path2.path))
        #expect(!FileManager.default.fileExists(atPath: path3.path))
        #expect(!FileManager.default.fileExists(atPath: trashURL.path))

        let finalContent = try String(contentsOf: path1, encoding: .utf8)
        #expect(finalContent == "Chained Movement Integrity")
    }

    // =========================================================================
    // SECTION 4: Search Filter Robustness & Boundary Cases in ApprovalCenter
    // =========================================================================

    @Test("F17 Stress: Search filter handles adversarial regex metacharacters without crashing")
    func testSearchFilterAdversarialRegexCharacters() {
        let op = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: "/Users/test/Downloads/Special [2026] + $100 (v1.0).zip",
            destinationPath: "/Users/test/.Trash/Special [2026] + $100 (v1.0).zip",
            fileSize: 1048576,
            reason: "Trashing archive with special metacharacters: .* [a-z] (foo|bar) \\d+ ^$"
        )

        // Adversarial query strings containing regex metacharacters
        let dangerousQueries = [
            ".*", "[a-z]+", "\\d+", "^$", "(foo|bar)", "???", "***", "+++",
            "[2026]", "(v1.0)", "$100", "+", "]", "[", "(", ")", "\\", "{2,5}", "$", "^"
        ]

        for query in dangerousQueries {
            // Must evaluate without throwing an exception or crashing
            let matchesFileName = op.fileName.localizedCaseInsensitiveContains(query)
            let matchesReason = op.reason.localizedCaseInsensitiveContains(query)
            let matchesPath = op.sourcePath.localizedCaseInsensitiveContains(query)

            // Specifically, literal tokens present in the fileName must match!
            if query == "[2026]" || query == "(v1.0)" || query == "$100" || query == "+" {
                #expect(matchesFileName, "Query '\(query)' should match literal characters in fileName")
                #expect(matchesPath, "Query '\(query)' should match literal characters in sourcePath")
            }
            if query == ".*" || query == "^$" || query == "(foo|bar)" {
                #expect(matchesReason, "Query '\(query)' should match literal characters in reason")
            }
        }
    }

    @Test("F17 Stress: Search filter case insensitivity and multi-field queries")
    func testSearchFilterCaseInsensitivityAndMultiField() {
        let op = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: "/Users/alice/Library/Caches/com.apple.dt.Xcode/DerivedData.cache",
            destinationPath: "/Users/alice/.Trash/DerivedData.cache",
            fileSize: 52428800,
            reason: "AI Maintenance auto cache purge"
        )

        // 1. Filename case insensitivity
        #expect(op.fileName.localizedCaseInsensitiveContains("deriveddata"))
        #expect(op.fileName.localizedCaseInsensitiveContains("DERIVEDDATA"))
        #expect(op.fileName.localizedCaseInsensitiveContains("DerivedData"))

        // 2. Reason matching
        #expect(op.reason.localizedCaseInsensitiveContains("ai maintenance"))
        #expect(op.reason.localizedCaseInsensitiveContains("MAINTENANCE"))
        #expect(op.reason.localizedCaseInsensitiveContains("purge"))

        // 3. Action type matching
        #expect(op.actionType.rawValue.localizedCaseInsensitiveContains("trash"))
        #expect(op.actionType.rawValue.localizedCaseInsensitiveContains("MOVE TO TRASH"))

        // 4. Source path matching
        #expect(op.sourcePath.localizedCaseInsensitiveContains("Xcode"))
        #expect(op.sourcePath.localizedCaseInsensitiveContains("library/caches"))

        // 5. Formatted size matching
        #expect(op.formattedSize.localizedCaseInsensitiveContains("MB"))
    }

    // =========================================================================
    // SECTION 5: Collision Resolution on Rollback (resolveNonCollidingURL)
    // =========================================================================

    @Test("F17 Stress: Rollback collision avoidance resolves with non-colliding name without overwriting")
    func testRollbackCollisionResolutionPreservesBothFiles() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let originalFile = try sandbox.createFile(at: "document.pdf", content: Data("Original File Content".utf8))

        let sec = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        // Move to trash
        let trashURL = try sec.safelyMoveToTrash(at: originalFile)
        let rec = ledger.recordOperation(actionType: .moveToTrash, sourcePath: originalFile.path, destinationPath: trashURL.path, fileSize: 21, reason: "Collision test")

        // Create a NEW file with the same name at the original location
        try sandbox.createFile(at: "document.pdf", content: Data("New Imposter Content".utf8))

        // Perform rollback
        let restoredURL = try ledger.rollback(recordId: rec.id)

        // Restored URL must NOT overwrite document.pdf
        #expect(restoredURL.path != originalFile.path)
        #expect(FileManager.default.fileExists(atPath: originalFile.path))
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))

        // Verify contents of both files are preserved perfectly
        let imposterContent = try String(contentsOf: originalFile, encoding: .utf8)
        let restoredContent = try String(contentsOf: restoredURL, encoding: .utf8)

        #expect(imposterContent == "New Imposter Content")
        #expect(restoredContent == "Original File Content")
        #expect(restoredURL.lastPathComponent.contains("Restored") || restoredURL.lastPathComponent.contains("(1)"))
    }

    @Test("F17 Stress: Multi-step sequential collision resolution numbers properly: (1), (2), (3)")
    func testMultiStepCollisionResolutionNumbering() throws {
        let sandbox = try M4ChallengerSandbox()
        defer { sandbox.cleanup() }

        let baseFile = try sandbox.createFile(at: "sample.txt", content: Data("Base".utf8))
        _ = try sandbox.createFile(at: "sample (1).txt", content: Data("First Collision".utf8))
        _ = try sandbox.createFile(at: "sample (2).txt", content: Data("Second Collision".utf8))

        let resolved = RollbackLedger.resolveNonCollidingURL(for: baseFile, suffix: "")
        #expect(resolved.lastPathComponent == "sample (3).txt")
    }

    // =========================================================================
    // SECTION 6: UI Invariants & Filter Integrity Stress Tests
    // =========================================================================

    @Test("F16 Stress: CleanupTarget dynamic selection and selectedBytes aggregation")
    func testCleanupTargetDynamicSelectionAggregation() {
        var targets = [
            CleanupTarget(name: "T1", url: URL(fileURLWithPath: "/tmp/1"), size: 1000, safetyTier: .safe, category: "Caches", explanation: "E1", isSelected: true),
            CleanupTarget(name: "T2", url: URL(fileURLWithPath: "/tmp/2"), size: 2000, safetyTier: .reviewRecommended, category: "Installers", explanation: "E2", isSelected: false),
            CleanupTarget(name: "T3", url: URL(fileURLWithPath: "/tmp/3"), size: 4000, safetyTier: .safe, category: "Logs", explanation: "E3", isSelected: true)
        ]

        let initialSelectedBytes = targets.filter(\.isSelected).reduce(0) { $0 + $1.size }
        #expect(initialSelectedBytes == 5000)

        // Toggle T2 on
        targets[1].isSelected = true
        let allSelectedBytes = targets.filter(\.isSelected).reduce(0) { $0 + $1.size }
        #expect(allSelectedBytes == 7000)

        // Deselect all
        for i in targets.indices { targets[i].isSelected = false }
        let zeroSelectedBytes = targets.filter(\.isSelected).reduce(0) { $0 + $1.size }
        #expect(zeroSelectedBytes == 0)
    }

    @Test("F17 Stress: OperationRecord byte-accurate description handles zero, nil, and positive bytes")
    func testOperationRecordByteAccurateDescriptions() {
        let opPos = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: "/tmp/file.dat",
            destinationPath: "/tmp/.Trash/file.dat",
            fileSize: 1024,
            reason: "Pos"
        )
        #expect(opPos.exactByteCountDescription.contains("1,024 bytes"))

        let opZero = OperationRecord(
            actionType: .createDirectory,
            sourcePath: "/tmp/dir",
            fileSize: 0,
            reason: "Zero"
        )
        #expect(opZero.exactByteCountDescription == "0 bytes")

        let opNil = OperationRecord(
            actionType: .createDirectory,
            sourcePath: "/tmp/dir2",
            fileSize: nil,
            reason: "Nil"
        )
        #expect(opNil.exactByteCountDescription == "0 bytes")
    }
}
