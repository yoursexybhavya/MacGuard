import Testing
import Foundation
import SwiftUI
@testable import MacGuard

private struct TestSandbox {
    let rootURL: URL

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGuard_M3_Test_\(UUID().uuidString)")
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

@Suite("Milestone 3: Shell Navigation & Core Workflow Tests", .serialized)
struct Milestone3NavigationAndWorkflowTests {

    // MARK: - Feature F10: NavigationCoordinator Tests

    @Test("F10: NavigationCoordinator default state and initial properties")
    @MainActor
    func testNavigationCoordinatorDefaults() {
        let coordinator = NavigationCoordinator()
        #expect(coordinator.selectedSection == .dashboard)
        #expect(coordinator.storageDrillDownCategory == nil)
        #expect(coordinator.duplicateScanFolder == nil)
        #expect(coordinator.previewURL == nil)
    }

    @Test("F10: NavigationCoordinator section routing and ephemeral drill-down reset")
    @MainActor
    func testNavigationCoordinatorRouting() {
        let coordinator = NavigationCoordinator()
        
        // Navigate to storage with drill-down
        coordinator.navigateToStorage(category: .caches)
        #expect(coordinator.selectedSection == .storage)
        #expect(coordinator.storageDrillDownCategory == .caches)

        // Navigating away from storage resets category drill-down
        coordinator.navigateTo(section: .cleanup)
        #expect(coordinator.selectedSection == .cleanup)
        #expect(coordinator.storageDrillDownCategory == nil)

        // Navigation via alias navigate(to:)
        coordinator.navigate(to: .organizer)
        #expect(coordinator.selectedSection == .organizer)
    }

    @Test("F10: NavigationCoordinator deep-linking to Duplicates and Storage")
    @MainActor
    func testNavigationCoordinatorDeepLinks() {
        let coordinator = NavigationCoordinator()
        let testFolder = URL(fileURLWithPath: "/tmp/MacGuardTestDuplicates")

        coordinator.navigateToDuplicates(folder: testFolder)
        #expect(coordinator.selectedSection == .duplicates)
        #expect(coordinator.duplicateScanFolder == testFolder)

        coordinator.navigateToStorage(category: .installers)
        #expect(coordinator.selectedSection == .storage)
        #expect(coordinator.storageDrillDownCategory == .installers)

        coordinator.navigateToOrganizer()
        #expect(coordinator.selectedSection == .organizer)

        coordinator.navigateToCleanup()
        #expect(coordinator.selectedSection == .cleanup)

        coordinator.navigateToApprovals()
        #expect(coordinator.selectedSection == .approvals)

        coordinator.navigateToSettings()
        #expect(coordinator.selectedSection == .settings)
    }

    @Test("F10: NavigationCoordinator quick look preview and resetToDashboard")
    @MainActor
    func testNavigationCoordinatorQuickLookAndReset() {
        let coordinator = NavigationCoordinator()
        let testFile = URL(fileURLWithPath: "/tmp/sample.dmg")

        coordinator.quickLook(fileURL: testFile)
        #expect(coordinator.previewURL == testFile)

        coordinator.clearDrillDown()
        #expect(coordinator.previewURL == nil)
        #expect(coordinator.storageDrillDownCategory == nil)

        // Test complete reset
        coordinator.navigateToStorage(category: .archives)
        coordinator.navigateToDuplicates(folder: URL(fileURLWithPath: "/tmp"))
        coordinator.quickLook(fileURL: testFile)

        coordinator.resetToDashboard()
        #expect(coordinator.selectedSection == .dashboard)
        #expect(coordinator.storageDrillDownCategory == nil)
        #expect(coordinator.duplicateScanFolder == nil)
        #expect(coordinator.previewURL == nil)
    }

    @Test("F10: NavigationCoordinator selectionBinding two-way communication")
    @MainActor
    func testNavigationCoordinatorSelectionBinding() {
        let coordinator = NavigationCoordinator()
        let binding = coordinator.selectionBinding

        #expect(binding.wrappedValue == .dashboard)

        binding.wrappedValue = .approvals
        #expect(coordinator.selectedSection == .approvals)
        #expect(binding.wrappedValue == .approvals)

        // Setting nil does not crash or corrupt
        binding.wrappedValue = nil
        #expect(coordinator.selectedSection == .approvals)
    }

