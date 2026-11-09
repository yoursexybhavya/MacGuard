import SwiftUI
import AppKit
import QuickLook

public enum OrganizerTab: String, CaseIterable, Identifiable {
    case files = "File Categorization"
    case folders = "Folder Consolidation"

    public var id: String { rawValue }
}

public struct OrganizerView: View {
    @State private var targetDirectory: URL
    @State private var selectedTab: OrganizerTab = .files

    // File Proposals
    @State private var proposals: [OrganizationProposal] = []
    @State private var selectedProposalIDs: Set<UUID> = []

    // Folder Merges
    @State private var folderMerges: [FolderMergeProposal] = []
    @State private var selectedMergeIDs: Set<UUID> = []

    @State private var isAnalyzing: Bool = false
    @State private var showConfirmSheet: Bool = false
    @State private var showMergeConfirmSheet: Bool = false
    @State private var executionStatusMessage: String?
    @State private var previewURL: URL? = nil

    public init(initialFolder: URL? = nil) {
        let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        self._targetDirectory = State(initialValue: initialFolder ?? defaultURL)
    }

    public var selectedProposalsSize: Int64 {
        proposals.filter { selectedProposalIDs.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intelligent File Organizer")
                        .font(.system(size: 22, weight: .bold))
                    Text("Group loose files and consolidate redundant folder structures safely")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Folder Selection & Action
                HStack(spacing: 8) {
                    folderPickerMenu

                    Button("Analyze") {
                        analyzeFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing)
                }
            }
            .padding(20)

            Divider()

            // Mode Selector Tabs
            HStack {
                Picker("Mode", selection: $selectedTab) {
                    Text("File Categorization (\(proposals.count))").tag(OrganizerTab.files)
                    Text("Folder Consolidation (\(folderMerges.count))").tag(OrganizerTab.folders)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.02))

            Divider()

            if isAnalyzing {
                Spacer()
                ProgressView("Analyzing folder structure & formulating layout...")
                Spacer()
            } else {
                switch selectedTab {
                case .files:
                    fileCategorizationView
                case .folders:
                    folderConsolidationView
                }
            }

            if let msg = executionStatusMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
            }
        }
        .quickLookPreview($previewURL)
        .onAppear {
            analyzeFolder()
        }
        // Confirmation for File Organization
        .sheet(isPresented: $showConfirmSheet) {
            confirmMoveSheet
        }
        // Confirmation for Folder Consolidation
        .sheet(isPresented: $showMergeConfirmSheet) {
            confirmMergeSheet
        }
    }

    // MARK: - Folder Picker Menu
    private var folderPickerMenu: some View {
        Menu {
            Button {
                updateTargetFolder(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
            } label: {
                Label("Downloads (~/Downloads)", systemImage: "arrow.down.circle")
            }

            Button {
                updateTargetFolder(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
            } label: {
                Label("Documents (~/Documents)", systemImage: "doc")
            }

            Button {
                updateTargetFolder(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
            } label: {
                Label("Desktop (~/Desktop)", systemImage: "menubar.dock.rectangle")
            }

            Button {
                updateTargetFolder(to: FileManager.default.homeDirectoryForCurrentUser)
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
                Text(targetDirectory.lastPathComponent)
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
        .help("Target folder: \(targetDirectory.path)")
    }

    // MARK: - Tab 1: File Categorization View
    @ViewBuilder
    private var fileCategorizationView: some View {
        if proposals.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No Loose Files Need Organization")
                    .font(.system(size: 16, weight: .semibold))
                Text("Folder '\(targetDirectory.lastPathComponent)' has no unorganized loose files.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button("Re-analyze Folder") {
                    analyzeFolder()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        } else {
            VStack(spacing: 0) {
                // Summary Banner
                HStack {
                    Button(selectedProposalIDs.count == proposals.count ? "Deselect All" : "Select All") {
                        if selectedProposalIDs.count == proposals.count {
                            selectedProposalIDs.removeAll()
                        } else {
                            selectedProposalIDs = Set(proposals.map(\.id))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedProposalIDs.count) of \(proposals.count) Files Selected")
                            .font(.system(size: 13, weight: .bold))
                        Text("Selected size: \(ByteCountFormatter.string(fromByteCount: selectedProposalsSize, countStyle: .file)) • Conflict-free naming")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button {
                        showConfirmSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Execute Selected (\(selectedProposalIDs.count))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedProposalIDs.isEmpty)
                }
                .padding(14)
                .background(Color.blue.opacity(0.06))

                Divider()

                // Proposals List
                List(proposals) { p in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { selectedProposalIDs.contains(p.id) },
                            set: { isChecked in
                                if isChecked {
                                    selectedProposalIDs.insert(p.id)
                                } else {
                                    selectedProposalIDs.remove(p.id)
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                        Image(systemName: p.category.systemIcon)
                            .foregroundColor(.blue)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.fileName)
                                .font(.system(size: 12, weight: .semibold))
                            HStack(spacing: 4) {
                                Text(p.sourcePath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                Text(p.destinationPath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundColor(.blue)
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(p.formattedSize)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Button {
                            previewURL = p.sourceURL
                        } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Quick Look Preview")

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([p.sourceURL])
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reveal in Finder")
                    }
                    .opacity(selectedProposalIDs.contains(p.id) ? 1.0 : 0.5)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Tab 2: Folder Consolidation View
    @ViewBuilder
    private var folderConsolidationView: some View {
        if folderMerges.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("No Redundant Folders Detected")
                    .font(.system(size: 16, weight: .semibold))
                Text("All subdirectories in '\(targetDirectory.lastPathComponent)' follow canonical naming conventions.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            VStack(spacing: 0) {
                // Summary Banner
                HStack {
                    Button(selectedMergeIDs.count == folderMerges.count ? "Deselect All" : "Select All") {
                        if selectedMergeIDs.count == folderMerges.count {
                            selectedMergeIDs.removeAll()
                        } else {
                            selectedMergeIDs = Set(folderMerges.map(\.id))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedMergeIDs.count) of \(folderMerges.count) Folder Consolidations Selected")
                            .font(.system(size: 13, weight: .bold))
                        Text("Safely merges duplicate folders and relocates empty sources to Trash.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button {
                        showMergeConfirmSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.gearshape.fill")
                            Text("Consolidate Selected (\(selectedMergeIDs.count))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(selectedMergeIDs.isEmpty)
                }
                .padding(14)
                .background(Color.orange.opacity(0.08))

                Divider()

                List(folderMerges) { merge in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { selectedMergeIDs.contains(merge.id) },
                                set: { isChecked in
                                    if isChecked {
                                        selectedMergeIDs.insert(merge.id)
                                    } else {
                                        selectedMergeIDs.remove(merge.id)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                            Image(systemName: "folder.fill")
                                .foregroundColor(.secondary)
                            Text(merge.sourceName)
                                .font(.system(size: 13, weight: .bold))

                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)

                            Image(systemName: "folder.badge.gearshape.fill")
                                .foregroundColor(.blue)
                            Text(merge.destinationName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.blue)

                            Spacer()

                            Text("\(merge.itemCount) items · \(merge.formattedSize)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Text(merge.reason)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.leading, 32)
                    }
                    .opacity(selectedMergeIDs.contains(merge.id) ? 1.0 : 0.5)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Confirmation Sheets
    private var confirmMoveSheet: some View {
        VStack(spacing: 16) {
            Text("Confirm File Organization")
                .font(.system(size: 16, weight: .bold))
            Text("MacGuard will move \(selectedProposalIDs.count) selected files into categorized folders in '\(targetDirectory.lastPathComponent)'. Every move is logged in the Rollback Ledger and can be undone at any time.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancel") {
                    showConfirmSheet = false
                }
                Spacer()
                Button("Approve and Move Files") {
                    executeSelectedProposals()
                    showConfirmSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 440)
    }

    private var confirmMergeSheet: some View {
        VStack(spacing: 16) {
            Text("Confirm Folder Consolidation")
                .font(.system(size: 16, weight: .bold))
            Text("MacGuard will consolidate \(selectedMergeIDs.count) redundant folders into canonical structures. All items will be relocated safely without overwriting. Empty source directories will be moved to macOS Trash (Zero Permanent Deletion).")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancel") {
                    showMergeConfirmSheet = false
                }
                Spacer()
                Button("Approve and Consolidate") {
                    executeSelectedMerges()
                    showMergeConfirmSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 440)
    }

    // MARK: - Actions
    private func updateTargetFolder(to url: URL) {
        self.targetDirectory = url
        analyzeFolder()
    }

    private func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.directoryURL = targetDirectory
        if panel.runModal() == .OK, let url = panel.url {
            updateTargetFolder(to: url)
        }
    }

    private func analyzeFolder() {
        isAnalyzing = true
        executionStatusMessage = nil
        let target = targetDirectory

        Task.detached(priority: .userInitiated) {
            let plannedProposals = (try? FileOrganizer.shared.planOrganization(for: target)) ?? []
            let plannedMerges = FileOrganizer.shared.planFolderConsolidation(for: target)

            await MainActor.run {
                self.proposals = plannedProposals
                self.selectedProposalIDs = Set(plannedProposals.map(\.id))

                self.folderMerges = plannedMerges
                self.selectedMergeIDs = Set(plannedMerges.map(\.id))

                self.isAnalyzing = false
            }
        }
    }

    private func executeSelectedProposals() {
        let toExecute = proposals.filter { selectedProposalIDs.contains($0.id) }
        guard !toExecute.isEmpty else { return }

        do {
            try FileOrganizer.shared.executeProposals(toExecute)
            executionStatusMessage = "Successfully organized \(toExecute.count) files. Reversible at any time."
            analyzeFolder()
        } catch {
            executionStatusMessage = "Organization failed: \(error.localizedDescription)"
        }
    }

    private func executeSelectedMerges() {
        let toExecute = folderMerges.filter { selectedMergeIDs.contains($0.id) }
        guard !toExecute.isEmpty else { return }

        do {
            try FileOrganizer.shared.executeFolderMerges(toExecute)
            executionStatusMessage = "Successfully consolidated \(toExecute.count) folders. Empty folders moved to Trash."
            analyzeFolder()
        } catch {
            executionStatusMessage = "Folder consolidation failed: \(error.localizedDescription)"
        }
    }
}
