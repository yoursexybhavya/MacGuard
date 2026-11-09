# Project: MacGuard Apple-Grade Interactive Overhaul

## Architecture
MacGuard is a pure native macOS 14.0+ SwiftUI application designed as an offline maintenance intelligence tool and capability showcase.

### Core Architecture & Data Flow
1. **Application Shell & Navigation**:
   - `NavigationCoordinator` (centralized observable router) manages selected section, navigation stack, and parameterized deep links (e.g. Storage -> Drill Down, Dashboard -> Category).
   - `HardwareMonitor` provides live system metrics (Metal device name, CPU core count, active RAM usage) replacing static placeholders in `MainView`.
2. **Scanner & Storage Engine**:
   - `StorageAnalyzer` scans APFS file hierarchies and populates `StorageOverview`.
   - `StorageOverview` retains full `categoryFiles: [FileCategory: [ScannedItem]]` across all 12 categories, computing accurate proportions including macOS System Data and Free Space.
3. **Safety & File Operations Engine**:
   - `SecurityGuard.shared.safelyMoveToTrash(at:)` uses `FileManager.default.trashItem(at:resultingItemURL:)` to safely move items to Trash and capture the exact destination trash URL.
   - All destructive actions require explicit user confirmation (`.confirmationDialog`).
   - Every file modification is logged in `RollbackLedger` with source and destination URLs, supporting full reversibility and undo.
4. **UI Presentation Layer**:
   - Fluid Apple-grade craft: interactive cards, hover feedback, active press states, `.quickLookPreview` across all file lists, context menus, and custom sheet views.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | Storage Category Retention | Update `StorageOverview` and `StorageAnalyzer` to retain `categoryFiles: [FileCategory: [ScannedItem]]` for all 12 categories | M1 | Survey 1, Survey 3 |
| F2 | Universal Safe Trashing | Route all file trashing in `AssistantView`, `FileOrganizer`, and views through `SecurityGuard.safelyMoveToTrash` with `resultingItemURL` captured | M1 | Survey 3, R3 |
| F3 | Zero Permanent Deletion | Replace `removeItem` in `FileOrganizer.swift:369` with safe trashing or non-destructive folder pruning | M1 | Survey 3, R3 |
| F4 | Enhanced RollbackLedger | Support reactive change notification, robust `.moveToTrash` undo with destination collision handling, and batch rollback | M1 | Survey 3, R3 |
| F5 | Storage Category Cards Interactivity | Make all 12 category cards clickable buttons with hover/active animations, item counts, and drill-down trigger | M2 | Survey 1, R1 |
| F6 | Dynamic Segmented Storage Bar | Rebuild storage bar with accurate proportions (Scanned Categories + System Data + Free Space), tooltips, and click-to-filter | M2 | Survey 1, R1 |
| F7 | Category Drill-Down View | Dedicated `CategoryDetailView` with file search, sorting (size, name, date), filtering, batch select, and action bar | M2 | Survey 1, R1 |
| F8 | Largest Files Action Controls | File rows provide Reveal in Finder, Move to Trash (with confirmation dialog), Inspect Metadata, and Quick Look Preview | M2 | Survey 1, R1 |
| F9 | App-Wide Quick Look Integration | Native `.quickLookPreview` integration across all file listings and preview buttons / Spacebar triggers | M2 | Survey 1, Survey 2 |
| F10 | Centralized NavigationCoordinator | Global router supporting cross-screen navigation with category/path parameters | M3 | Survey 2, R2 |
| F11 | Dynamic Shell Status & Hardware Bar | Live Metal device query (`MTLCopyAllDevices`) and memory monitor in `MainView` status pill | M3 | Survey 2, R2 |
| F12 | Dashboard Live Gauge & Action Context | Interactive storage gauge, live non-fallback values, and Recent Actions context menus with inline rollback | M3 | Survey 2, R2 |
| F13 | Duplicate Finder Folder Picker & Keeper | Working `NSOpenPanel` folder selector, interactive keeper switcher, and file preview/comparison | M3 | Survey 2, R2 |
| F14 | Organizer Folder Consolidation & Checkboxes | UI for redundant sibling folder consolidation (`planFolderConsolidation`) and proposal selection checkboxes | M3 | Survey 2, R2 |
| F15 | Assistant Persistent State & Interactive Chips | Persistent chat state across navigation, interactive category chips in `StorageActionCard` | M3 | Survey 2, R2 |
| F16 | Cleanup Center Select-All & Drill-Down | "Select All / Deselect All", safety tier filter tabs, and directory drill-down inspection for cache targets | M4 | Survey 2, R2 |
| F17 | Approvals & History Rich View & Batch Undo | File size column, search/filter by action type, batch rollback, and confirmation dialogs | M4 | Survey 2, R2 |
| F18 | Settings Real Ollama & Background Persistence | Live Ollama model list & status UI, real Metal hardware stats, and persisted background monitor settings | M4 | Survey 2, R2 |
| F19 | Comprehensive Automated Test Suite | Unit & integration tests for category drill-down data flow, safe trashing, rollback ledger state transitions, and UI view models | M5 | Survey 3, R4 |
| F20 | Adversarial Coverage Hardening | White-box edge case testing, invalid path handling, and regression verification | M5 | Dual Track, Tier 5 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Core Safety, Data Retention & Ledger Foundation | Features F1, F2, F3, F4: Retain category files in `StorageOverview`, eliminate permanent deletions, enforce `SecurityGuard.safelyMoveToTrash` across all callers, enhance `RollbackLedger` | none | DONE |
| M2 | Storage Analyzer Interactivity & Category Drill-Down | Features F5, F6, F7, F8, F9: Interactive 12 category buttons, dynamic segmented storage bar, `CategoryDetailView`, Largest Files action controls (Reveal, Trash with confirmation, Metadata sheet, Quick Look) | M1 | DONE |
| M3 | Shell Navigation & Core Workflow Screens | Features F10, F11, F12, F13, F14, F15: `NavigationCoordinator`, live hardware status pill, Dashboard interactive gauge & actions, Duplicate Finder folder picker & keeper switcher, Organizer folder consolidation & proposal checkboxes, Assistant persistent chat & chips | M1, M2 | DONE |
| M4 | Secondary Screens & Settings Overhaul | Features F16, F17, F18: Cleanup Center select-all & directory drill-down, Approvals file sizes & batch rollback, Settings live Ollama & Metal hardware & settings persistence | M1, M3 | DONE |
| M5 | Final Milestone: Test Suite & Adversarial Hardening | Features F19, F20: Verify 100% pass on all existing 20 unit tests, verify new automated tests for interactive behaviors, ledger state transitions, and category filtering, complete adversarial hardening | M2, M3, M4 | DONE |

