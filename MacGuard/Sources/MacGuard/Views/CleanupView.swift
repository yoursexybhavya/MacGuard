import SwiftUI
import AppKit
import QuickLook

public enum CleanupFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Items"
    case safeCaches = "Safe Caches"
    case logs = "System Logs"
    case review = "Review Recommended"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "tray.full"
        case .safeCaches: return "checkmark.shield"
        case .logs: return "doc.text"
        case .review: return "exclamationmark.triangle"
        }
    }
}

public struct CleanupView: View {
    @State private var candidates: [CleanupTarget] = []
    @State private var selectedFilter: CleanupFilter = .all
    @State private var expandedTargetIDs: Set<UUID> = []
    @State private var isLoading: Bool = true
    @State private var showConfirmSheet: Bool = false
    @State private var executionMessage: String?

    // Popover & Action States
    @State private var inspectingTarget: CleanupTarget? = nil
    @State private var inspectingSubItem: CleanupSubItem? = nil
    @State private var previewURL: URL? = nil
    @State private var singleTrashTarget: CleanupTarget? = nil
    @State private var showSingleTrashConfirm: Bool = false

    public init() {}

    // MARK: - Computed Properties

    public var filteredCandidates: [CleanupTarget] {
        candidates.filter { target in
            switch selectedFilter {
            case .all:
                return true
            case .safeCaches:
                return target.safetyTier == .safe && (target.category.contains("Cache") || target.category.contains("Developer") || target.category.contains("Artifact"))
            case .logs:
                return target.category.contains("Log") || target.name.contains("Log")
            case .review:
                return target.safetyTier == .reviewRecommended || target.category.contains("Installer")
            }
        }
    }

    private var isAllFilteredSelected: Bool {
        let visible = filteredCandidates
        guard !visible.isEmpty else { return false }
        let visibleIDs = Set(visible.map(\.id))
        return candidates.filter { visibleIDs.contains($0.id) }.allSatisfy { $0.isSelected }
    }

    private var selectedItems: [CleanupTarget] {
        candidates.filter { $0.isSelected }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            Divider()

            // Filter Tabs Bar
            filterTabsBar
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Scanning user caches, logs, and installer files...")
                Spacer()
            } else if candidates.isEmpty {
                Spacer()
                emptyStateView
                Spacer()
            } else {
                VStack(spacing: 0) {
                    // Action Summary Bar
                    actionSummaryBar

                    // Targets List
                    targetsListView
                }
            }

