import Testing
import Foundation
import SwiftUI
import Metal
@testable import MacGuard

// MARK: - Dedicated Challenger Sandbox

private struct ChallengerM3Sandbox {
    let rootURL: URL

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGuard_ChallengerM3_\(UUID().uuidString)")
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

// MARK: - Challenger Stress Suite

@Suite("Feature F10, F11, F12 Challenger: Empirical Stress & Hardening Tests", .serialized)
struct F10F11F12ChallengerStressTests {

    // =========================================================================
    // MARK: - Feature F10: NavigationCoordinator & Routing Stress Tests
    // =========================================================================

    @Test("F10 Challenger: Programmatic section transitions across all 8 navigation sections")
    @MainActor
    func testAllSectionTransitions() {
        let coordinator = NavigationCoordinator()
        let allSections: [NavigationSection] = [
            .dashboard,
            .assistant,
            .storage,
            .duplicates,
            .organizer,
            .cleanup,
            .approvals,
            .settings
        ]

        #expect(NavigationSection.allCases.count == 8)

        for section in allSections {
            #expect(!section.id.isEmpty)
            #expect(!section.rawValue.isEmpty)
            #expect(!section.icon.isEmpty)

            coordinator.navigateTo(section: section)
            #expect(coordinator.selectedSection == section)
        }

        // Test convenience methods
        coordinator.navigateToOrganizer()
        #expect(coordinator.selectedSection == .organizer)

        coordinator.navigateToCleanup()
        #expect(coordinator.selectedSection == .cleanup)

        coordinator.navigateToApprovals()
        #expect(coordinator.selectedSection == .approvals)

        coordinator.navigateToSettings()
        #expect(coordinator.selectedSection == .settings)

        coordinator.navigate(to: .dashboard)
        #expect(coordinator.selectedSection == .dashboard)
    }

    @Test("F10 Challenger: Rapid tab switching stress maintains navigation invariants")
    @MainActor
    func testRapidTabSwitchingStress() {
        let coordinator = NavigationCoordinator()
        let sections = NavigationSection.allCases

        // Perform 1,000 rapid transitions alternating between sections and storage drill-downs
        for i in 0..<1000 {
            let section = sections[i % sections.count]
            if section == .storage {
                coordinator.navigateToStorage(category: .caches)
                #expect(coordinator.selectedSection == .storage)
                #expect(coordinator.storageDrillDownCategory == .caches)
            } else {
                coordinator.navigateTo(section: section)
                #expect(coordinator.selectedSection == section)
                // Invariant: ephemeral drill-down MUST be cleared when leaving storage
                #expect(coordinator.storageDrillDownCategory == nil)
            }
        }
    }

    @Test("F10 Challenger: Category parameter passing across all 12 storage categories")
    @MainActor
    func testAllTwelveCategoryDrillDowns() {
        let coordinator = NavigationCoordinator()
        let categories = FileCategory.allCases

        #expect(categories.count == 12)

        for category in categories {
            // Drill down into category
            coordinator.navigateToStorage(category: category)
            #expect(coordinator.selectedSection == .storage)
            #expect(coordinator.storageDrillDownCategory == category)

            // Navigating to another section resets drill-down
            coordinator.navigateTo(section: .cleanup)
            #expect(coordinator.selectedSection == .cleanup)
            #expect(coordinator.storageDrillDownCategory == nil)
        }

        // Nil category transitions to Storage root overview
        coordinator.navigateToStorage(category: nil)
        #expect(coordinator.selectedSection == .storage)
        #expect(coordinator.storageDrillDownCategory == nil)
    }

