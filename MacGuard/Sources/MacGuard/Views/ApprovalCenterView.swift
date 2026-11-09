import SwiftUI
import AppKit

public struct ApprovalCenterView: View {
    @ObservedObject private var ledger = RollbackLedger.shared

    // Interactive States
    @State private var searchText: String = ""
    @State private var selectedFilter: OperationFilter = .all
    @State private var selectedRecordIDs: Set<UUID> = []

    // Confirmation & Sheet States
    @State private var recordToRollback: OperationRecord? = nil
    @State private var showSingleRollbackConfirmation: Bool = false
    @State private var showBatchRollbackConfirmation: Bool = false

    // Feedback & Toast States
    @State private var statusMessage: String? = nil
    @State private var isError: Bool = false
    @State private var showFeedbackBanner: Bool = false

    public init() {}

    // MARK: - Computed Properties

    public var filteredOperations: [OperationRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ledger.operations.filter { record in
            guard record.matches(filter: selectedFilter) else { return false }
            guard !query.isEmpty else { return true }
            return record.fileName.localizedCaseInsensitiveContains(query) ||
                   record.reason.localizedCaseInsensitiveContains(query) ||
                   record.actionType.rawValue.localizedCaseInsensitiveContains(query) ||
                   record.sourcePath.localizedCaseInsensitiveContains(query) ||
                   (record.destinationPath?.localizedCaseInsensitiveContains(query) ?? false) ||
                   record.formattedSize.localizedCaseInsensitiveContains(query)
        }
    }

    public var reversibleOperations: [OperationRecord] {
        filteredOperations.filter { !$0.isRolledBack }
    }