            if let msg = executionMessage {
                feedbackBanner(message: msg)
            }
        }
        .onAppear {
            if candidates.isEmpty {
                loadCandidates()
            }
        }
        .quickLookPreview($previewURL)
        .popover(item: $inspectingTarget) { target in
            FileMetadataPopoverView(
                fileURL: target.url,
                name: target.name,
                size: target.size,
                modificationDate: (try? target.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            )
        }
        .popover(item: $inspectingSubItem) { sub in
            FileMetadataPopoverView(
                fileURL: sub.url,
                name: sub.name,
                size: sub.size,
                modificationDate: sub.modificationDate ?? Date()
            )
        }
        .confirmationDialog(
            "Move '\(singleTrashTarget?.name ?? "")' to Trash?",
            isPresented: $showSingleTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let target = singleTrashTarget {
                    performSingleTrash(target: target)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This item (\(singleTrashTarget?.formattedSize ?? "")) will be safely moved to macOS Trash and recorded in Approvals & History for reversible rollback.")
        }
        .sheet(isPresented: $showConfirmSheet) {
            batchConfirmationSheet
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Intelligent Cleanup Center")
                        .font(.system(size: 22, weight: .bold))
                    Text("Feature F16")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                Text("Safe cache and temporary file cleanup with directory inspection, safety tiers, and 100% reversible Trash")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button {
                loadCandidates()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Rescan caches and disposable files")
        }
        .padding(20)
    }

    private var filterTabsBar: some View {
        HStack(spacing: 8) {
            ForEach(CleanupFilter.allCases) { filter in
                let count = countForFilter(filter)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 11))
                        Text(filter.rawValue)
                            .font(.system(size: 11, weight: selectedFilter == filter ? .semibold : .regular))
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(selectedFilter == filter ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(selectedFilter == filter ? Color.orange : Color.secondary.opacity(0.08))
                    .foregroundColor(selectedFilter == filter ? .white : .primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(filteredCandidates.count) candidates visible")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.02))
    }

    private var actionSummaryBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedItems.count) of \(candidates.count) Items Selected")
                    .font(.system(size: 14, weight: .bold))
                Text("Reclaimable space: \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)) • Items move to macOS Trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Batch Select Controls
            Button {
                toggleSelectAllFiltered()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isAllFilteredSelected ? "checkmark.circle.fill" : "circle")
                    Text(isAllFilteredSelected ? "Deselect All" : "Select All")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)

            Button {
                selectSafeOnly()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield")
                    Text("Safe Only")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .help("Select only guaranteed-safe caches and logs")

            Button {
                showConfirmSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("Clean Selected (\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)))")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(selectedItems.isEmpty)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08))
    }

    private var targetsListView: some View {
        List {
            ForEach($candidates) { $target in
                if filteredCandidates.contains(where: { $0.id == target.id }) {
                    targetRowView(target: $target)
                }
            }
        }
    }

    private func targetRowView(target: Binding<CleanupTarget>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: target.isSelected)
                    .labelsHidden()

                if target.wrappedValue.isDirectory {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expandedTargetIDs.contains(target.wrappedValue.id) {
                                expandedTargetIDs.remove(target.wrappedValue.id)
                            } else {
                                expandedTargetIDs.insert(target.wrappedValue.id)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expandedTargetIDs.contains(target.wrappedValue.id) ? 90 : 0))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(expandedTargetIDs.contains(target.wrappedValue.id) ? "Collapse directory contents" : "Expand directory contents")
                } else {
                    Spacer().frame(width: 16)
                }

                ZStack {
                    Circle()
                        .fill(badgeColor(target.wrappedValue.safetyTier).opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: target.wrappedValue.safetyTier == .safe ? "checkmark.shield" : "exclamationmark.triangle")
                        .foregroundColor(badgeColor(target.wrappedValue.safetyTier))
                        .font(.system(size: 14))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(target.wrappedValue.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(target.wrappedValue.safetyTier.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(target.wrappedValue.safetyTier).opacity(0.15))
                            .foregroundColor(badgeColor(target.wrappedValue.safetyTier))
                            .cornerRadius(4)
                        Text(target.wrappedValue.category)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    }

                    Text(target.wrappedValue.explanation)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button {
                        revealInFinder(path: target.wrappedValue.path)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text(target.wrappedValue.path)
                                .font(.system(size: 10, design: .monospaced))
                                .underline()
                        }
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .help("Click to reveal in Finder")
                }

                Spacer()

                Text(target.wrappedValue.formattedSize)
                    .font(.system(size: 13, weight: .bold))

                // Action Controls
                HStack(spacing: 4) {
                    Button {
                        previewURL = target.wrappedValue.url
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Quick Look Preview")

                    Button {
                        inspectingTarget = target.wrappedValue
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Inspect Metadata & SHA-256")

                    Button {
                        revealInFinder(path: target.wrappedValue.path)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reveal in Finder")

                    Button {
                        singleTrashTarget = target.wrappedValue
                        showSingleTrashConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Move to Trash")
                }
            }
            .padding(.vertical, 4)
            .contextMenu {
                Button {
                    previewURL = target.wrappedValue.url
                } label: {
                    Label("Quick Look Preview", systemImage: "eye")
                }
                Button {
                    inspectingTarget = target.wrappedValue
                } label: {
                    Label("Inspect Metadata", systemImage: "info.circle")
                }
                Button {
                    revealInFinder(path: target.wrappedValue.path)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button {
                    openContainingFolder(path: target.wrappedValue.path)
                } label: {
                    Label("Open Containing Folder", systemImage: "arrow.up.forward.app")
                }
                Divider()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(target.wrappedValue.path, forType: .string)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                Divider()
                Button(role: .destructive) {
                    singleTrashTarget = target.wrappedValue
                    showSingleTrashConfirm = true
                } label: {
                    Label("Move to Trash...", systemImage: "trash")
                }
            }

            // Expanded Sub-Item Inspection
            if expandedTargetIDs.contains(target.wrappedValue.id) {
                VStack(alignment: .leading, spacing: 4) {
                    if target.wrappedValue.subItems.isEmpty {
                        Text("No visible child items found in this directory.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.leading, 48)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(target.wrappedValue.subItems) { sub in
                            HStack(spacing: 8) {
                                Image(systemName: sub.isDirectory ? "folder.fill" : "doc.fill")
                                    .foregroundColor(sub.isDirectory ? .blue : .secondary)
                                    .font(.system(size: 11))

                                Text(sub.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Text(sub.formattedSize)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Button {
                                    previewURL = sub.url
                                } label: {
                                    Image(systemName: "eye")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help("Quick Look")

                                Button {
                                    inspectingSubItem = sub
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help("Inspect Metadata")

                                Button {
                                    revealInFinder(path: sub.path)
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(6)
                            .padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("Your Mac is Clean & Optimized")
                .font(.system(size: 16, weight: .semibold))
            Text("No unnecessary developer caches or disposable installer files found.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var batchConfirmationSheet: some View {
        let selected = candidates.filter { $0.isSelected }
        let total = selected.reduce(0) { $0 + $1.size }

        return VStack(spacing: 16) {
            Text("Confirm Safe Cleanup")
                .font(.system(size: 16, weight: .bold))

            Text("Are you sure you want to move \(selected.count) items (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))) to macOS Trash?")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Note: Files are relocated to macOS Trash and are NOT permanently deleted. You can restore them anytime in Approvals & History.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)

            HStack {
                Button("Cancel") {
                    showConfirmSheet = false
                }
                Spacer()
                Button("Move to Trash") {
                    performCleanup(selected: selected)
                    showConfirmSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 440)
    }

    private func feedbackBanner(message: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle")
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(10)
        .background(Color.green.opacity(0.1))
    }

    // MARK: - Action Helpers

    private func countForFilter(_ filter: CleanupFilter) -> Int {
        candidates.filter { target in
            switch filter {
            case .all:
                return true
            case .safeCaches:
                return target.safetyTier == .safe && (target.category.contains("Cache") || target.category.contains("Developer") || target.category.contains("Artifact"))
            case .logs:
                return target.category.contains("Log") || target.name.contains("Log")
            case .review:
                return target.safetyTier == .reviewRecommended || target.category.contains("Installer")
            }
        }.count
    }

    private func toggleSelectAllFiltered() {
        let selectNewState = !isAllFilteredSelected
        let visibleIDs = Set(filteredCandidates.map(\.id))
        for i in candidates.indices {
            if visibleIDs.contains(candidates[i].id) {
                candidates[i].isSelected = selectNewState
            }
        }
    }

    private func selectSafeOnly() {
        for i in candidates.indices {
            candidates[i].isSelected = (candidates[i].safetyTier == .safe)
        }
    }

    private func loadCandidates() {
        isLoading = true
        executionMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let res = CleanupEngine.shared.discoverCleanupCandidates()
            DispatchQueue.main.async {
                self.candidates = res
                self.isLoading = false
            }
        }
    }

    private func performCleanup(selected: [CleanupTarget]) {
        do {
            try CleanupEngine.shared.executeCleanup(targets: selected)
            let total = selected.reduce(0) { $0 + $1.size }
            executionMessage = "Safely relocated \(selected.count) items (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))) to Trash."
            loadCandidates()
        } catch {
            executionMessage = "Cleanup failed: \(error.localizedDescription)"
        }
    }

    private func performSingleTrash(target: CleanupTarget) {
        do {
            try CleanupEngine.shared.executeCleanup(targets: [target])
            executionMessage = "Safely moved '\(target.name)' to Trash."
            loadCandidates()
        } catch {
            executionMessage = "Failed to trash item: \(error.localizedDescription)"
        }
    }

    private func badgeColor(_ tier: SafetyTier) -> Color {
        switch tier {
        case .safe: return .green
        case .reviewRecommended: return .orange
        case .highRisk: return .red
        case .protected: return .gray
        }
    }

    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            NSWorkspace.shared.open(parent)
        }
    }

    private func openContainingFolder(path: String) {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        NSWorkspace.shared.open(parent)
    }
}