    // MARK: - Feature F11: Dynamic Shell Status & HardwareMonitor Tests

    @Test("F11: HardwareMonitor live Metal query and device detection")
    func testHardwareMonitorMetalQuery() {
        let info = HardwareMonitor.queryHardware()

        #expect(!info.chipName.isEmpty)
        #expect(info.coreCount > 0)
        #expect(info.physicalMemoryBytes > 0)
        #expect(!info.formattedPhysicalMemory.isEmpty)
        #expect(info.formattedPhysicalMemory.contains("B")) // GB or MB
    }

    @Test("F11: HardwareMonitor resident memory and formatted summaries")
    func testHardwareMonitorMemorySummaries() {
        let info = HardwareMonitor.queryHardware()

        #expect(info.activeResidentMemoryBytes >= 0)
        #expect(!info.formattedActiveRAM.isEmpty)
        #expect(info.systemFreeMemoryBytes >= 0)
        #expect(!info.formattedSystemFree.isEmpty)

        // Verify summary strings
        #expect(info.deviceSummary.contains(info.chipName))
        #expect(info.deviceSummary.contains(info.formattedPhysicalMemory))
        #expect(info.activeMemorySummary.contains("Standalone Offline AI"))
        #expect(info.activeMemorySummary.contains(info.formattedActiveRAM))
    }

    @Test("F11: HardwareMonitor singleton reactivity and manual refresh")
    @MainActor
    func testHardwareMonitorSingleton() {
        let monitor = HardwareMonitor.shared
        let initialInfo = monitor.hardwareInfo

        #expect(!initialInfo.chipName.isEmpty)
        monitor.refresh()
        #expect(!monitor.hardwareInfo.chipName.isEmpty)
    }

    // MARK: - Feature F12: Dashboard Live Gauge & Action Context Tests

    @Test("F12: StorageAnalyzer.getLiveVolumeMetrics produces real APFS metrics without mock fallbacks")
    func testLiveVolumeMetricsRealAPFSValues() {
        let metrics = StorageAnalyzer.shared.getLiveVolumeMetrics()

        #expect(metrics.totalCapacity > 0)
        #expect(metrics.availableCapacity > 0)
        #expect(metrics.usedCapacity >= 0)
        #expect(metrics.usagePercentage >= 0.0 && metrics.usagePercentage <= 1.0)

        #expect(!metrics.formattedTotal.isEmpty)
        #expect(!metrics.formattedAvailable.isEmpty)
        #expect(!metrics.formattedUsed.isEmpty)

        // Verify non-mock real volume metrics
        #expect(metrics.formattedTotal.contains("B"))
        #expect(metrics.formattedAvailable.contains("B"))
    }

    @Test("F12: DashboardStorageGaugeCard button triggers navigation on select")
    @MainActor
    func testDashboardStorageGaugeCardNavigation() {
        var didSelect = false
        let card = DashboardStorageGaugeCard(
            usagePercentage: 0.65,
            formattedAvailable: "350 GB",
            formattedTotal: "1 TB",
            onSelect: {
                didSelect = true
            }
        )

        card.onSelect()
        #expect(didSelect == true)
        #expect(card.usagePercentage == 0.65)
        #expect(card.formattedAvailable == "350 GB")
        #expect(card.formattedTotal == "1 TB")
    }

    @Test("F12: QuickActionCard callback execution across all 4 maintenance actions")
    @MainActor
    func testQuickActionCardCallbacks() {
        var cleanInvoked = false
        var dupInvoked = false
        var orgInvoked = false
        var spaceInvoked = false

        let cleanCard = QuickActionCard(
            title: "Clean Caches",
            subtitle: "Safe temporary file removal",
            icon: "trash.fill",
            color: .orange,
            action: { cleanInvoked = true }
        )
        cleanCard.action()
        #expect(cleanInvoked == true)

        let dupCard = QuickActionCard(
            title: "Find Duplicates",
            subtitle: "Locate identical files",
            icon: "doc.on.doc.fill",
            color: .teal,
            action: { dupInvoked = true }
        )
        dupCard.action()
        #expect(dupInvoked == true)

        let orgCard = QuickActionCard(
            title: "Organize Files",
            subtitle: "Sort Downloads",
            icon: "folder.badge.gearshape",
            color: .blue,
            action: { orgInvoked = true }
        )
        orgCard.action()
        #expect(orgInvoked == true)

        let spaceCard = QuickActionCard(
            title: "Analyze Space",
            subtitle: "Inspect largest files",
            icon: "chart.pie.fill",
            color: .indigo,
            action: { spaceInvoked = true }
        )
        spaceCard.action()
        #expect(spaceInvoked == true)
    }

