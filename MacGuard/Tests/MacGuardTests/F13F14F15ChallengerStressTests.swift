import Foundation
import Testing
import SwiftUI
@testable import MacGuard

// MARK: - Test Sandbox Helper

private struct M3ChallengerSandbox {
    let rootURL: URL

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGuard_M3_Challenger_\(UUID().uuidString)")
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

// MARK: - Suite: Feature F13, F14, F15 Challenger: Empirical Stress & Hardening Tests

@Suite("Feature F13, F14, F15 Challenger: Empirical Stress & Hardening Tests", .serialized)
struct F13F14F15ChallengerStressTests {

    // =========================================================================
    // SECTION 1: Feature F13 - Duplicate Finder Keeper Switching & Safe Trashing
    // =========================================================================

    @Test("F13: Single-item cluster keeper switching retains keeper invariant")
    func testKeeperSwitchingSingleItem() {
        let item = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/single.pdf"),
            size: 1024,
            modificationDate: Date(),
            category: .documents,
            isDirectory: false
        )

        var cluster = DuplicateCluster(
            id: "single_hash",
            items: [
                DuplicateGroupItem(id: item.id, item: item, isKeeper: true, isSelected: false)
            ],
            singleFileSize: 1024
        )

        #expect(cluster.items.count == 1)
        #expect(cluster.items[0].isKeeper == true)
        #expect(cluster.items[0].isSelected == false)
        #expect(cluster.reclaimableSize == 0)
        #expect(cluster.totalWastedSize == 0)
        #expect(cluster.candidateDuplicates.isEmpty)
        #expect(cluster.keeperItem?.id == item.id)

        // Switching keeper to itself
        cluster.setKeeper(id: item.id)
        #expect(cluster.items[0].isKeeper == true)
        #expect(cluster.items[0].isSelected == false)
        #expect(cluster.reclaimableSize == 0)
    }

