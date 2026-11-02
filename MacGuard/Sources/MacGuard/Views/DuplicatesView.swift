import SwiftUI
import AppKit

public struct DuplicateGroupItem: Identifiable, Sendable {
    public let id: String
    public let item: ScannedItem
    public let isKeeper: Bool
    public var isSelected: Bool

    public var url: URL { item.url }
    public var size: Int64 { item.size }
    public var filename: String { item.name }
    public var path: String { item.path }
    public var date: Date { item.modificationDate }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
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
}

public struct DuplicatesView: View {
    @State private var clusters: [DuplicateCluster] = []
    @State private var isScanning: Bool = false
    @State private var scanPath: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    @State private var statusMessage: String?
    @State private var showConfirmSheet: Bool = false

    public init() {}

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
                    Text("Cryptographic SHA-256 detection with automatic keeper protection")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

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
                    Text("Hashing candidate files with SHA-256...")
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
                    Text("Select a folder and click Scan Duplicates to discover exact duplicate files.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
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
            if clusters.isEmpty {
                startScan()
            }
        }
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
            }

            Divider()

            ForEach(cluster.items) { $item in
                HStack(spacing: 12) {
                    if item.isKeeper {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .help("Original keeper file (protected from removal)")
                    } else {
                        Toggle("", isOn: $item.isSelected)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if item.isKeeper {
                                Text("KEEPER")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .clipShape(Capsule())
                            }
                        }

                        Text("Modified \(item.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
                .padding(.vertical, 4)
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
                    // Sort files by modification date (oldest first is keeper)
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

        for target in targets {
            do {
                let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: target.url)
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
                print("Failed to trash duplicate at \(target.path): \(error)")
            }
        }

        startScan()
        statusMessage = "Successfully moved \(successCount) duplicate files to Trash (\(ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)) freed)."
    }
}
