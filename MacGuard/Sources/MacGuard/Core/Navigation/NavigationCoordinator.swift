import SwiftUI
import Foundation

// MARK: - Navigation Section Primitive

public enum NavigationSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard = "Dashboard"
    case assistant = "AI Assistant"
    case storage = "Storage Analyzer"
    case duplicates = "Duplicate Finder"
    case organizer = "File Organizer"
    case cleanup = "Cleanup Center"
    case approvals = "Approvals & History"
    case settings = "Settings & Model"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dashboard: return "speedometer"
        case .assistant: return "sparkles"
        case .storage: return "chart.pie.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .organizer: return "folder.badge.gearshape"
        case .cleanup: return "trash.fill"
        case .approvals: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Centralized Navigation Coordinator (Feature F10)

@MainActor
public final class NavigationCoordinator: ObservableObject {
    public static let shared = NavigationCoordinator()

    /// Current active navigation section displayed in MainView detail
    @Published public var selectedSection: NavigationSection = .dashboard

    /// Deep-link target category for Storage Analyzer drill-down view
    @Published public var storageDrillDownCategory: FileCategory? = nil

    /// Target folder URL for Duplicate Finder scanning
    @Published public var duplicateScanFolder: URL? = nil

    /// Active Quick Look preview URL for app-wide file preview
    @Published public var previewURL: URL? = nil

    public init(
        initialSection: NavigationSection = .dashboard,
        initialCategory: FileCategory? = nil,
        initialDuplicateFolder: URL? = nil,
        initialPreview: URL? = nil
    ) {
        self.selectedSection = initialSection
        self.storageDrillDownCategory = initialCategory
        self.duplicateScanFolder = initialDuplicateFolder
        self.previewURL = initialPreview
    }

    // MARK: - Convenience Navigation Methods

    /// Navigates to a specific section, resetting ephemeral sub-view drill-downs when navigating away from Storage
    public func navigateTo(section: NavigationSection) {
        if section != .storage {
            self.storageDrillDownCategory = nil
        }
        self.selectedSection = section
    }

    /// Alias for navigateTo(section:)
    public func navigate(to section: NavigationSection) {
        navigateTo(section: section)
    }

    /// Deep-links to Storage Analyzer with an optional category drill-down
    public func navigateToStorage(category: FileCategory? = nil) {
        self.storageDrillDownCategory = category
        self.selectedSection = .storage
    }

    /// Deep-links to Duplicate Finder with an optional scan root folder
    public func navigateToDuplicates(folder: URL? = nil) {
        self.duplicateScanFolder = folder
        self.selectedSection = .duplicates
    }

    public func navigateToOrganizer() {
        self.selectedSection = .organizer
    }

    public func navigateToCleanup() {
        self.selectedSection = .cleanup
    }

    public func navigateToApprovals() {
        self.selectedSection = .approvals
    }

    public func navigateToSettings() {
        self.selectedSection = .settings
    }

    /// Triggers Quick Look for a specific file URL across any application view
    public func quickLook(fileURL: URL) {
        self.previewURL = fileURL
    }

    /// Clears any active category drill-down or preview
    public func clearDrillDown() {
        self.storageDrillDownCategory = nil
        self.previewURL = nil
    }

    /// Clears all state and returns to Dashboard
    public func resetToDashboard() {
        self.storageDrillDownCategory = nil
        self.duplicateScanFolder = nil
        self.previewURL = nil
        self.selectedSection = .dashboard
    }

    // MARK: - SwiftUI Binding Helpers

    /// Provides a Binding<NavigationSection?> compatible with SwiftUI List(selection:)
    public var selectionBinding: Binding<NavigationSection?> {
        Binding(
            get: { self.selectedSection },
            set: { [weak self] newValue in
                guard let self = self, let value = newValue else { return }
                self.navigateTo(section: value)
            }
        )
    }
}
