import Foundation
import Testing
@testable import MacGuard

private let adversarialLedgerLock = NSLock()

private struct AdversarialSandbox {
    let rootURL: URL

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGuard_Adv_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.rootURL = tempDir.resolvingSymlinksInPath()
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

@Suite("Adversarial Reversibility & Collision Challenge Tests", .serialized)
struct AdversarialReversibilityTests {

    // MARK: - Challenge 1: Rollback Collision Handling

    @Test("Adversarial: File A moved to trash and replaced by new File A restores as 'A (Restored).ext' without overwriting or error")
    func testRollbackCollisionSingleFile() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        let originalContent = Data("Original File A content — critical business contract".utf8)
        let fileA = try sandbox.createFile(at: "Contract.pdf", content: originalContent)

        // Step 1: Safely move file A to macOS Trash
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: fileA, reason: "Adv Test Trash A")
        #expect(!FileManager.default.fileExists(atPath: fileA.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))

        adversarialLedgerLock.lock()
        defer { adversarialLedgerLock.unlock() }

        let recordId = UUID()
        let ledger = RollbackLedger.shared
        ledger.recordOperation(OperationRecord(
            id: recordId,
            actionType: .moveToTrash,
            sourcePath: fileA.path,
            destinationPath: trashedURL.path,
            fileSize: Int64(originalContent.count),
            reason: "Adv Test Collision Record"
        ))

        // Step 2: Adversary creates a brand new file at the original path before rollback
        let adversaryContent = Data("Adversarial replacement file at Contract.pdf".utf8)
        try adversaryContent.write(to: fileA)
        #expect(FileManager.default.fileExists(atPath: fileA.path))

        // Step 3: Trigger rollback
        let restoredURL = try ledger.rollback(recordId: recordId)

        // Step 4: Assertions
        // 4a. Restored URL should exist
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        // 4b. Restored URL must NOT overwrite fileA
        #expect(restoredURL.path != fileA.path)
        #expect(restoredURL.lastPathComponent == "Contract (Restored).pdf")
        // 4c. Existing file A must remain completely intact
        let fileAContent = try Data(contentsOf: fileA)
        #expect(fileAContent == adversaryContent)
        // 4d. Restored file must contain exact original content
        let restoredContent = try Data(contentsOf: restoredURL)
        #expect(restoredContent == originalContent)

