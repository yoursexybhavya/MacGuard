import SwiftUI
import AppKit
import QuickLook

public enum SortOption: String, CaseIterable, Identifiable {
    case sizeDesc = "Size (Largest First)"
    case sizeAsc = "Size (Smallest First)"
    case nameAsc = "Name (A to Z)"
    case nameDesc = "Name (Z to A)"
    case dateDesc = "Date Modified (Newest)"
    case dateAsc = "Date Modified (Oldest)"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .sizeDesc: return "arrow.down.circle"
        case .sizeAsc: return "arrow.up.circle"
        case .nameAsc: return "textformat.abc"
        case .nameDesc: return "textformat.abc"
        case .dateDesc: return "calendar.badge.clock"
        case .dateAsc: return "calendar"
        }
    }
}

/// Dedicated category drill-down view providing real-time search, 6-way sorting, batch selection, and safe trashing.
public struct CategoryDetailView: View {
    public let category: FileCategory
    public let onDismiss: () -> Void
    public var onFilesChanged: (([ScannedItem]) -> Void)?

    @State private var items: [ScannedItem]
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .sizeDesc
    @State private var selectedItemIDs: Set<String> = []

    // Dialog & Feedback States
    @State private var showBatchTrashConfirmation: Bool = false
    @State private var previewURL: URL? = nil
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false

    public init(
        category: FileCategory,
        initialItems: [ScannedItem],
        onDismiss: @escaping () -> Void,
        onFilesChanged: (([ScannedItem]) -> Void)? = nil
    ) {
        self.category = category
        self._items = State(initialValue: initialItems)
        self.onDismiss = onDismiss
        self.onFilesChanged = onFilesChanged
    }

    /// Convenience initializer accepting StorageOverview
    public init(
        category: FileCategory,
        overview: StorageOverview,
        onDismiss: @escaping () -> Void,
        onFilesChanged: (([ScannedItem]) -> Void)? = nil
    ) {
        self.init(
            category: category,
            initialItems: overview.files(for: category),
            onDismiss: onDismiss,
            onFilesChanged: onFilesChanged
        )
    }

    // MARK: - Computed Filter & Sort