    @Test("F10 Challenger: Duplicate scan folder parameter passing handles complex and boundary URLs")
    @MainActor
    func testDuplicateScanFolderPassing() {
        let coordinator = NavigationCoordinator()

        // Standard directory URL
        let standardURL = URL(fileURLWithPath: "/Users/test/Downloads")
        coordinator.navigateToDuplicates(folder: standardURL)
        #expect(coordinator.selectedSection == .duplicates)
        #expect(coordinator.duplicateScanFolder == standardURL)

        // URL with spaces, emojis, and unicode
        let complexURL = URL(fileURLWithPath: "/tmp/📁 MacGuard Scanner Test/Subfolder #42 [Backup]")
        coordinator.navigateToDuplicates(folder: complexURL)
        #expect(coordinator.selectedSection == .duplicates)
        #expect(coordinator.duplicateScanFolder == complexURL)

        // Root volume URL
        let rootURL = URL(fileURLWithPath: "/")
        coordinator.navigateToDuplicates(folder: rootURL)
        #expect(coordinator.duplicateScanFolder == rootURL)

        // Nil folder preserves default behavior
        coordinator.navigateToDuplicates(folder: nil)
        #expect(coordinator.selectedSection == .duplicates)
        #expect(coordinator.duplicateScanFolder == nil)

        // Reset clears folder
        coordinator.navigateToDuplicates(folder: standardURL)
        coordinator.resetToDashboard()
        #expect(coordinator.duplicateScanFolder == nil)
        #expect(coordinator.selectedSection == .dashboard)
    }

    @Test("F10 Challenger: Quick Look preview binding and ephemeral lifecycle")
    @MainActor
    func testQuickLookPreviewBinding() {
        let coordinator = NavigationCoordinator()
        let testFileURL = URL(fileURLWithPath: "/tmp/sample_contract.pdf")

        // Trigger Quick Look
        coordinator.quickLook(fileURL: testFileURL)
        #expect(coordinator.previewURL == testFileURL)

        // clearDrillDown clears previewURL
        coordinator.clearDrillDown()
        #expect(coordinator.previewURL == nil)

        // Setting a different file
        let secondFileURL = URL(fileURLWithPath: "/tmp/presentation.key")
        coordinator.quickLook(fileURL: secondFileURL)
        #expect(coordinator.previewURL == secondFileURL)

        // resetToDashboard clears preview and drilldown
        coordinator.navigateToStorage(category: .installers)
        coordinator.resetToDashboard()
        #expect(coordinator.previewURL == nil)
        #expect(coordinator.storageDrillDownCategory == nil)
        #expect(coordinator.selectedSection == .dashboard)
    }

    @Test("F10 Challenger: Selection binding two-way communication and nil safety")
    @MainActor
    func testSelectionBindingEdgeCases() {
        let coordinator = NavigationCoordinator()
        let binding = coordinator.selectionBinding

        // Initial binding matches coordinator
        #expect(binding.wrappedValue == .dashboard)

        // Change section via binding
        binding.wrappedValue = .settings
        #expect(coordinator.selectedSection == .settings)
        #expect(binding.wrappedValue == .settings)

        // Assigning nil to binding does NOT crash and preserves previous state
        binding.wrappedValue = nil
        #expect(coordinator.selectedSection == .settings)
        #expect(binding.wrappedValue == .settings)

        // Multiple rapid assignments via binding
        for section in NavigationSection.allCases {
            binding.wrappedValue = section
            #expect(coordinator.selectedSection == section)
        }
    }