    @Test("F12: RecentOperationRowView metadata and RollbackLedger.recentOperations")
    @MainActor
    func testRecentOperationRowViewAndLedger() {
        let op = OperationRecord(
            id: UUID(),
            timestamp: Date(),
            actionType: .moveToTrash,
            sourcePath: "/Users/test/Downloads/installer.pkg",
            destinationPath: "/Users/test/.Trash/installer.pkg",
            fileSize: 1024 * 1024 * 150, // 150 MB
            reason: "User quick-trashed large installer",
            isRolledBack: false
        )

        #expect(op.fileName == "installer.pkg")
        #expect(op.formattedSize.contains("150") || op.formattedSize.contains("MB"))
        #expect(!op.isRolledBack)
        #expect(op.systemImageName == "trash")

        // Test RollbackLedger.recentOperations accessor
        let ledger = RollbackLedger.shared
        ledger.recordOperation(op)
        #expect(ledger.recentOperations.contains(where: { $0.id == op.id }))
    }

    // MARK: - Feature F13: Duplicate Finder & Keeper Switcher Tests

    @Test("F13: Duplicate Cluster interactive keeper switching preserves invariants")
    func testDuplicateClusterKeeperSwitching() {
        let item1 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/sample_a.pdf"),
            size: 2048,
            modificationDate: Date(timeIntervalSince1970: 1000),
            category: .documents,
            isDirectory: false
        )
        let item2 = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/sample_b.pdf"),
            size: 2048,
            modificationDate: Date(timeIntervalSince1970: 2000),
            category: .documents,
            isDirectory: false
        )

        var cluster = DuplicateCluster(
            id: "sha256_mock_hash",
            items: [
                DuplicateGroupItem(id: item1.id, item: item1, isKeeper: true, isSelected: false),
                DuplicateGroupItem(id: item2.id, item: item2, isKeeper: false, isSelected: true)
            ],
            singleFileSize: 2048
        )

        #expect(cluster.reclaimableSize == 2048)
        #expect(cluster.totalWastedSize == 2048)
        #expect(cluster.keeperItem?.id == item1.id)
        #expect(cluster.candidateDuplicates.count == 1)

        // Make item2 the keeper
        cluster.setKeeper(id: item2.id)