    public var sortedAndFilteredItems: [ScannedItem] {
        let filtered = items.filter { item in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(query) ||
                   item.path.localizedCaseInsensitiveContains(query)
        }

        return filtered.sorted { a, b in
            switch sortOption {
            case .sizeDesc:
                if a.size != b.size { return a.size > b.size }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .sizeAsc:
                if a.size != b.size { return a.size < b.size }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .nameAsc:
                let comp = a.name.localizedStandardCompare(b.name)
                if comp != .orderedSame { return comp == .orderedAscending }
                return a.path < b.path
            case .nameDesc:
                let comp = a.name.localizedStandardCompare(b.name)
                if comp != .orderedSame { return comp == .orderedDescending }
                return a.path > b.path
            case .dateDesc:
                if a.modificationDate != b.modificationDate { return a.modificationDate > b.modificationDate }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .dateAsc:
                if a.modificationDate != b.modificationDate { return a.modificationDate < b.modificationDate }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    private var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    private var selectedBytes: Int64 {
        items.filter { selectedItemIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            toolbarView
            Divider()

            contentView

            if !selectedItemIDs.isEmpty {
                batchActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .quickLookPreview($previewURL)
        .confirmationDialog(
            "Move \(selectedItemIDs.count) items to Trash?",
            isPresented: $showBatchTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                executeBatchTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These \(selectedItemIDs.count) items (\(formattedSelectedSize)) will be safely moved to macOS Trash and recorded in Approvals & History for reversible restoration.")
        }
        .alert("Operation Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 14) {
            Button {
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("Storage Analyzer")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .help("Back to Storage Overview")

            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: category.systemIcon)
                    .foregroundColor(categoryColor)
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.system(size: 20, weight: .bold))
                HStack(spacing: 8) {
                    Text("\(items.count) items")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(formattedTotalSize)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    if !searchText.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Showing \(sortedAndFilteredItems.count) filtered")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Search Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search files by name or path...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
            .frame(maxWidth: 320)

            Spacer()

            // Select All / Deselect All
            if !sortedAndFilteredItems.isEmpty {
                Button {
                    toggleSelectAll()
                } label: {
                    Text(selectedItemIDs.count == sortedAndFilteredItems.count && !sortedAndFilteredItems.isEmpty ? "Deselect All" : "Select All")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
            }

            // Sort Menu
            Menu {
                Picker("Sort By", selection: $sortOption) {
                    ForEach(SortOption.allCases) { opt in
                        Label(opt.rawValue, systemImage: opt.icon)
                            .tag(opt)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOption.rawValue)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .menuStyle(.borderedButton)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.02))
    }

    @ViewBuilder
    private var contentView: some View {
        if items.isEmpty {
            emptyCategoryView
        } else if sortedAndFilteredItems.isEmpty {
            noSearchResultsView
        } else {
            fileListView
        }
    }

    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(sortedAndFilteredItems) { item in
                    ScannedFileRowView(
                        file: item,
                        categoryColor: categoryColor,
                        isSelected: selectedItemIDs.contains(item.id),
                        showCheckbox: true,
                        showCategoryIcon: false,
                        showPath: true,
                        showDate: true,
                        onSelect: {
                            toggleSelection(for: item.id)
                        },
                        onQuickLook: { url in
                            previewURL = url
                        },
                        onReveal: { url in
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        },
                        onTrash: { trashedItem in
                            handleSingleTrash(item: trashedItem)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var emptyCategoryView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: category.systemIcon)
                .font(.system(size: 48))
                .foregroundColor(categoryColor.opacity(0.4))
            Text("No Files Found in \(category.rawValue)")
                .font(.system(size: 16, weight: .bold))
            Text("There are currently no discovered files in this category. Your disk is clean in this section.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button("Return to Storage Overview") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Files Matched \"\(searchText)\"")
                .font(.system(size: 15, weight: .semibold))
            Text("Check your spelling or try clearing the search filter to view all \(items.count) files.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button("Clear Filter") {
                searchText = ""
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var batchActionBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                Text("\(selectedItemIDs.count) files selected (\(formattedSelectedSize))")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            Button("Clear Selection") {
                withAnimation(.easeOut(duration: 0.15)) {
                    selectedItemIDs.removeAll()
                }
            }
            .buttonStyle(.bordered)

            Button {
                showBatchTrashConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Move to Trash (\(selectedItemIDs.count))")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Actions & Safety

    private func toggleSelection(for id: String) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        if selectedItemIDs.count == sortedAndFilteredItems.count && !sortedAndFilteredItems.isEmpty {
            selectedItemIDs.removeAll()
        } else {
            selectedItemIDs = Set(sortedAndFilteredItems.map(\.id))
        }
    }

    private func handleSingleTrash(item: ScannedItem) {
        withAnimation(.easeOut(duration: 0.25)) {
            items.removeAll { $0.id == item.id }
            selectedItemIDs.remove(item.id)
        }
        onFilesChanged?(items)
    }

    private func executeBatchTrash() {
        let targets = items.filter { selectedItemIDs.contains($0.id) }
        var trashedIDs: Set<String> = []
        var failures: [String] = []

        for item in targets {
            do {
                let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(
                    at: item.url,
                    reason: "Batch trash from \(category.rawValue) detail view"
                )
                let record = OperationRecord(
                    actionType: .moveToTrash,
                    sourcePath: item.path,
                    destinationPath: trashedURL.path,
                    fileSize: item.size,
                    reason: "Batch trash from \(category.rawValue) detail view"
                )
                RollbackLedger.shared.recordOperation(record)
                trashedIDs.insert(item.id)
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }

        withAnimation(.easeOut(duration: 0.25)) {
            items.removeAll { trashedIDs.contains($0.id) }
            selectedItemIDs.subtract(trashedIDs)
        }
        onFilesChanged?(items)

        if !failures.isEmpty {
            alertMessage = "Failed to trash \(failures.count) file(s): " + failures.joined(separator: ", ")
            showAlert = true
        }
    }

    private var categoryColor: Color {
        category.color
    }
}
