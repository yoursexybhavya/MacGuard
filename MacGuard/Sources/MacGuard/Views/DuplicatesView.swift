import SwiftUI
import AppKit
import QuickLook

public struct DuplicateGroupItem: Identifiable, Sendable {
    public let id: String
    public let item: ScannedItem
    public var isKeeper: Bool
    public var isSelected: Bool

    public var url: URL { item.url }
    public var size: Int64 { item.size }
    public var filename: String { item.name }
    public var path: String { item.path }
    public var date: Date { item.modificationDate }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public init(id: String, item: ScannedItem, isKeeper: Bool, isSelected: Bool) {
        self.id = id
        self.item = item
        self.isKeeper = isKeeper
        self.isSelected = isSelected
    }
}

public struct DuplicateCluster: Identifiable, Sendable {
    public let id: String // hash
    public var items: [DuplicateGroupItem]
    public let singleFileSize: Int64

    public var reclaimableSize: Int64 {
        let selectedCount = items.filter { $0.isSelected && !$0.isKeeper }.count
        return Int64(selectedCount) * singleFileSize
    }

    public var totalWastedSize: Int64 {
        let duplicateCount = max(0, items.count - 1)
        return Int64(duplicateCount) * singleFileSize
    }

    public var keeperItem: DuplicateGroupItem? {
        items.first { $0.isKeeper } ?? items.first
    }

    public var candidateDuplicates: [DuplicateGroupItem] {
        items.filter { !$0.isKeeper }
    }

    public init(id: String, items: [DuplicateGroupItem], singleFileSize: Int64) {
        self.id = id
        self.items = items
        self.singleFileSize = singleFileSize
    }

    /// Atomically designates a new keeper, protecting it from deletion and re-enabling
    /// selection on the previous keeper copy.
    public mutating func setKeeper(id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        for index in items.indices {
            if items[index].id == id {
                items[index].isKeeper = true
                items[index].isSelected = false
            } else {
                let wasKeeper = items[index].isKeeper
                items[index].isKeeper = false
                if wasKeeper {
                    items[index].isSelected = true
                }
            }
        }
    }
}

public struct DuplicatesView: View {
    @ObservedObject private var coordinator = NavigationCoordinator.shared

    @State private var clusters: [DuplicateCluster] = []
    @State private var isScanning: Bool = false
    @State private var scanPath: URL
    @State private var statusMessage: String?
    @State private var showConfirmSheet: Bool = false
    @State private var previewURL: URL? = nil
    @State private var comparingCluster: DuplicateCluster? = nil

    public init(initialFolder: URL? = nil) {
        let defaultURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        self._scanPath = State(initialValue: initialFolder ?? defaultURL)
    }

    public var totalReclaimable: Int64 {
        clusters.reduce(0) { $0 + $1.reclaimableSize }
    }

    public var totalSelectedCount: Int {
        clusters.flatMap { $0.items }.filter { $0.isSelected && !$0.isKeeper }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duplicate Finder")
                        .font(.system(size: 22, weight: .bold))
                    Text("Cryptographic SHA-256 detection with interactive keeper protection")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Folder Selection & Scan Trigger
                HStack(spacing: 8) {
                    folderPickerMenu

                    Button {
                        startScan()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isScanning ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                                .rotationEffect(Angle(degrees: isScanning ? 360 : 0))
                                .animation(isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isScanning)
                            Text(isScanning ? "Scanning..." : "Scan Duplicates")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning)
                }
            }
            .padding(20)

            Divider()