## Interface Contracts

### NavigationCoordinator ↔ Views
```swift
@MainActor
public final class NavigationCoordinator: ObservableObject {
    public static let shared = NavigationCoordinator()
    @Published public var selectedSection: NavigationSection = .dashboard
    @Published public var storageDrillDownCategory: FileCategory? = nil
    @Published public var duplicateScanFolder: URL? = nil
    @Published public var previewURL: URL? = nil
    
    public func navigateToStorage(category: FileCategory? = nil)
    public func navigateToDuplicates(folder: URL? = nil)
    public func quickLook(fileURL: URL)
}
```

### StorageAnalyzer & StorageOverview Contract
```swift
public struct StorageOverview: Sendable {
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let usedCapacity: Int64
    public let categorySizes: [FileCategory: Int64]
    public let categoryFiles: [FileCategory: [ScannedItem]]
    public let largestFiles: [ScannedItem]
    
    public var scannedTotalBytes: Int64
    public var systemAndOtherBytes: Int64
    public func files(for category: FileCategory) -> [ScannedItem]
}
```

### SecurityGuard & RollbackLedger Contract
```swift
public final class SecurityGuard {
    public static let shared: SecurityGuard
    public func safelyMoveToTrash(at url: URL, reason: String = "User requested trash") throws -> URL
}

public final class RollbackLedger {
    public static let shared: RollbackLedger
    public func recordOperation(type: OperationType, sourcePath: String, destinationPath: String?, reason: String, fileSize: Int64?)
    public func rollback(recordId: UUID) throws
    public func rollbackAll(recordIds: [UUID]) throws -> Int
}
```

## Code Layout
- `MacGuard/Package.swift`: Swift package manifest
- `MacGuard/Sources/MacGuard/MacGuard.swift`: App entry point and menu bar
- `MacGuard/Sources/MacGuard/Core/Scanner/`: `SystemScanner.swift`, `StorageAnalyzer.swift`
- `MacGuard/Sources/MacGuard/Core/Security/`: `SecurityGuard.swift`, `PermissionManager.swift`
- `MacGuard/Sources/MacGuard/Core/History/`: `RollbackLedger.swift`
- `MacGuard/Sources/MacGuard/Core/Cleaner/`: `CleanupEngine.swift`
- `MacGuard/Sources/MacGuard/Core/Organizer/`: `FileOrganizer.swift`
- `MacGuard/Sources/MacGuard/Core/Navigation/`: `NavigationCoordinator.swift` (new)
- `MacGuard/Sources/MacGuard/Views/`:
  - `MainView.swift`: App shell, sidebar, live hardware pill
  - `DashboardView.swift`: Interactive gauge, live stats, recent actions
  - `StorageView.swift`: Category buttons, dynamic progress bar, file actions
  - `CategoryDetailView.swift`: Drill-down view for category files with filter/sort/inspect (new)
  - `DuplicatesView.swift`: Folder picker, keeper switcher, preview
  - `OrganizerView.swift`: Proposal checkboxes, folder consolidation UI
  - `CleanupView.swift`: Select all/none, directory inspection
  - `ApprovalCenterView.swift`: File sizes, batch rollback, search
  - `SettingsView.swift`: Live Ollama status/models, hardware specs, preferences
- `MacGuard/Tests/MacGuardTests/`:
  - `MacGuardTests.swift`: Existing 20 tests (SecurityGuard, SystemScanner, FileOrganizer, RollbackLedger, AIMaintenance)
  - `InteractiveAndStorageTests.swift`: New automated tests for category drill-down data flow, safe trashing, ledger transitions, and navigation (new)