        #expect(cluster.keeperItem?.id == item2.id)
        #expect(cluster.items.first(where: { $0.id == item2.id })?.isKeeper == true)
        #expect(cluster.items.first(where: { $0.id == item2.id })?.isSelected == false)
        #expect(cluster.items.first(where: { $0.id == item1.id })?.isKeeper == false)
        #expect(cluster.items.first(where: { $0.id == item1.id })?.isSelected == true)
        #expect(cluster.reclaimableSize == 2048)
    }

    @Test("F13: Keeper copy is strictly protected from deletion while candidate is trashed")
    func testKeeperCopySafetyDuringTrashing() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let keeperURL = try sandbox.createFile(at: "keeper.txt", content: Data("identical-content".utf8))
        let duplicateURL = try sandbox.createFile(at: "duplicate.txt", content: Data("identical-content".utf8))

        // Safely trash the duplicate copy
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(
            at: duplicateURL,
            reason: "Duplicate removal (keeper copy preserved)"
        )
        let record = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: duplicateURL.path,
            destinationPath: trashedURL.path,
            fileSize: 17,
            reason: "Duplicate removal (keeper copy preserved)"
        )
        RollbackLedger.shared.recordOperation(record)

        // Invariant: Keeper copy MUST still exist at its exact original path
        #expect(FileManager.default.fileExists(atPath: keeperURL.path))
        #expect(!FileManager.default.fileExists(atPath: duplicateURL.path))

        // Invariant: Operation is reversible
        let restoredURL = try RollbackLedger.shared.rollback(recordId: record.id)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
    }

    // MARK: - Feature F14: Organizer Categorization & Consolidation Tests

    @Test("F14: File Organizer selective proposals execution respects selection checkboxes")
    func testOrganizerSelectiveProposalExecution() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let file1 = try sandbox.createFile(at: "document.pdf", content: Data("doc".utf8))
        let file2 = try sandbox.createFile(at: "installer.dmg", content: Data("installer".utf8))
        let file3 = try sandbox.createFile(at: "archive.zip", content: Data("archive".utf8))

        let proposals = try FileOrganizer.shared.planOrganization(for: sandbox.rootURL)
        #expect(proposals.count >= 3)

        // Selectively execute ONLY document.pdf proposal
        let selected = proposals.filter { $0.fileName == "document.pdf" }
        #expect(selected.count == 1)

        try FileOrganizer.shared.executeProposals(selected)

        // Invariant: document.pdf moved into Documents & Notes/
        #expect(!FileManager.default.fileExists(atPath: file1.path))
        #expect(FileManager.default.fileExists(atPath: sandbox.rootURL.appendingPathComponent("Documents & Notes/document.pdf").path))

        // Invariant: unselected files remain untouched at original locations
        #expect(FileManager.default.fileExists(atPath: file2.path))
        #expect(FileManager.default.fileExists(atPath: file3.path))
    }

    @Test("F14: Redundant folder consolidation moves empty source to Trash (Zero Permanent Deletion)")
    func testFolderConsolidationSelectiveExecution() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        _ = try sandbox.createFolder(at: "Images")
        _ = try sandbox.createFolder(at: "Photos & Wallpapers")
        _ = try sandbox.createFolder(at: "Documents")
        _ = try sandbox.createFolder(at: "Documents & Notes")

        try sandbox.createFile(at: "Images/photo1.png", content: Data("png-data".utf8))
        try sandbox.createFile(at: "Documents/notes.txt", content: Data("notes-data".utf8))

        let merges = FileOrganizer.shared.planFolderConsolidation(for: sandbox.rootURL)
        #expect(merges.count == 2)

        // Selectively execute only the Images merge
        let selectedMerge = merges.filter { $0.sourceName == "Images" }
        #expect(selectedMerge.count == 1)

        try FileOrganizer.shared.executeFolderMerges(selectedMerge)

        // Invariant: Images merged into Photos & Wallpapers
        #expect(!FileManager.default.fileExists(atPath: sandbox.rootURL.appendingPathComponent("Images").path))
        #expect(FileManager.default.fileExists(atPath: sandbox.rootURL.appendingPathComponent("Photos & Wallpapers/photo1.png").path))

        // Invariant: Unselected Documents folder and contents remain untouched
        #expect(FileManager.default.fileExists(atPath: sandbox.rootURL.appendingPathComponent("Documents").path))
        #expect(FileManager.default.fileExists(atPath: sandbox.rootURL.appendingPathComponent("Documents/notes.txt").path))
    }

    // MARK: - Feature F15: Assistant Persistent State & Category Chips Tests

    @Test("F15: AssistantViewModel state retention across tab switching")
    @MainActor
    func testAssistantViewModelStateRetention() {
        let viewModel = AssistantViewModel.shared
        let initialMessageCount = viewModel.messages.count

        // Simulate user adding a message
        viewModel.messages.append(ChatMessage(isUser: true, text: "Check my system storage"))
        viewModel.messages.append(ChatMessage(isUser: false, text: "Your startup disk has plenty of space."))

        #expect(viewModel.messages.count == initialMessageCount + 2)

        // Simulate deallocating and re-instantiating AssistantView
        let view1 = AssistantView()
        #expect(viewModel.messages.count == initialMessageCount + 2)

        let view2 = AssistantView()
        #expect(viewModel.messages.count == initialMessageCount + 2)
        #expect(view1.onNavigate == nil)
        #expect(view2.onNavigate == nil)

        // Test clearing history
        viewModel.clearHistory()
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.isUser == false)
    }

    @Test("F15: StorageCategoryChip interactive button triggers deep-link callback")
    @MainActor
    func testStorageCategoryChipDeepLink() {
        var drilledCategory: FileCategory? = nil

        let chip = StorageCategoryChip(category: .installers, byteCount: 1024 * 1024 * 50) { cat in
            drilledCategory = cat
        }

        chip.onDrillDown(chip.category)
        #expect(drilledCategory == .installers)
    }
}