            // Summary Bar
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Identified Duplicates")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(clusters.count) Groups")
                        .font(.system(size: 15, weight: .bold))
                }

                Divider().frame(height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected for Removal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(totalSelectedCount) files (\(ByteCountFormatter.string(fromByteCount: totalReclaimable, countStyle: .file)))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(totalSelectedCount > 0 ? .orange : .primary)
                }

                Spacer()

                if totalSelectedCount > 0 {
                    Button(role: .destructive) {
                        showConfirmSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Trash \(totalSelectedCount) Duplicates")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.04))

            Divider()

            if isScanning {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Hashing candidate files in '\(scanPath.lastPathComponent)' with SHA-256...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if clusters.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Duplicates Found")
                        .font(.system(size: 16, weight: .semibold))
                    Text("No duplicate files found in '\(scanPath.path)'. Select another folder to scan.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Button("Select Another Folder...") {
                        selectCustomFolder()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach($clusters) { $cluster in
                            clusterCard(for: $cluster)
                        }
                    }
                    .padding(20)
                }
            }

            if let status = statusMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
            }
        }
        .quickLookPreview($previewURL)
        .sheet(item: $comparingCluster) { cluster in
            DuplicateComparisonSheet(
                cluster: cluster,
                onDesignateKeeper: { newKeeperId in
                    if let index = clusters.firstIndex(where: { $0.id == cluster.id }) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            clusters[index].setKeeper(id: newKeeperId)
                        }
                    }
                },
                onQuickLook: { url in
                    previewURL = url
                }
            )
        }
        .confirmationDialog(
            "Safely Move Duplicates to Trash?",
            isPresented: $showConfirmSheet,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                trashSelectedDuplicates()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move \(totalSelectedCount) duplicate files (\(ByteCountFormatter.string(fromByteCount: totalReclaimable, countStyle: .file))) to your macOS Trash. The original keeper copy will be untouched. This action can be undone via Approvals & History.")
        }
        .onAppear {
            if let target = coordinator.duplicateScanFolder {
                self.scanPath = target
                if clusters.isEmpty {
                    startScan()
                }
            }
        }
        .onChange(of: coordinator.duplicateScanFolder) { _, newFolder in
            if let folder = newFolder {
                updateScanPath(to: folder)
            }
        }
    }

    private var folderPickerMenu: some View {
        Menu {
            Button {
                updateScanPath(to: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()))
            } label: {
                Label("Downloads (~/Downloads)", systemImage: "arrow.down.circle")
            }

            Button {
                updateScanPath(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()))
            } label: {
                Label("Documents (~/Documents)", systemImage: "doc")
            }

            Button {
                updateScanPath(to: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()))
            } label: {
                Label("Desktop (~/Desktop)", systemImage: "menubar.dock.rectangle")
            }

            Button {
                updateScanPath(to: URL(fileURLWithPath: NSHomeDirectory()))
            } label: {
                Label("Home Folder (~)", systemImage: "house")
            }

            Divider()

            Button {
                selectCustomFolder()
            } label: {
                Label("Choose Custom Folder...", systemImage: "folder.badge.plus")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                Text(scanPath.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
        .help("Current scan folder: \(scanPath.path)")
    }

    @ViewBuilder
    private func clusterCard(for cluster: Binding<DuplicateCluster>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.blue)
                Text(cluster.wrappedValue.items.first?.filename ?? "Unknown")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(cluster.wrappedValue.items.count) copies · \(ByteCountFormatter.string(fromByteCount: cluster.wrappedValue.singleFileSize, countStyle: .file)) each")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button {
                    comparingCluster = cluster.wrappedValue
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.split.2x1")
                        Text("Compare")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            ForEach(cluster.items) { $item in
                HStack(spacing: 12) {
                    if item.isKeeper {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 15))
                            .help("Original keeper file (protected from removal)")
                    } else {
                        Toggle("", isOn: $item.isSelected)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if item.isKeeper {
                                HStack(spacing: 3) {
                                    Image(systemName: "shield.fill")
                                        .font(.system(size: 8))
                                    Text("KEEPER")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                            } else {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        cluster.wrappedValue.setKeeper(id: item.id)
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "shield")
                                            .font(.system(size: 8))
                                        Text("Make Keeper")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.08))
                                    .foregroundColor(.secondary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("Make this copy the protected keeper")
                            }
                        }

                        Text("Modified \(item.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        previewURL = item.url
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.borderless)
                    .help("Quick Look Preview (Space)")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(item.isKeeper ? Color.green.opacity(0.04) : Color.clear)
                .cornerRadius(6)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    private func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.directoryURL = scanPath
        if panel.runModal() == .OK, let url = panel.url {
            updateScanPath(to: url)
        }
    }

    private func updateScanPath(to url: URL) {
        self.scanPath = url
        startScan()
    }

    private func startScan() {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = nil
        let targetPath = scanPath

        Task.detached(priority: .userInitiated) {
            do {
                let groups = try SystemScanner.shared.findDuplicates(in: targetPath, minFileSize: 512)
                var resultClusters: [DuplicateCluster] = []

                for group in groups {
                    let sortedFiles = group.files.sorted { $0.modificationDate < $1.modificationDate }
                    var items: [DuplicateGroupItem] = []

                    for (idx, scanned) in sortedFiles.enumerated() {
                        let isKeeper = (idx == 0)
                        items.append(DuplicateGroupItem(
                            id: scanned.id,
                            item: scanned,
                            isKeeper: isKeeper,
                            isSelected: !isKeeper
                        ))
                    }

                    resultClusters.append(DuplicateCluster(
                        id: group.hash,
                        items: items,
                        singleFileSize: group.fileSize
                    ))
                }

                await MainActor.run {
                    self.clusters = resultClusters
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.statusMessage = "Scan error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func trashSelectedDuplicates() {
        let targets = clusters.flatMap { $0.items }.filter { $0.isSelected && !$0.isKeeper }
        guard !targets.isEmpty else { return }

        var successCount = 0
        var freedBytes: Int64 = 0
        var failures: [String] = []

        for target in targets {
            do {
                let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(
                    at: target.url,
                    reason: "Duplicate removal (keeper copy preserved)"
                )
                let record = OperationRecord(
                    id: UUID(),
                    timestamp: Date(),
                    actionType: .moveToTrash,
                    sourcePath: target.path,
                    destinationPath: trashedURL.path,
                    fileSize: target.size,
                    reason: "Duplicate removal (keeper copy preserved)",
                    isRolledBack: false
                )
                RollbackLedger.shared.recordOperation(record)
                successCount += 1
                freedBytes += target.size
            } catch {
                failures.append("\(target.filename): \(error.localizedDescription)")
            }
        }

        startScan()
        if failures.isEmpty {
            statusMessage = "Successfully moved \(successCount) duplicate files to Trash (\(ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)) freed)."
        } else {
            statusMessage = "Moved \(successCount) duplicates to Trash. Failed to move \(failures.count) files."
        }
    }
}

// MARK: - Side-by-Side Comparison Sheet
public struct DuplicateComparisonSheet: View {
    public let cluster: DuplicateCluster
    public let onDesignateKeeper: (String) -> Void
    public let onQuickLook: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCandidateIndex: Int = 0

    public init(
        cluster: DuplicateCluster,
        onDesignateKeeper: @escaping (String) -> Void,
        onQuickLook: @escaping (URL) -> Void
    ) {
        self.cluster = cluster
        self.onDesignateKeeper = onDesignateKeeper
        self.onQuickLook = onQuickLook
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Side-by-Side Duplicate Comparison")
                        .font(.system(size: 16, weight: .bold))
                    Text("Exact SHA-256 match (\(ByteCountFormatter.string(fromByteCount: cluster.singleFileSize, countStyle: .file)))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            let candidates = cluster.items.filter { !$0.isKeeper }
            let keeper = cluster.items.first { $0.isKeeper } ?? cluster.items.first

            HStack(spacing: 16) {
                // Left: Keeper
                if let keeper = keeper {
                    comparisonColumn(item: keeper, isKeeper: true)
                }

                Divider()

                // Right: Candidate Duplicate
                if !candidates.isEmpty {
                    let candidate = candidates[min(selectedCandidateIndex, candidates.count - 1)]
                    comparisonColumn(item: candidate, isKeeper: false)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 380)
    }

    @ViewBuilder
    private func comparisonColumn(item: DuplicateGroupItem, isKeeper: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isKeeper {
                    Label("Designated Keeper", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Label("Duplicate Candidate", systemImage: "doc.on.doc")
                        .foregroundColor(.blue)
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Filename: \(item.filename)")
                    .font(.system(size: 12, weight: .semibold))
                Text("Location: \(item.path)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("Modified: \(item.date.formatted(date: .complete, time: .standard))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(8)

            HStack(spacing: 8) {
                Button {
                    onQuickLook(item.url)
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .buttonStyle(.bordered)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if !isKeeper {
                    Spacer()
                    Button {
                        onDesignateKeeper(item.id)
                        dismiss()
                    } label: {
                        Label("Make Keeper", systemImage: "shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