    @Test("F13: Two-item cluster alternating keeper switching preserves invariants")
    func testKeeperSwitchingTwoItems() {
        let item1 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/copy1.pdf"),
            size: 2048,
            modificationDate: Date(timeIntervalSince1970: 100),
            category: .documents,
            isDirectory: false
        )
        let item2 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/copy2.pdf"),
            size: 2048,
            modificationDate: Date(timeIntervalSince1970: 200),
            category: .documents,
            isDirectory: false
        )

        var cluster = DuplicateCluster(
            id: "two_hash",
            items: [
                DuplicateGroupItem(id: item1.id, item: item1, isKeeper: true, isSelected: false),
                DuplicateGroupItem(id: item2.id, item: item2, isKeeper: false, isSelected: true)
            ],
            singleFileSize: 2048
        )

        // Initial state
        #expect(cluster.keeperItem?.id == item1.id)
        #expect(cluster.candidateDuplicates.count == 1)
        #expect(cluster.candidateDuplicates.first?.id == item2.id)
        #expect(cluster.reclaimableSize == 2048)

        // Switch to item2
        cluster.setKeeper(id: item2.id)
        #expect(cluster.keeperItem?.id == item2.id)
        #expect(cluster.items.first(where: { $0.id == item2.id })?.isKeeper == true)
        #expect(cluster.items.first(where: { $0.id == item2.id })?.isSelected == false)
        #expect(cluster.items.first(where: { $0.id == item1.id })?.isKeeper == false)
        #expect(cluster.items.first(where: { $0.id == item1.id })?.isSelected == true)
        #expect(cluster.candidateDuplicates.count == 1)
        #expect(cluster.candidateDuplicates.first?.id == item1.id)
        #expect(cluster.reclaimableSize == 2048)

        // Switch back to item1
        cluster.setKeeper(id: item1.id)
        #expect(cluster.keeperItem?.id == item1.id)
        #expect(cluster.items.first(where: { $0.id == item1.id })?.isKeeper == true)
        #expect(cluster.items.first(where: { $0.id == item1.id })?.isSelected == false)
        #expect(cluster.items.first(where: { $0.id == item2.id })?.isKeeper == false)
        #expect(cluster.items.first(where: { $0.id == item2.id })?.isSelected == true)
    }

    @Test("F13: Ten-item cluster iterative keeper switching across all positions")
    func testKeeperSwitchingTenItems() {
        let count = 10
        let singleSize: Int64 = 4096
        var groupItems: [DuplicateGroupItem] = []

        for i in 0..<count {
            let item = ScannedItem(
                url: URL(fileURLWithPath: "/tmp/cluster_file_\(i).dat"),
                size: singleSize,
                modificationDate: Date(timeIntervalSince1970: Double(i * 100)),
                category: .other,
                isDirectory: false
            )
            groupItems.append(DuplicateGroupItem(
                id: item.id,
                item: item,
                isKeeper: i == 0,
                isSelected: i != 0
            ))
        }

        var cluster = DuplicateCluster(
            id: "ten_hash",
            items: groupItems,
            singleFileSize: singleSize
        )

        // Sequentially rotate keeper through all 10 items
        for targetIndex in 0..<count {
            let targetId = groupItems[targetIndex].id
            cluster.setKeeper(id: targetId)

            // Invariant 1: Exactly one item has isKeeper == true
            let keeperCount = cluster.items.filter { $0.isKeeper }.count
            #expect(keeperCount == 1, "Exactly one keeper must exist at all times (targetIndex: \(targetIndex))")

            // Invariant 2: Designated item is the keeper and is NOT selected
            let currentKeeper = cluster.items.first { $0.isKeeper }
            #expect(currentKeeper?.id == targetId)
            #expect(currentKeeper?.isSelected == false)

            // Invariant 3: All other 9 items have isKeeper == false and isSelected == true
            let nonKeepers = cluster.items.filter { !$0.isKeeper }
            #expect(nonKeepers.count == count - 1)
            for nonKeeper in nonKeepers {
                #expect(nonKeeper.isSelected == true, "Non-keeper \(nonKeeper.id) should be selected for removal")
            }

            // Invariant 4: Candidate duplicates count equals count - 1
            #expect(cluster.candidateDuplicates.count == count - 1)

            // Invariant 5: Reclaimable size equals (count - 1) * singleFileSize
            #expect(cluster.reclaimableSize == Int64(count - 1) * singleSize)
            #expect(cluster.totalWastedSize == Int64(count - 1) * singleSize)
        }
    }

    @Test("F13: Non-existent keeper ID does not corrupt cluster keeper state")
    func testNonExistentKeeperID() {
        let item1 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/valid1.txt"),
            size: 512,
            modificationDate: Date(),
            category: .documents,
            isDirectory: false
        )
        let item2 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/valid2.txt"),
            size: 512,
            modificationDate: Date(),
            category: .documents,
            isDirectory: false
        )

        var cluster = DuplicateCluster(
            id: "guard_test_hash",
            items: [
                DuplicateGroupItem(id: item1.id, item: item1, isKeeper: true, isSelected: false),
                DuplicateGroupItem(id: item2.id, item: item2, isKeeper: false, isSelected: true)
            ],
            singleFileSize: 512
        )

        let initialKeeper = cluster.keeperItem
        #expect(initialKeeper?.id == item1.id)

        // Attempt designating a non-existent ID
        cluster.setKeeper(id: "non-existent-guid-9999")

        // Strict invariant: Does cluster still have a valid keeper item?
        #expect(cluster.keeperItem != nil)
        #expect(cluster.items.filter { $0.isKeeper }.count == 1, "Cluster items must retain exactly 1 keeper when given an invalid ID")
        #expect(cluster.items.first(where: { $0.id == item1.id })?.isKeeper == true, "Original keeper must remain keeper when invalid ID is requested")
    }

    @Test("F13 Blast Radius: Non-existent keeper ID does NOT mark keeper for deletion")
    func testNonExistentKeeperIdBlastRadius() {
        let item1 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/sample1.txt"),
            size: 1024,
            modificationDate: Date(),
            category: .documents,
            isDirectory: false
        )
        let item2 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/sample2.txt"),
            size: 1024,
            modificationDate: Date(),
            category: .documents,
            isDirectory: false
        )

        var cluster = DuplicateCluster(
            id: "blast_radius_hash",
            items: [
                DuplicateGroupItem(id: item1.id, item: item1, isKeeper: true, isSelected: false),
                DuplicateGroupItem(id: item2.id, item: item2, isKeeper: false, isSelected: true)
            ],
            singleFileSize: 1024
        )

        // Prior to call, exactly 1 candidate duplicate is selected for trashing
        #expect(cluster.items.filter { $0.isSelected && !$0.isKeeper }.count == 1)

        cluster.setKeeper(id: "invalid_id")

        // Blast Radius Prevention: With the guard in place, non-existent keeper ID does not corrupt cluster state.
        // Only candidate duplicate copies remain selected; the designated keeper is strictly preserved.
        let trashingTargets = cluster.items.filter { $0.isSelected && !$0.isKeeper }
        #expect(trashingTargets.count == 1, "Only candidate duplicate is marked for deletion")
        #expect(!trashingTargets.contains(where: { $0.id == item1.id }), "Keeper copy is never marked for deletion")
    }

    @Test("F13 & R3: Real batch trashing of duplicate candidates preserves keeper untouched with full rollback")
    func testRealBatchTrashingDuplicateCandidatesWithRollback() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        let content = Data("identical-cryptographic-content-for-duplicates".utf8)
        let keeperFile = try sandbox.createFile(at: "Originals/primary_document.txt", content: content)
        let dupFile1 = try sandbox.createFile(at: "Downloads/duplicate_copy_1.txt", content: content)
        let dupFile2 = try sandbox.createFile(at: "Desktop/duplicate_copy_2.txt", content: content)
        let dupFile3 = try sandbox.createFile(at: "Temp/duplicate_copy_3.txt", content: content)

        let candidateFiles = [dupFile1, dupFile2, dupFile3]
        var trashedRecords: [OperationRecord] = []

        // Safely move all 3 duplicate candidates to Trash via SecurityGuard
        for candidate in candidateFiles {
            let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(
                at: candidate,
                reason: "Batch duplicate elimination"
            )
            let record = OperationRecord(
                actionType: .moveToTrash,
                sourcePath: candidate.path,
                destinationPath: trashedURL.path,
                fileSize: Int64(content.count),
                reason: "Batch duplicate elimination"
            )
            RollbackLedger.shared.recordOperation(record)
            trashedRecords.append(record)
        }

        // Invariant 1: The original keeper file MUST remain untouched at its exact location
        #expect(FileManager.default.fileExists(atPath: keeperFile.path))
        let remainingContent = try Data(contentsOf: keeperFile)
        #expect(remainingContent == content)

        // Invariant 2: All 3 candidate duplicates must be removed from their original paths
        for candidate in candidateFiles {
            #expect(!FileManager.default.fileExists(atPath: candidate.path))
        }

        // Invariant 3: Rollback all candidate trashing operations restores all files
        let restoredCount = try RollbackLedger.shared.rollbackAll(recordIds: trashedRecords.map(\.id))
        #expect(restoredCount == candidateFiles.count)

        for candidate in candidateFiles {
            #expect(FileManager.default.fileExists(atPath: candidate.path))
            let restoredData = try Data(contentsOf: candidate)
            #expect(restoredData == content)
        }
    }

    // =========================================================================
    // SECTION 2: Feature F14 - Organizer Checkboxes & Folder Consolidation
    // =========================================================================

    @Test("F14: Selective proposal execution moves only selected items while unselected remain untouched")
    func testSelectiveProposalExecution() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        let file1 = try sandbox.createFile(at: "manual.pdf", content: Data("manual".utf8))
        let file2 = try sandbox.createFile(at: "installer.dmg", content: Data("installer".utf8))
        let file3 = try sandbox.createFile(at: "archive.tar.gz", content: Data("archive".utf8))
        let file4 = try sandbox.createFile(at: "photo.jpg", content: Data("photo".utf8))
        let file5 = try sandbox.createFile(at: "script.py", content: Data("code".utf8))

        let proposals = try FileOrganizer.shared.planOrganization(for: sandbox.rootURL)
        #expect(proposals.count >= 5)

        // Selectively choose ONLY file1 (.pdf) and file3 (.tar.gz)
        let selectedProposals = proposals.filter {
            $0.fileName == "manual.pdf" || $0.fileName == "archive.tar.gz"
        }
        #expect(selectedProposals.count == 2)

        try FileOrganizer.shared.executeProposals(selectedProposals)

        // Invariant 1: Selected files are moved to their respective organized directories
        #expect(!FileManager.default.fileExists(atPath: file1.path))
        #expect(!FileManager.default.fileExists(atPath: file3.path))

        let expectedDocPath = sandbox.rootURL.appendingPathComponent("Documents & Notes/manual.pdf").path
        let expectedArchivePath = sandbox.rootURL.appendingPathComponent("Archives/archive.tar.gz").path
        #expect(FileManager.default.fileExists(atPath: expectedDocPath))
        #expect(FileManager.default.fileExists(atPath: expectedArchivePath))

        // Invariant 2: Unselected files remain completely untouched at their original paths
        #expect(FileManager.default.fileExists(atPath: file2.path))
        #expect(FileManager.default.fileExists(atPath: file4.path))
        #expect(FileManager.default.fileExists(atPath: file5.path))
    }

    @Test("F14 & R3: Folder consolidation moves files, resolves collisions, and trashes empty source directory")
    func testFolderConsolidationWithCollisionAndEmptyDirTrashing() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        // Create redundant sibling directories: Images and Photos & Wallpapers
        _ = try sandbox.createFolder(at: "Images")
        _ = try sandbox.createFolder(at: "Photos & Wallpapers")

        let photo1 = try sandbox.createFile(at: "Images/unique_photo.png", content: Data("unique-image-content".utf8))
        // Create duplicate filename in both source and destination to test collision handling
        _ = try sandbox.createFile(at: "Photos & Wallpapers/wallpaper.jpg", content: Data("destination-wallpaper".utf8))
        let sourceWallpaper = try sandbox.createFile(at: "Images/wallpaper.jpg", content: Data("source-wallpaper".utf8))

        let merges = FileOrganizer.shared.planFolderConsolidation(for: sandbox.rootURL)
        let imageMerge = merges.first { $0.sourceName == "Images" }
        #expect(imageMerge != nil)

        // Execute merge
        try FileOrganizer.shared.executeFolderMerges([imageMerge!])

        // Invariant 1: unique_photo.png moved into Photos & Wallpapers
        let destPhoto1 = sandbox.rootURL.appendingPathComponent("Photos & Wallpapers/unique_photo.png")
        #expect(FileManager.default.fileExists(atPath: destPhoto1.path))
        #expect(!FileManager.default.fileExists(atPath: photo1.path))

        // Invariant 2: Collision handling: wallpaper.jpg from source renamed to wallpaper (1).jpg
        let destOriginalWallpaper = sandbox.rootURL.appendingPathComponent("Photos & Wallpapers/wallpaper.jpg")
        let destRenamedWallpaper = sandbox.rootURL.appendingPathComponent("Photos & Wallpapers/wallpaper (1).jpg")

        #expect(FileManager.default.fileExists(atPath: destOriginalWallpaper.path))
        #expect(FileManager.default.fileExists(atPath: destRenamedWallpaper.path))
        #expect(!FileManager.default.fileExists(atPath: sourceWallpaper.path))

        let originalContent = try Data(contentsOf: destOriginalWallpaper)
        let renamedContent = try Data(contentsOf: destRenamedWallpaper)
        #expect(originalContent == Data("destination-wallpaper".utf8))
        #expect(renamedContent == Data("source-wallpaper".utf8))

        // Invariant 3: Empty source directory 'Images' is moved to macOS Trash (Zero Permanent Deletion)
        let sourceDir = sandbox.rootURL.appendingPathComponent("Images")
        #expect(!FileManager.default.fileExists(atPath: sourceDir.path), "Empty source folder must be removed from root directory")

        // Verify recent ledger operations recorded the trashing of the empty source folder
        let ledger = RollbackLedger.shared
        let trashedDirRecord = ledger.recentOperations.first {
            $0.actionType == .moveToTrash && $0.sourcePath == sourceDir.path
        }
        #expect(trashedDirRecord != nil, "Trashing empty source directory must be logged in RollbackLedger")
    }

    @Test("F14 & R3: Consolidated folder merge rollback via RollbackLedger")
    func testFolderConsolidationRollback() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "Installers")
        _ = try sandbox.createFolder(at: "Software & Installers")

        let pkg = try sandbox.createFile(at: "Installers/package.pkg", content: Data("package-data".utf8))

        let merges = FileOrganizer.shared.planFolderConsolidation(for: sandbox.rootURL)
        let instMerge = merges.first { $0.sourceName == "Installers" }
        #expect(instMerge != nil)
        try FileOrganizer.shared.executeFolderMerges([instMerge!])

        let sourceDir = sandbox.rootURL.appendingPathComponent("Installers")
        let destPkg = sandbox.rootURL.appendingPathComponent("Software & Installers/package.pkg")
        #expect(FileManager.default.fileExists(atPath: destPkg.path))
        #expect(!FileManager.default.fileExists(atPath: sourceDir.path))

        // Collect new operation IDs executed during this merge for this sandbox
        let newOps = RollbackLedger.shared.recentOperations.filter {
            $0.sourcePath.contains(sandbox.rootURL.lastPathComponent) && !$0.isRolledBack
        }
        #expect(newOps.count >= 2) // Move file + Trash empty folder

        // Rollback all operations in reverse-chronological order
        let rolledBackCount = try RollbackLedger.shared.rollbackAll(recordIds: newOps.map(\.id))
        #expect(rolledBackCount == newOps.count)

        // Invariant: Source directory and file are restored
        #expect(FileManager.default.fileExists(atPath: sourceDir.path))
        #expect(FileManager.default.fileExists(atPath: pkg.path))
        let restoredData = try Data(contentsOf: pkg)
        #expect(restoredData == Data("package-data".utf8))
    }

    @Test("F14: Folder consolidation plans zero merges when directory contains no redundant pairs")
    func testFolderConsolidationNoRedundantFolders() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "MyProject")
        _ = try sandbox.createFolder(at: "RandomFolder")

        let merges = FileOrganizer.shared.planFolderConsolidation(for: sandbox.rootURL)
        #expect(merges.isEmpty, "Directories without known redundant pairs must not formulate any merge proposals")
    }

    // =========================================================================
    // SECTION 3: Feature F15 - Assistant Conversation Persistence & Category Chips
    // =========================================================================

    @Test("F15: AssistantViewModel retains conversation messages across view lifecycle and clearing")
    @MainActor
    func testAssistantConversationPersistence() {
        let viewModel = AssistantViewModel.shared
        viewModel.clearHistory()
        #expect(viewModel.messages.count == 1)

        // Add user and assistant dialogue
        viewModel.messages.append(ChatMessage(isUser: true, text: "Can you help organize my downloads?"))
        viewModel.messages.append(ChatMessage(isUser: false, text: "I found 12 loose files that can be organized."))
        viewModel.messages.append(ChatMessage(isUser: true, text: "Show me duplicate files."))

        #expect(viewModel.messages.count == 4)

        // Simulate creating and tearing down multiple AssistantView instances
        for _ in 0..<5 {
            let view = AssistantView()
            _ = view.body
            // Invariant: Shared viewModel messages must stay intact
            #expect(viewModel.messages.count == 4)
            #expect(viewModel.messages[1].text == "Can you help organize my downloads?")
            #expect(viewModel.messages[2].text == "I found 12 loose files that can be organized.")
            #expect(viewModel.messages[3].text == "Show me duplicate files.")
        }

        // Test clear history resets to initial state
        viewModel.clearHistory()
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.isUser == false)
    }

    @Test("F15: StorageCategoryChip triggers callback for all 12 FileCategory cases")
    @MainActor
    func testStorageCategoryChipAllCategories() {
        let allCategories = FileCategory.allCases
        #expect(allCategories.count == 12)

        for category in allCategories {
            var selectedCategory: FileCategory? = nil
            let testByteCount: Int64 = 1024 * 1024 * 128 // 128 MB

            let chip = StorageCategoryChip(category: category, byteCount: testByteCount) { cat in
                selectedCategory = cat
            }

            #expect(chip.category == category)
            #expect(chip.byteCount == testByteCount)

            // Trigger drill-down callback
            chip.onDrillDown(category)
            #expect(selectedCategory == category)
        }
    }

    @Test("F15 & R3: AssistantViewModel trashSingleFile moves item to Trash and logs in RollbackLedger")
    @MainActor
    func testAssistantViewModelTrashSingleFile() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        let file = try sandbox.createFile(at: "trash_target.tmp", content: Data("temporary-cache-data".utf8))
        let item = ScannedItem(
            url: file,
            size: 20,
            modificationDate: Date(),
            category: .caches,
            isDirectory: false
        )

        let viewModel = AssistantViewModel.shared
        viewModel.trashSingleFile(item)

        // Invariant 1: File is moved out of original path
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // Invariant 2: Notification message confirms safe trashing
        #expect(viewModel.trashedFileNotification != nil)
        #expect(viewModel.trashedFileNotification?.contains("trash_target.tmp") == true)

        // Invariant 3: RollbackLedger logs the operation
        let ledger = RollbackLedger.shared
        let record = ledger.recentOperations.first { $0.sourcePath == file.path && $0.actionType == .moveToTrash }
        #expect(record != nil)

        // Invariant 4: Rollback restores the file
        let restoredURL = try ledger.rollback(recordId: record!.id)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
    }

    // =========================================================================
    // SECTION 4: Additional Challenger Stress & Boundary Tests
    // =========================================================================

    @Test("F13: Empty, whitespace, and non-existent keeper IDs do not mutate cluster state")
    func testKeeperSwitchingNonExistentId() {
        let item1 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/sample_keeper.txt"),
            size: 1024,
            modificationDate: Date(),
            category: .documents,
            isDirectory: false
        )
        let item2 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/sample_dup.txt"),
            size: 1024,
            modificationDate: Date(),
            category: .documents,
            isDirectory: false
        )

        var cluster = DuplicateCluster(
            id: "boundary_keeper_hash",
            items: [
                DuplicateGroupItem(id: item1.id, item: item1, isKeeper: true, isSelected: false),
                DuplicateGroupItem(id: item2.id, item: item2, isKeeper: false, isSelected: true)
            ],
            singleFileSize: 1024
        )

        let testIds = ["", "   ", "\t\n", "non-existent-guid-9999", "UUID-DOES-NOT-EXIST"]
        for badId in testIds {
            cluster.setKeeper(id: badId)
            #expect(cluster.items.filter { $0.isKeeper }.count == 1, "Must retain exactly 1 keeper on invalid id: '\(badId)'")
            #expect(cluster.items.first(where: { $0.id == item1.id })?.isKeeper == true, "Original keeper must remain keeper")
            #expect(cluster.items.first(where: { $0.id == item1.id })?.isSelected == false, "Keeper must not be selected")
            #expect(cluster.items.first(where: { $0.id == item2.id })?.isKeeper == false, "Duplicate copy must not be keeper")
            #expect(cluster.items.first(where: { $0.id == item2.id })?.isSelected == true, "Duplicate copy must remain selected")
            #expect(cluster.reclaimableSize == 1024)
        }
    }

    @Test("F13: 100 alternating keeper switches maintain exact invariant integrity")
    func testKeeperRapidAlternatingSwitching() {
        let item1 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/alt1.txt"),
            size: 2048,
            modificationDate: Date(),
            category: .code,
            isDirectory: false
        )
        let item2 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/alt2.txt"),
            size: 2048,
            modificationDate: Date(),
            category: .code,
            isDirectory: false
        )

        var cluster = DuplicateCluster(
            id: "alternating_hash",
            items: [
                DuplicateGroupItem(id: item1.id, item: item1, isKeeper: true, isSelected: false),
                DuplicateGroupItem(id: item2.id, item: item2, isKeeper: false, isSelected: true)
            ],
            singleFileSize: 2048
        )

        for step in 1...100 {
            let targetId = (step % 2 == 1) ? item2.id : item1.id
            cluster.setKeeper(id: targetId)

            let keepers = cluster.items.filter { $0.isKeeper }
            #expect(keepers.count == 1, "Must have exactly 1 keeper at step \(step)")
            #expect(keepers.first?.id == targetId, "Keeper ID must match target at step \(step)")
            #expect(keepers.first?.isSelected == false, "Keeper must not be selected at step \(step)")

            let nonKeepers = cluster.items.filter { !$0.isKeeper }
            #expect(nonKeepers.count == 1, "Must have exactly 1 duplicate candidate at step \(step)")
            #expect(nonKeepers.first?.isSelected == true, "Duplicate candidate must be selected at step \(step)")
            #expect(cluster.reclaimableSize == 2048)
            #expect(cluster.totalWastedSize == 2048)
        }
    }

    @Test("F14: Folder consolidation prevents self-merges without corruption")
    func testFolderConsolidationSelfMergePrevention() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "SameFolder")
        let file = try sandbox.createFile(at: "SameFolder/file.txt", content: Data("stay-safe".utf8))

        let selfMerge = FolderMergeProposal(
            sourceURL: sandbox.fileURL("SameFolder"),
            destinationURL: sandbox.fileURL("SameFolder"),
            itemCount: 1,
            totalSize: 9,
            reason: "Self merge test"
        )

        // Execute self-merge: must be gracefully skipped
        try FileOrganizer.shared.executeFolderMerges([selfMerge])

        // File and directory must remain intact
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: sandbox.fileURL("SameFolder").path))
        let content = try Data(contentsOf: file)
        #expect(content == Data("stay-safe".utf8))
    }

    @Test("F14: Folder consolidation prevents circular descendant merges")
    func testFolderConsolidationCircularDescendantPrevention() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "ParentFolder")
        _ = try sandbox.createFolder(at: "ParentFolder/SubChild")
        let file = try sandbox.createFile(at: "ParentFolder/root_file.txt", content: Data("root-content".utf8))

        let circularMerge = FolderMergeProposal(
            sourceURL: sandbox.fileURL("ParentFolder"),
            destinationURL: sandbox.fileURL("ParentFolder/SubChild"),
            itemCount: 1,
            totalSize: 12,
            reason: "Circular merge test"
        )

        // Execute circular merge: must be safely skipped
        try FileOrganizer.shared.executeFolderMerges([circularMerge])

        // Parent and root file must remain intact
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: sandbox.fileURL("ParentFolder").path))
        let content = try Data(contentsOf: file)
        #expect(content == Data("root-content".utf8))
    }

    @Test("F14: Multi-step collision avoidance correctly numbers sequential collisions: (1), (2), (3)")
    func testFolderConsolidationMultiStepCollisionAvoidance() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "Images")
        _ = try sandbox.createFolder(at: "Photos & Wallpapers")

        // Destination has base, (1), and (2)
        let dest0 = try sandbox.createFile(at: "Photos & Wallpapers/photo.jpg", content: Data("dest-v0".utf8))
        let dest1 = try sandbox.createFile(at: "Photos & Wallpapers/photo (1).jpg", content: Data("dest-v1".utf8))
        let dest2 = try sandbox.createFile(at: "Photos & Wallpapers/photo (2).jpg", content: Data("dest-v2".utf8))

        // Source has the colliding file photo.jpg
        let srcPhoto = try sandbox.createFile(at: "Images/photo.jpg", content: Data("source-incoming-v3".utf8))

        let merges = FileOrganizer.shared.planFolderConsolidation(for: sandbox.rootURL)
        let imageMerge = merges.first { $0.sourceName == "Images" }
        #expect(imageMerge != nil)

        try FileOrganizer.shared.executeFolderMerges([imageMerge!])

        // Verify photo (3).jpg was created
        let expectedDest3 = sandbox.fileURL("Photos & Wallpapers/photo (3).jpg")
        #expect(FileManager.default.fileExists(atPath: expectedDest3.path))

        // All 4 files must retain their exact contents
        #expect(try Data(contentsOf: dest0) == Data("dest-v0".utf8))
        #expect(try Data(contentsOf: dest1) == Data("dest-v1".utf8))
        #expect(try Data(contentsOf: dest2) == Data("dest-v2".utf8))
        #expect(try Data(contentsOf: expectedDest3) == Data("source-incoming-v3".utf8))

        // Source photo removed from source
        #expect(!FileManager.default.fileExists(atPath: srcPhoto.path))
    }

    @Test("F14: Folder consolidation consolidates both subdirectories and files, then safely trashes empty source")
    func testFolderConsolidationSubdirectoryConsolidationAndRollback() throws {
        let sandbox = try M3ChallengerSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "Installers")
        _ = try sandbox.createFolder(at: "Software & Installers")

        // Create a subfolder inside source directory which contains a nested file
        _ = try sandbox.createFolder(at: "Installers/NestedSubdir")
        let nestedFile = try sandbox.createFile(at: "Installers/NestedSubdir/keep.txt", content: Data("keep".utf8))
        let rootPkg = try sandbox.createFile(at: "Installers/tool.pkg", content: Data("tool".utf8))

        let merges = FileOrganizer.shared.planFolderConsolidation(for: sandbox.rootURL)
        let instMerge = merges.first { $0.sourceName == "Installers" }
        #expect(instMerge != nil)

        try FileOrganizer.shared.executeFolderMerges([instMerge!])

        let sourceDir = sandbox.fileURL("Installers")
        let destSubdir = sandbox.fileURL("Software & Installers/NestedSubdir/keep.txt")
        let destPkg = sandbox.fileURL("Software & Installers/tool.pkg")

        // Verify items were consolidated into destination
        #expect(FileManager.default.fileExists(atPath: destSubdir.path))
        #expect(FileManager.default.fileExists(atPath: destPkg.path))
        #expect(try Data(contentsOf: destSubdir) == Data("keep".utf8))
        #expect(try Data(contentsOf: destPkg) == Data("tool".utf8))

        // Empty source folder was safely trashed
        #expect(!FileManager.default.fileExists(atPath: sourceDir.path))

        // Rollback all consolidation operations
        let newOps = RollbackLedger.shared.recentOperations.filter {
            $0.sourcePath.contains(sandbox.rootURL.lastPathComponent) && !$0.isRolledBack
        }
        #expect(newOps.count >= 3) // move pkg, move subdir, trash empty folder

        let rolledBackCount = try RollbackLedger.shared.rollbackAll(recordIds: newOps.map(\.id))
        #expect(rolledBackCount == newOps.count)

        // Verify restoration of source directory, nested folder, and files
        #expect(FileManager.default.fileExists(atPath: sourceDir.path))
        #expect(FileManager.default.fileExists(atPath: nestedFile.path))
        #expect(FileManager.default.fileExists(atPath: rootPkg.path))
        #expect(try Data(contentsOf: nestedFile) == Data("keep".utf8))
        #expect(try Data(contentsOf: rootPkg) == Data("tool".utf8))
    }
}