    private var selectedRecords: [OperationRecord] {
        ledger.operations.filter { selectedRecordIDs.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedRecords.compactMap(\.byteAccurateSize).reduce(0, +)
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

            if !selectedRecordIDs.isEmpty {
                batchActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let message = statusMessage, showFeedbackBanner {
                feedbackBanner(message: message, isError: isError)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedRecordIDs)
        .animation(.easeInOut(duration: 0.2), value: showFeedbackBanner)
        .confirmationDialog(
            "Rollback '\(recordToRollback?.fileName ?? "Operation")'?",
            isPresented: $showSingleRollbackConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rollback Operation", role: .destructive) {
                if let r = recordToRollback {
                    executeSingleRollback(for: r.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let r = recordToRollback {
                Text("This will move '\(r.fileName)' back to its original location:\n'\(r.sourcePath)'.\nAny file collisions will be resolved safely with non-colliding names.")
            } else {
                Text("This will restore the file to its original location.")
            }
        }
        .confirmationDialog(
            "Rollback \(selectedRecordIDs.count) operations?",
            isPresented: $showBatchRollbackConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rollback \(selectedRecordIDs.count) Operations", role: .destructive) {
                executeBatchRollback()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These \(selectedRecordIDs.count) operations (\(formattedSelectedSize)) will be restored to their original locations in strict reverse-chronological order.\nZero permanent deletion guarantee applies.")
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.blue)
                    .font(.system(size: 17, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Approval Center & History")
                        .font(.system(size: 20, weight: .bold))
                    Text("Feature F17")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                Text("Complete audit ledger of all file operations with instant search, category filters, and 100% reversible rollback")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Active Ledger Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("\(ledger.operations.count) Total Logged")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)

            Button {
                ledger.reloadFromDisk()
                notify(message: "Ledger refreshed from disk", isError: false)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh ledger records from disk")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var toolbarView: some View {
        VStack(spacing: 10) {
            // Row 1: Search Field + Select All / Deselect All
            HStack(spacing: 12) {
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search operations by filename, reason, action, or path...", text: $searchText)
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
                .frame(maxWidth: 420)

                Spacer()

                // "Select All" / "Deselect All" Button
                if !reversibleOperations.isEmpty {
                    Button {
                        toggleSelectAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedRecordIDs.count == reversibleOperations.count ? "checkmark.circle.fill" : "circle")
                            Text(selectedRecordIDs.count == reversibleOperations.count ? "Deselect All" : "Select All Reversible")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Row 2: Filter Chips
            HStack(spacing: 8) {
                ForEach(OperationFilter.allCases) { filter in
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
                        .background(selectedFilter == filter ? Color.accentColor : Color.secondary.opacity(0.08))
                        .foregroundColor(selectedFilter == filter ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !searchText.isEmpty {
                    Text("Showing \(filteredOperations.count) of \(ledger.operations.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.02))
    }

    @ViewBuilder
    private var contentView: some View {
        if ledger.operations.isEmpty {
            emptyLedgerView
        } else if filteredOperations.isEmpty {
            noSearchResultsView
        } else {
            operationsListView
        }
    }

    private var operationsListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredOperations) { record in
                    ApprovalOperationRowView(
                        record: record,
                        isSelected: selectedRecordIDs.contains(record.id),
                        onToggleSelect: {
                            toggleSelection(for: record.id)
                        },
                        onRollback: {
                            recordToRollback = record
                            showSingleRollbackConfirmation = true
                        },
                        onReveal: {
                            revealInFinder(for: record)
                        },
                        onCopyPath: {
                            copyPath(for: record)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Batch Action Bar

    private var batchActionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedRecordIDs.count) Operations Selected")
                    .font(.system(size: 13, weight: .bold))
                Text("Total size: \(formattedSelectedSize) • Reverses in strict LIFO order")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Deselect All") {
                selectedRecordIDs.removeAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                showBatchRollbackConfirmation = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Rollback Selected (\(selectedRecordIDs.count))")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.secondary.opacity(0.15)), alignment: .top)
    }

    // MARK: - Empty States

    private var emptyLedgerView: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 38))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 6) {
                Text("No Operations Recorded Yet")
                    .font(.system(size: 18, weight: .bold))
                Text("Any file movements, safe trashing, or duplicate cleanups performed in MacGuard will be logged here with complete 100% reversible undo.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("Zero Permanent Deletion Guarantee Active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.08))
            .cornerRadius(12)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 6) {
                Text("No Matching Operations Found")
                    .font(.system(size: 16, weight: .bold))
                if !searchText.isEmpty {
                    Text("No operations match '\(searchText)' under the '\(selectedFilter.rawValue)' filter.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("No operations found under the '\(selectedFilter.rawValue)' filter category.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Button("Reset Search & Filters") {
                withAnimation {
                    searchText = ""
                    selectedFilter = .all
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func feedbackBanner(message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button {
                showFeedbackBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background((isError ? Color.red : Color.green).opacity(0.12))
        .cornerRadius(8)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Action Handlers

    private func toggleSelection(for id: UUID) {
        if selectedRecordIDs.contains(id) {
            selectedRecordIDs.remove(id)
        } else {
            selectedRecordIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        if selectedRecordIDs.count == reversibleOperations.count {
            selectedRecordIDs.removeAll()
        } else {
            selectedRecordIDs = Set(reversibleOperations.map(\.id))
        }
    }

    private func countForFilter(_ filter: OperationFilter) -> Int {
        ledger.operations.filter { $0.matches(filter: filter) }.count
    }

    private func executeSingleRollback(for id: UUID) {
        do {
            try ledger.rollback(operationId: id)
            selectedRecordIDs.remove(id)
            notify(message: "Successfully reversed operation and restored file.", isError: false)
        } catch {
            notify(message: "Rollback failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func executeBatchRollback() {
        let idsToRollback = Array(selectedRecordIDs)
        do {
            let count = try ledger.rollbackAll(recordIds: idsToRollback)
            selectedRecordIDs.removeAll()
            notify(message: "Successfully restored \(count) operation\(count == 1 ? "" : "s") in reverse-chronological order.", isError: false)
        } catch {
            notify(message: "Batch rollback failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func revealInFinder(for record: OperationRecord) {
        let targetPath = record.isRolledBack ? record.sourcePath : (record.destinationPath ?? record.sourcePath)
        let url = URL(fileURLWithPath: targetPath)
        if FileManager.default.fileExists(atPath: targetPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        } else {
            notify(message: "Target file is no longer present on disk.", isError: true)
        }
    }

    private func copyPath(for record: OperationRecord) {
        let path = record.isRolledBack ? record.sourcePath : (record.destinationPath ?? record.sourcePath)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        notify(message: "Copied path for '\(record.fileName)' to clipboard", isError: false)
    }

    private func notify(message: String, isError: Bool) {
        self.statusMessage = message
        self.isError = isError
        self.showFeedbackBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.statusMessage == message {
                withAnimation {
                    self.showFeedbackBanner = false
                }
            }
        }
    }
}

// MARK: - ApprovalOperationRowView Component

public struct ApprovalOperationRowView: View {
    public let record: OperationRecord
    public let isSelected: Bool
    public let onToggleSelect: () -> Void
    public let onRollback: () -> Void
    public let onReveal: () -> Void
    public let onCopyPath: () -> Void

    @State private var isHovered: Bool = false

    public init(
        record: OperationRecord,
        isSelected: Bool,
        onToggleSelect: @escaping () -> Void,
        onRollback: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopyPath: @escaping () -> Void
    ) {
        self.record = record
        self.isSelected = isSelected
        self.onToggleSelect = onToggleSelect
        self.onRollback = onRollback
        self.onReveal = onReveal
        self.onCopyPath = onCopyPath
    }

    private var iconBackgroundColor: Color {
        switch record.actionType {
        case .moveToTrash:
            return Color.orange.opacity(0.15)
        case .moveFile:
            return Color.blue.opacity(0.15)
        case .createDirectory:
            return Color.purple.opacity(0.15)
        }
    }

    private var iconForegroundColor: Color {
        switch record.actionType {
        case .moveToTrash:
            return .orange
        case .moveFile:
            return .blue
        case .createDirectory:
            return .purple
        }
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 1. Selection Checkbox (Active/Reversible only)
            if !record.isRolledBack {
                Button {
                    onToggleSelect()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.6))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 15, height: 15)
            }

            // 2. Action Type Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBackgroundColor)
                    .frame(width: 36, height: 36)
                Image(systemName: record.systemImageName)
                    .foregroundColor(iconForegroundColor)
                    .font(.system(size: 15, weight: .semibold))
            }

            // 3. File Details, Reason, Path Flow
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(record.fileName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(record.actionType.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)

                    if record.isRolledBack {
                        Text("Rolled Back")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    } else {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }

                // Path Flow
                HStack(spacing: 4) {
                    Text(record.sourcePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let dest = record.destinationPath {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(dest)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

                // Reason & Timestamp
                HStack(spacing: 8) {
                    Text(record.reason)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(record.timestamp, style: .date)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(record.timestamp, style: .time)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 4. Byte-Accurate File Size Column
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.formattedSize)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                if let bytes = record.byteAccurateSize ?? record.fileSize, bytes > 0 {
                    Text("\(bytes.formatted()) B")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 80, alignment: .trailing)
            .padding(.trailing, 8)
            .help(record.exactByteCountDescription)

            // 5. Individual Row Actions
            HStack(spacing: 6) {
                Button {
                    onCopyPath()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy file path to clipboard")

                Button {
                    onReveal()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal location in Finder")

                if !record.isRolledBack {
                    Button {
                        onRollback()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Rollback")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reversible undo for this operation")
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
        .cornerRadius(8)
        .onHover { isHovered = $0 }
        .contextMenu {
            if !record.isRolledBack {
                Button {
                    onRollback()
                } label: {
                    Label("Rollback Operation", systemImage: "arrow.uturn.backward")
                }
            }
            Button {
                onReveal()
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
            }
            Button {
                onCopyPath()
            } label: {
                Label("Copy File Path", systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                let p = NSPasteboard.general
                p.clearContents()
                p.setString(record.sourcePath, forType: .string)
            } label: {
                Label("Copy Source Path", systemImage: "arrow.right.doc.on.clipboard")
            }
            if let dest = record.destinationPath {
                Button {
                    let p = NSPasteboard.general
                    p.clearContents()
                    p.setString(dest, forType: .string)
                } label: {
                    Label("Copy Destination Path", systemImage: "arrow.right.doc.on.clipboard")
                }
            }
            Button {
                let p = NSPasteboard.general
                p.clearContents()
                p.setString(record.reason, forType: .string)
            } label: {
                Label("Copy Reason", systemImage: "text.bubble")
            }
        }
    }
}