        // Clean up trashed remnant
        try? FileManager.default.removeItem(at: restoredURL)
    }

    @Test("Adversarial: Multiple collisions sequentially produce '(Restored)', '(Restored 2)', '(Restored 3)'")
    func testRollbackMultipleSequentialCollisions() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        let baseFile = sandbox.fileURL("Document.txt")
        try Data("Original".utf8).write(to: baseFile)

        // Simulate existing collisions
        let restored1 = sandbox.fileURL("Document (Restored).txt")
        try Data("Collision 1".utf8).write(to: restored1)

        let restored2 = sandbox.fileURL("Document (Restored 2).txt")
        try Data("Collision 2".utf8).write(to: restored2)

        // URL resolver should detect both existing and pick (Restored 3)
        let resolved = RollbackLedger.resolveNonCollidingURL(for: baseFile)
        #expect(resolved.lastPathComponent == "Document (Restored 3).txt")
        #expect(!FileManager.default.fileExists(atPath: resolved.path))
    }

    @Test("Adversarial: Extensionless file and compound extension rollback collision")
    func testRollbackCollisionEdgeFilenames() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        // Extensionless file
        let noExtFile = sandbox.fileURL("LICENSE")
        try Data("License content".utf8).write(to: noExtFile)
        let resolvedNoExt = RollbackLedger.resolveNonCollidingURL(for: noExtFile)
        #expect(resolvedNoExt.lastPathComponent == "LICENSE (Restored)")

        // Compound extension file: archive.tar.gz
        let compoundFile = sandbox.fileURL("archive.tar.gz")
        try Data("Archive content".utf8).write(to: compoundFile)
        let resolvedCompound = RollbackLedger.resolveNonCollidingURL(for: compoundFile)
        #expect(resolvedCompound.lastPathComponent == "archive.tar (Restored).gz")
    }

    // MARK: - Challenge 2: Batch Rollback (rollbackAll)

    @Test("Adversarial: Batch rollbackAll executes in strict reverse-chronological (LIFO) order")
    func testBatchRollbackLIFOOrder() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        // Set up chained file moves: Path1 -> Path2 -> Path3
        // If rolled back in forward order, moving Path1 to Path2 fails because file is at Path3.
        // It MUST roll back Path2 -> Path3 first, then Path1 -> Path2!
        let path1 = sandbox.fileURL("Step1.dat")
        let path2 = sandbox.fileURL("Step2.dat")
        let path3 = sandbox.fileURL("Step3.dat")

        let initialData = Data("Chained move test data".utf8)
        try initialData.write(to: path1)

        let security = SecurityGuard.shared
        let ledger = RollbackLedger.shared

        // Move 1: Path1 -> Path2
        try security.safelyMoveItem(from: path1, to: path2)
        adversarialLedgerLock.lock()
        defer { adversarialLedgerLock.unlock() }

        let id1 = UUID()
        let t1 = Date(timeIntervalSince1970: 1000)
        let rec1 = OperationRecord(id: id1, timestamp: t1, actionType: .moveFile, sourcePath: path1.path, destinationPath: path2.path, fileSize: Int64(initialData.count), reason: "Chained 1")
        ledger.recordOperation(rec1)

        // Move 2: Path2 -> Path3
        try security.safelyMoveItem(from: path2, to: path3)
        let id2 = UUID()
        let t2 = Date(timeIntervalSince1970: 2000) // Later timestamp
        let rec2 = OperationRecord(id: id2, timestamp: t2, actionType: .moveFile, sourcePath: path2.path, destinationPath: path3.path, fileSize: Int64(initialData.count), reason: "Chained 2")
        ledger.recordOperation(rec2)

        #expect(!FileManager.default.fileExists(atPath: path1.path))
        #expect(!FileManager.default.fileExists(atPath: path2.path))
        #expect(FileManager.default.fileExists(atPath: path3.path))

        // Execute batch rollback
        let count = try ledger.rollbackAll(recordIds: [id1, id2])
        #expect(count == 2)

        // File should have cleanly returned to Path1
        #expect(FileManager.default.fileExists(atPath: path1.path))
        #expect(!FileManager.default.fileExists(atPath: path2.path))
        #expect(!FileManager.default.fileExists(atPath: path3.path))

        let finalData = try Data(contentsOf: path1)
        #expect(finalData == initialData)
    }

    @Test("Adversarial: Batch rollbackAll handles partial failures gracefully without halting other operations")
    func testBatchRollbackPartialFailure() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        let fileGood1 = try sandbox.createFile(at: "Good1.txt", content: Data("Good 1".utf8))
        let fileGood2 = try sandbox.createFile(at: "Good2.txt", content: Data("Good 2".utf8))

        let trashGood1 = try SecurityGuard.shared.safelyMoveToTrash(at: fileGood1)
        let trashGood2 = try SecurityGuard.shared.safelyMoveToTrash(at: fileGood2)

        adversarialLedgerLock.lock()
        defer { adversarialLedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let idGood1 = UUID()
        let idPhantom = UUID()
        let idGood2 = UUID()

        // Good operation 1
        ledger.recordOperation(OperationRecord(
            id: idGood1,
            timestamp: Date(timeIntervalSince1970: 100),
            actionType: .moveToTrash,
            sourcePath: fileGood1.path,
            destinationPath: trashGood1.path,
            fileSize: 6,
            reason: "Partial failure test good 1"
        ))

        // Phantom operation whose destination file in Trash does NOT exist
        let nonExistentTrashPath = sandbox.fileURL("non_existent_in_trash_\(UUID().uuidString).txt").path
        ledger.recordOperation(OperationRecord(
            id: idPhantom,
            timestamp: Date(timeIntervalSince1970: 200),
            actionType: .moveToTrash,
            sourcePath: sandbox.fileURL("Phantom.txt").path,
            destinationPath: nonExistentTrashPath,
            fileSize: 100,
            reason: "Partial failure test phantom"
        ))

        // Good operation 2
        ledger.recordOperation(OperationRecord(
            id: idGood2,
            timestamp: Date(timeIntervalSince1970: 300),
            actionType: .moveToTrash,
            sourcePath: fileGood2.path,
            destinationPath: trashGood2.path,
            fileSize: 6,
            reason: "Partial failure test good 2"
        ))

        // Batch rollback on all three
        let restoredCount = try ledger.rollbackAll(recordIds: [idGood1, idPhantom, idGood2])

        // Should successfully restore the 2 good files despite phantom failing
        #expect(restoredCount == 2)
        #expect(FileManager.default.fileExists(atPath: fileGood1.path))
        #expect(FileManager.default.fileExists(atPath: fileGood2.path))

        // Check history state
        let history = ledger.loadHistory()
        let rec1 = history.first(where: { $0.id == idGood1 })
        let recPhantom = history.first(where: { $0.id == idPhantom })
        let rec2 = history.first(where: { $0.id == idGood2 })

        #expect(rec1?.isRolledBack == true)
        #expect(rec2?.isRolledBack == true)
        #expect(recPhantom?.isRolledBack == false) // Phantom remains not rolled back
    }

    @Test("Adversarial: Batch rollbackAll throws error if all operations in batch fail")
    func testBatchRollbackAllFailThrows() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        adversarialLedgerLock.lock()
        defer { adversarialLedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let idPhantom = UUID()
        ledger.recordOperation(OperationRecord(
            id: idPhantom,
            actionType: .moveToTrash,
            sourcePath: sandbox.fileURL("FakeSource.txt").path,
            destinationPath: sandbox.fileURL("FakeTrash.txt").path,
            fileSize: 10,
            reason: "Total failure test"
        ))

        #expect(throws: Error.self) {
            _ = try ledger.rollbackAll(recordIds: [idPhantom])
        }
    }

    @Test("Adversarial: Batch rollbackAll is strictly idempotent")
    func testBatchRollbackIdempotency() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        let file = try sandbox.createFile(at: "Idempotent.txt", content: Data("Idempotency test".utf8))
        let trash = try SecurityGuard.shared.safelyMoveToTrash(at: file)

        adversarialLedgerLock.lock()
        defer { adversarialLedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let recordId = UUID()
        ledger.recordOperation(OperationRecord(
            id: recordId,
            actionType: .moveToTrash,
            sourcePath: file.path,
            destinationPath: trash.path,
            fileSize: 16,
            reason: "Idempotency test"
        ))

        // First batch call succeeds with 1
        let firstRun = try ledger.rollbackAll(recordIds: [recordId])
        #expect(firstRun == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))

        // Second batch call with the same IDs must return 0 without error or re-executing
        let secondRun = try ledger.rollbackAll(recordIds: [recordId])
        #expect(secondRun == 0)

        // Empty IDs return 0
        let emptyRun = try ledger.rollbackAll(recordIds: [])
        #expect(emptyRun == 0)

        // Single rollback on already rolled back record must throw
        #expect(throws: Error.self) {
            try ledger.rollback(recordId: recordId)
        }
    }

    // MARK: - Challenge 3: Empty Folder Consolidation & Hierarchy Restoration

    @Test("Adversarial: Moving empty directory to Trash and rolling it back restores directory hierarchy without data corruption")
    func testEmptyFolderConsolidationAndRestoration() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        // Setup: Nested folder structure
        // ParentFolder/
        //   SubFolderA/ (has fileA.txt)
        //   SubFolderB/ (destination for consolidation)
        let subFolderA = try sandbox.createFolder(at: "ParentFolder/SubFolderA")
        let subFolderB = try sandbox.createFolder(at: "ParentFolder/SubFolderB")

        let fileAContent = Data("Nested file content inside SubFolderA".utf8)
        let fileA = try sandbox.createFile(at: "ParentFolder/SubFolderA/fileA.txt", content: fileAContent)

        // Execute consolidation from SubFolderA into SubFolderB
        let proposal = FolderMergeProposal(
            sourceURL: subFolderA,
            destinationURL: subFolderB,
            itemCount: 1,
            totalSize: Int64(fileAContent.count),
            reason: "Consolidation adversarial test"
        )

        adversarialLedgerLock.lock()
        defer { adversarialLedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let historyBeforeCount = ledger.loadHistory().count

        try FileOrganizer.shared.executeFolderMerges([proposal])

        // Verification after consolidation:
        // 1. fileA is now in SubFolderB
        let movedFileA = subFolderB.appendingPathComponent("fileA.txt")
        #expect(FileManager.default.fileExists(atPath: movedFileA.path))
        let movedContent = try Data(contentsOf: movedFileA)
        #expect(movedContent == fileAContent)

        // 2. SubFolderA was emptied and safely moved to Trash (NOT deleted permanently via removeItem)
        #expect(!FileManager.default.fileExists(atPath: subFolderA.path))

        // 3. Find the ledger records created by executeFolderMerges
        let historyAfter = ledger.loadHistory()
        let newRecords = historyAfter.filter { $0.sourcePath.contains(sandbox.rootURL.lastPathComponent) }
        #expect(newRecords.count == 2)
        let dirTrashRecord = newRecords.first(where: {
            $0.actionType == .moveToTrash && $0.sourcePath.hasSuffix("ParentFolder/SubFolderA")
        })
        let fileMoveRecord = newRecords.first(where: {
            $0.actionType == .moveFile && $0.sourcePath.hasSuffix("ParentFolder/SubFolderA/fileA.txt")
        })

        #expect(dirTrashRecord != nil)
        #expect(dirTrashRecord?.destinationPath != nil)
        #expect(fileMoveRecord != nil)

        guard let dirRecord = dirTrashRecord, let fileRecord = fileMoveRecord else {
            Issue.record("Missing required operation records for folder consolidation")
            return
        }

        // Step 4: Adversarially rollback both operations using batch rollbackAll
        let batchCount = try ledger.rollbackAll(recordIds: [dirRecord.id, fileRecord.id])
        #expect(batchCount == 2)

        // Step 5: Verify directory hierarchy is fully restored
        #expect(FileManager.default.fileExists(atPath: subFolderA.path))
        #expect(FileManager.default.fileExists(atPath: fileA.path))
        #expect(!FileManager.default.fileExists(atPath: movedFileA.path))

        // Verify data integrity of the restored file
        let restoredData = try Data(contentsOf: fileA)
        #expect(restoredData == fileAContent)
    }

    @Test("Adversarial: Directory rollback collision when new folder exists at original path")
    func testDirectoryRollbackCollision() throws {
        let sandbox = try AdversarialSandbox()
        defer { sandbox.cleanup() }

        let dir = try sandbox.createFolder(at: "ProjectAssets")
        let trashDir = try SecurityGuard.shared.safelyMoveToTrash(at: dir)

        adversarialLedgerLock.lock()
        defer { adversarialLedgerLock.unlock() }

        let ledger = RollbackLedger.shared
        let recordId = UUID()
        ledger.recordOperation(OperationRecord(
            id: recordId,
            actionType: .moveToTrash,
            sourcePath: dir.path,
            destinationPath: trashDir.path,
            fileSize: 0,
            reason: "Dir collision test"
        ))

        // Create a new folder at the original path before rollback
        let newDir = try sandbox.createFolder(at: "ProjectAssets")
        _ = try sandbox.createFile(at: "ProjectAssets/new_file.txt", content: Data("new".utf8))

        // Trigger rollback
        let restoredDirURL = try ledger.rollback(recordId: recordId)

        // Restored directory must be named ProjectAssets (Restored) without overwriting ProjectAssets
        #expect(restoredDirURL.lastPathComponent == "ProjectAssets (Restored)")
        #expect(FileManager.default.fileExists(atPath: newDir.path))
        #expect(FileManager.default.fileExists(atPath: restoredDirURL.path))
        #expect(FileManager.default.fileExists(atPath: newDir.appendingPathComponent("new_file.txt").path))

        // Clean up
        try? FileManager.default.removeItem(at: restoredDirURL)
    }
}