    @Test("F10 Challenger: Concurrent asynchronous navigation updates on MainActor")
    func testConcurrentNavigationCoordinatorUpdates() async {
        let coordinator = await NavigationCoordinator.shared

        // Concurrently dispatch 50 navigation updates to MainActor
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await MainActor.run {
                        let section = NavigationSection.allCases[i % NavigationSection.allCases.count]
                        coordinator.navigateTo(section: section)
                        if i % 3 == 0 {
                            coordinator.navigateToStorage(category: .caches)
                        } else if i % 5 == 0 {
                            coordinator.quickLook(fileURL: URL(fileURLWithPath: "/tmp/file_\(i).txt"))
                        }
                    }
                }
            }
        }

        // Verify final state is valid and reachable
        await MainActor.run {
            coordinator.resetToDashboard()
            #expect(coordinator.selectedSection == .dashboard)
            #expect(coordinator.storageDrillDownCategory == nil)
            #expect(coordinator.previewURL == nil)
            #expect(coordinator.duplicateScanFolder == nil)
        }
    }

    // =========================================================================
    // MARK: - Feature F11: HardwareMonitor Stress & Fallback Tests
    // =========================================================================

    @Test("F11 Challenger: Live Metal GPU device query on running system")
    func testLiveMetalQueryProperties() {
        let info = HardwareMonitor.queryHardware()

        // 1. Metal GPU device presence
        #expect(!info.chipName.isEmpty)
        #expect(!info.chipName.trimmingCharacters(in: .whitespaces).isEmpty)

        // 2. Core count and physical memory
        #expect(info.coreCount >= 1)
        #expect(info.physicalMemoryBytes > 0)
        #expect(!info.formattedPhysicalMemory.isEmpty)
        #expect(info.formattedPhysicalMemory.contains("B"))

        // 3. Process resident memory
        #expect(info.activeResidentMemoryBytes >= 0)
        #expect(!info.formattedActiveRAM.isEmpty)

        // 4. System free/inactive memory
        #expect(info.systemFreeMemoryBytes >= 0)
        #expect(!info.formattedSystemFree.isEmpty)

        // 5. Summary strings
        #expect(!info.deviceSummary.isEmpty)
        #expect(!info.activeMemorySummary.isEmpty)
        #expect(info.activeMemorySummary.contains("Standalone Offline AI"))
    }

    @Test("F11 Challenger: High-concurrency Mach kernel and Metal queries stress")
    func testConcurrentHardwareQueriesStress() async {
        // Concurrently execute 50 hardware queries in parallel tasks
        // Tests thread safety of host_statistics64, mach_task_basic_info, and MTLCopyAllDevices
        await withTaskGroup(of: HardwareInfo.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    HardwareMonitor.queryHardware()
                }
            }

            var queryCount = 0
            for await info in group {
                queryCount += 1
                #expect(!info.chipName.isEmpty)
                #expect(info.coreCount >= 1)
                #expect(info.physicalMemoryBytes > 0)
            }
            #expect(queryCount == 50)
        }
    }

    @Test("F11 Challenger: HardwareInfo simulated environments and non-Apple Silicon fallback")
    func testHardwareInfoSimulatedEnvironments() {
        // 1. Simulated Intel Mac (discrete GPU, non-unified memory)
        let intelInfo = HardwareInfo(
            chipName: "Intel Iris Plus Graphics",
            coreCount: 4,
            physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
            formattedPhysicalMemory: "16 GB",
            hasUnifiedMemory: false,
            activeResidentMemoryBytes: 120 * 1024 * 1024,
            formattedActiveRAM: "120 MB",
            systemFreeMemoryBytes: 3 * 1024 * 1024 * 1024,
            formattedSystemFree: "3 GB Free"
        )

        #expect(!intelInfo.hasUnifiedMemory)
        #expect(intelInfo.deviceSummary == "Intel Iris Plus Graphics • 16 GB")
        #expect(!intelInfo.deviceSummary.contains("Unified"))
        #expect(intelInfo.activeMemorySummary == "Standalone Offline AI • 120 MB Active")

        // 2. Simulated Apple Silicon Mac with unified memory
        let appleSiliconInfo = HardwareInfo(
            chipName: "Apple M3 Max",
            coreCount: 16,
            physicalMemoryBytes: 64 * 1024 * 1024 * 1024,
            formattedPhysicalMemory: "64 GB",
            hasUnifiedMemory: true,
            activeResidentMemoryBytes: 250 * 1024 * 1024,
            formattedActiveRAM: "250 MB",
            systemFreeMemoryBytes: 20 * 1024 * 1024 * 1024,
            formattedSystemFree: "20 GB Free"
        )

        #expect(appleSiliconInfo.hasUnifiedMemory)
        #expect(appleSiliconInfo.deviceSummary == "Apple M3 Max • 64 GB Unified")
        #expect(appleSiliconInfo.deviceSummary.contains("Unified"))

        // 3. Fallback empty GPU list simulation
        let fallbackInfo = HardwareInfo(
            chipName: "Apple Silicon",
            coreCount: 8,
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024,
            formattedPhysicalMemory: "8 GB",
            hasUnifiedMemory: true,
            activeResidentMemoryBytes: 0,
            formattedActiveRAM: "0 MB Idle",
            systemFreeMemoryBytes: 0,
            formattedSystemFree: "0 bytes Free"
        )

        #expect(fallbackInfo.chipName == "Apple Silicon")
        #expect(fallbackInfo.formattedActiveRAM == "0 MB Idle")
        #expect(fallbackInfo.activeMemorySummary == "Standalone Offline AI • 0 MB Idle Active")
    }

    @Test("F11 Challenger: RAM query robustness against division by zero and extreme memory values")
    func testRAMQueryRobustnessAndExtremes() {
        // Zero memory values boundary
        let zeroRAMInfo = HardwareInfo(
            chipName: "Virtual Mac",
            coreCount: 1,
            physicalMemoryBytes: 0,
            formattedPhysicalMemory: "0 bytes",
            hasUnifiedMemory: true,
            activeResidentMemoryBytes: 0,
            formattedActiveRAM: "0 MB Idle",
            systemFreeMemoryBytes: 0,
            formattedSystemFree: "0 bytes Free"
        )

        #expect(zeroRAMInfo.physicalMemoryBytes == 0)
        #expect(zeroRAMInfo.activeResidentMemoryBytes == 0)
        #expect(zeroRAMInfo.systemFreeMemoryBytes == 0)
        #expect(!zeroRAMInfo.deviceSummary.isEmpty)
        #expect(!zeroRAMInfo.activeMemorySummary.isEmpty)

        // Extreme memory (e.g. 1.5 TB Mac Pro / Mac Studio)
        let hugeRAMBytes: UInt64 = 1536 * 1024 * 1024 * 1024
        let formattedHuge = ByteCountFormatter.string(fromByteCount: Int64(hugeRAMBytes), countStyle: .memory)
        let hugeRAMInfo = HardwareInfo(
            chipName: "Apple M2 Ultra",
            coreCount: 24,
            physicalMemoryBytes: hugeRAMBytes,
            formattedPhysicalMemory: formattedHuge,
            hasUnifiedMemory: true,
            activeResidentMemoryBytes: 10 * 1024 * 1024 * 1024,
            formattedActiveRAM: "10 GB",
            systemFreeMemoryBytes: 500 * 1024 * 1024 * 1024,
            formattedSystemFree: "500 GB Free"
        )

        #expect(hugeRAMInfo.coreCount == 24)
        #expect(hugeRAMInfo.deviceSummary.contains("Unified"))
        #expect(hugeRAMInfo.deviceSummary.contains("Apple M2 Ultra"))
    }

    @Test("F11 Challenger: HardwareMonitor singleton refresh reactivity")
    @MainActor
    func testHardwareMonitorRefreshReactivity() {
        let monitor = HardwareMonitor.shared
        let initialInfo = monitor.hardwareInfo

        #expect(!initialInfo.chipName.isEmpty)

        // Call refresh 10 times consecutively
        for _ in 0..<10 {
            monitor.refresh()
            #expect(!monitor.hardwareInfo.chipName.isEmpty)
            #expect(monitor.hardwareInfo.coreCount >= 1)
        }
    }

    // =========================================================================
    // MARK: - Feature F12: LiveVolumeMetrics & Dashboard Gauge Stress Tests
    // =========================================================================

    @Test("F12 Challenger: LiveVolumeMetrics boundary conditions — zero total and zero available capacities")
    func testLiveVolumeMetricsZeroBoundary() {
        // Condition: totalCapacity == 0 (must never divide by zero)
        let zeroMetrics = LiveVolumeMetrics(totalCapacity: 0, availableCapacity: 0, usedCapacity: 0)
        #expect(zeroMetrics.usagePercentage == 0.0)
        #expect(!zeroMetrics.formattedTotal.isEmpty)
        #expect(!zeroMetrics.formattedAvailable.isEmpty)
        #expect(!zeroMetrics.formattedUsed.isEmpty)

        // Condition: totalCapacity == 0 but usedCapacity > 0
        let zeroTotalNonzeroUsed = LiveVolumeMetrics(totalCapacity: 0, availableCapacity: 0, usedCapacity: 500)
        #expect(zeroTotalNonzeroUsed.usagePercentage == 0.0)
    }

    @Test("F12 Challenger: LiveVolumeMetrics boundary conditions — available exceeds total (APFS snapshots)")
    func testLiveVolumeMetricsAPFSSnapshotConditions() {
        // In APFS with purgeable snapshots or synthetic volumes, available space can theoretically exceed total
        let snapshotMetrics = LiveVolumeMetrics(
            totalCapacity: 500_000_000_000,
            availableCapacity: 600_000_000_000,
            usedCapacity: 0
        )

        #expect(snapshotMetrics.usagePercentage == 0.0)
        #expect(snapshotMetrics.totalCapacity == 500_000_000_000)
        #expect(snapshotMetrics.availableCapacity == 600_000_000_000)
        #expect(snapshotMetrics.usedCapacity == 0)
    }

    @Test("F12 Challenger: LiveVolumeMetrics boundary conditions — 100% full and over-allocated capacity")
    func testLiveVolumeMetricsFullAndOverAllocated() {
        // Condition 1: Completely full disk (used == total)
        let fullMetrics = LiveVolumeMetrics(
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 0,
            usedCapacity: 1_000_000_000_000
        )
        #expect(fullMetrics.usagePercentage == 1.0)

        // Condition 2: Over-allocated (used > total), must clamp strictly to 1.0
        let overAllocated = LiveVolumeMetrics(
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 0,
            usedCapacity: 1_250_000_000_000
        )
        #expect(overAllocated.usagePercentage == 1.0)
    }

    @Test("F12 Challenger: LiveVolumeMetrics negative values resilience")
    func testLiveVolumeMetricsNegativeValues() {
        // Negative total capacity
        let negativeTotal = LiveVolumeMetrics(
            totalCapacity: -100_000_000_000,
            availableCapacity: 50_000_000_000,
            usedCapacity: 50_000_000_000
        )
        #expect(negativeTotal.usagePercentage == 0.0)

        // Negative used capacity
        let negativeUsed = LiveVolumeMetrics(
            totalCapacity: 500_000_000_000,
            availableCapacity: 500_000_000_000,
            usedCapacity: -50_000_000_000
        )
        #expect(negativeUsed.usagePercentage == 0.0)
    }

    @Test("F12 Challenger: LiveVolumeMetrics extreme large capacities without overflow")
    func testLiveVolumeMetricsExtremeLargeCapacities() {
        let massiveTotal: Int64 = Int64.max - 1000
        let massiveUsed: Int64 = massiveTotal / 2

        let massiveMetrics = LiveVolumeMetrics(
            totalCapacity: massiveTotal,
            availableCapacity: massiveTotal - massiveUsed,
            usedCapacity: massiveUsed
        )

        #expect(massiveMetrics.usagePercentage >= 0.49 && massiveMetrics.usagePercentage <= 0.51)
        #expect(!massiveMetrics.formattedTotal.isEmpty)
        #expect(!massiveMetrics.formattedAvailable.isEmpty)
        #expect(!massiveMetrics.formattedUsed.isEmpty)
    }

    @Test("F12 Challenger: Live system volume metrics query returns valid APFS volume values")
    func testLiveSystemVolumeMetricsRealAPFS() {
        let metrics = StorageAnalyzer.shared.getLiveVolumeMetrics()

        #expect(metrics.totalCapacity > 0)
        #expect(metrics.availableCapacity > 0)
        #expect(metrics.usedCapacity >= 0)
        #expect(metrics.usagePercentage >= 0.0 && metrics.usagePercentage <= 1.0)

        #expect(!metrics.formattedTotal.isEmpty)
        #expect(!metrics.formattedAvailable.isEmpty)
        #expect(!metrics.formattedUsed.isEmpty)
        #expect(metrics.formattedTotal.contains("B"))
    }

    @Test("F12 Challenger: DashboardStorageGaugeCard button and boundary usage percentages")
    @MainActor
    func testDashboardStorageGaugeCardStress() {
        var selectionCount = 0

        // Test normal gauge card
        let normalCard = DashboardStorageGaugeCard(
            usagePercentage: 0.72,
            formattedAvailable: "280 GB",
            formattedTotal: "1 TB",
            onSelect: { selectionCount += 1 }
        )
        normalCard.onSelect()
        #expect(selectionCount == 1)
        #expect(normalCard.usagePercentage == 0.72)

        // Test boundary values (0.0, 1.0, negative, > 1.0)
        let zeroCard = DashboardStorageGaugeCard(
            usagePercentage: 0.0,
            formattedAvailable: "1 TB",
            formattedTotal: "1 TB",
            onSelect: { selectionCount += 1 }
        )
        zeroCard.onSelect()
        #expect(selectionCount == 2)
        #expect(zeroCard.usagePercentage == 0.0)

        let fullCard = DashboardStorageGaugeCard(
            usagePercentage: 1.0,
            formattedAvailable: "0 bytes",
            formattedTotal: "1 TB",
            onSelect: { selectionCount += 1 }
        )
        fullCard.onSelect()
        #expect(selectionCount == 3)
        #expect(fullCard.usagePercentage == 1.0)

        let overCard = DashboardStorageGaugeCard(
            usagePercentage: 1.5,
            formattedAvailable: "0 bytes",
            formattedTotal: "500 GB",
            onSelect: { selectionCount += 1 }
        )
        overCard.onSelect()
        #expect(selectionCount == 4)
        #expect(overCard.usagePercentage == 1.5)
    }

    @Test("F12 Challenger: QuickActionCard callbacks execution across all 4 maintenance tools")
    @MainActor
    func testAllQuickActionCardCallbacks() {
        var cleanCalled = false
        var dupCalled = false
        var orgCalled = false
        var spaceCalled = false

        let cards: [QuickActionCard] = [
            QuickActionCard(title: "Clean Caches", subtitle: "Safe removal", icon: "trash.fill", color: .orange, action: { cleanCalled = true }),
            QuickActionCard(title: "Find Duplicates", subtitle: "Locate identical files", icon: "doc.on.doc.fill", color: .teal, action: { dupCalled = true }),
            QuickActionCard(title: "Organize Files", subtitle: "Sort Downloads", icon: "folder.badge.gearshape", color: .blue, action: { orgCalled = true }),
            QuickActionCard(title: "Analyze Space", subtitle: "Inspect largest files", icon: "chart.pie.fill", color: .indigo, action: { spaceCalled = true })
        ]

        #expect(cards.count == 4)

        for card in cards {
            #expect(!card.title.isEmpty)
            #expect(!card.subtitle.isEmpty)
            #expect(!card.icon.isEmpty)
            card.action()
        }

        #expect(cleanCalled == true)
        #expect(dupCalled == true)
        #expect(orgCalled == true)
        #expect(spaceCalled == true)
    }

    @Test("F12 Challenger: RecentOperationRowView state and metadata across all ActionTypes")
    @MainActor
    func testRecentOperationRowViewAcrossActionTypes() {
        var rolledBackId: UUID? = nil
        var revealedPath: String? = nil

        let testTypes: [OperationRecord.ActionType] = [.moveToTrash, .moveFile, .createDirectory]

        for actionType in testTypes {
            let record = OperationRecord(
                id: UUID(),
                timestamp: Date(),
                actionType: actionType,
                sourcePath: "/Users/test/Downloads/asset_\(actionType.rawValue).dat",
                destinationPath: "/Users/test/.Trash/asset_\(actionType.rawValue).dat",
                fileSize: 1024 * 1024 * 25,
                reason: "Automated test for \(actionType.rawValue)",
                isRolledBack: false
            )

            let row = RecentOperationRowView(
                op: record,
                onRollback: { id in rolledBackId = id },
                onReveal: { path in revealedPath = path }
            )

            #expect(row.op.id == record.id)
            #expect(row.op.actionType == actionType)
            #expect(!row.op.isRolledBack)
            #expect(row.op.formattedSize.contains("25") || row.op.formattedSize.contains("MB"))

            row.onRollback(record.id)
            #expect(rolledBackId == record.id)

            row.onReveal(record.sourcePath)
            #expect(revealedPath == record.sourcePath)
        }

        // Test rolled-back operation record
        let rolledBackRecord = OperationRecord(
            id: UUID(),
            timestamp: Date(),
            actionType: .moveToTrash,
            sourcePath: "/Users/test/old.log",
            destinationPath: "/Users/test/.Trash/old.log",
            fileSize: 100,
            reason: "Log cleanup",
            isRolledBack: true
        )

        let rolledBackRow = RecentOperationRowView(
            op: rolledBackRecord,
            onRollback: { _ in },
            onReveal: { _ in }
        )

        #expect(rolledBackRow.op.isRolledBack == true)
    }

    @Test("F12 Challenger: Recent Actions rollback execution and error resilience")
    func testRecentActionsRollbackExecutionAndResilience() throws {
        let sandbox = try ChallengerM3Sandbox()
        defer { sandbox.cleanup() }

        // Test 1: Real file move to trash and successful rollback
        let originalContent = Data("Important business record for Challenger M3".utf8)
        let sourceFile = try sandbox.createFile(at: "Document_M3.txt", content: originalContent)

        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(
            at: sourceFile,
            reason: "Challenger M3 rollback test"
        )

        #expect(!FileManager.default.fileExists(atPath: sourceFile.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))

        let record = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: sourceFile.path,
            destinationPath: trashedURL.path,
            fileSize: Int64(originalContent.count),
            reason: "Challenger M3 rollback test"
        )
        RollbackLedger.shared.recordOperation(record)

        // Execute rollback
        let restoredURL = try RollbackLedger.shared.rollback(recordId: record.id)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        let restoredData = try Data(contentsOf: restoredURL)
        #expect(restoredData == originalContent)

        // Test 2: Double-rollback throws error (already rolled back)
        #expect(throws: Error.self) {
            try RollbackLedger.shared.rollback(recordId: record.id)
        }

        // Test 3: Non-existent UUID rollback throws error (not found)
        let bogusUUID = UUID()
        #expect(throws: Error.self) {
            try RollbackLedger.shared.rollback(recordId: bogusUUID)
        }

        // Test 4: Rollback when destination file is missing throws error
        let missingFileRecord = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: sandbox.fileURL("non_existent_original.txt").path,
            destinationPath: sandbox.fileURL("non_existent_in_trash.txt").path,
            fileSize: 50,
            reason: "Challenger test for missing trash destination"
        )
        RollbackLedger.shared.recordOperation(missingFileRecord)

        #expect(throws: Error.self) {
            try RollbackLedger.shared.rollback(recordId: missingFileRecord.id)
        }
    }

    @Test("F12 Challenger: Rollback collision handling safely creates (Restored) copy without data loss")
    func testRollbackCollisionHandling() throws {
        let sandbox = try ChallengerM3Sandbox()
        defer { sandbox.cleanup() }

        let originalContent = Data("Original File content".utf8)
        let fileURL = try sandbox.createFile(at: "ChallengerNote.md", content: originalContent)

        // Trash the original file
        let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: fileURL, reason: "Collision prep")
        let record = OperationRecord(
            actionType: .moveToTrash,
            sourcePath: fileURL.path,
            destinationPath: trashedURL.path,
            fileSize: Int64(originalContent.count),
            reason: "Collision prep"
        )
        RollbackLedger.shared.recordOperation(record)

        // Recreate a NEW conflicting file at the original path
        let newContent = Data("New replacement file content".utf8)
        _ = try sandbox.createFile(at: "ChallengerNote.md", content: newContent)

        // Rollback should resolve collision without overwriting new file
        let restoredURL = try RollbackLedger.shared.rollback(recordId: record.id)

        #expect(restoredURL.path != fileURL.path)
        #expect(restoredURL.lastPathComponent.contains("Restored"))
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))

        let newFileData = try Data(contentsOf: fileURL)
        let restoredFileData = try Data(contentsOf: restoredURL)
        #expect(newFileData == newContent)
        #expect(restoredFileData == originalContent)
    }
}
