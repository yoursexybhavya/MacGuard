import SwiftUI
import AppKit

public struct OrganizerView: View {
    @State private var targetDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State private var proposals: [OrganizationProposal] = []
    @State private var isAnalyzing: Bool = false
    @State private var showConfirmSheet: Bool = false
    @State private var executionStatusMessage: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intelligent File Organizer")
                        .font(.system(size: 22, weight: .bold))
                    Text("Group files by category without overwriting existing data")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Folder Picker Shortcut
                HStack(spacing: 8) {
                    Text("Folder:")
                        .font(.system(size: 12, weight: .medium))
                    Button(targetDirectory.lastPathComponent) {
                        selectCustomFolder()
                    }
                    .buttonStyle(.bordered)

                    Button("Analyze") {
                        analyzeFolder()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)

            Divider()

            if isAnalyzing {
                Spacer()
                ProgressView("Analyzing folder structure & formulating layout...")
                Spacer()
            } else if proposals.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Organization Needed or Folder is Clean")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Selected folder '\(targetDirectory.lastPathComponent)' has no unorganized loose files.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Analyze Downloads Folder") {
                        targetDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                        analyzeFolder()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            } else {
                VStack(spacing: 0) {
                    // Summary Banner
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(proposals.count) Files Ready for Organization")
                                .font(.system(size: 14, weight: .bold))
                            let totalSize = proposals.reduce(0) { $0 + $1.fileSize }
                            Text("Total size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)) • Safe conflict-free naming")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            showConfirmSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Execute Plan (\(proposals.count))")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(14)
                    .background(Color.blue.opacity(0.08))

                    // Proposals Table
                    List(proposals) { p in
                        HStack(spacing: 12) {
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
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let msg = executionStatusMessage {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.system(size: 12))
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
            }
        }
        .onAppear {
            analyzeFolder()
        }
        .sheet(isPresented: $showConfirmSheet) {
            VStack(spacing: 16) {
                Text("Confirm Organization Execution")
                    .font(.system(size: 16, weight: .bold))
                Text("MacGuard will move \(proposals.count) files into categorized folders in '\(targetDirectory.lastPathComponent)'. Every move is reversible through the Rollback Ledger.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    Button("Cancel") {
                        showConfirmSheet = false
                    }
                    Spacer()
                    Button("Approve and Move Files") {
                        executeProposals()
                        showConfirmSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 10)
            }
            .padding(20)
            .frame(width: 440)
        }
    }

    private func analyzeFolder() {
        isAnalyzing = true
        executionStatusMessage = nil
        let target = targetDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let res = (try? FileOrganizer.shared.planOrganization(for: target)) ?? []
            DispatchQueue.main.async {
                self.proposals = res
                self.isAnalyzing = false
            }
        }
    }

    private func executeProposals() {
        do {
            try FileOrganizer.shared.executeProposals(proposals)
            executionStatusMessage = "Successfully organized \(proposals.count) files. Reversible at any time."
            analyzeFolder()
        } catch {
            executionStatusMessage = "Organization failed: \(error.localizedDescription)"
        }
    }

    private func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            targetDirectory = url
            analyzeFolder()
        }
    }
}
