import SwiftUI
import AppKit

public enum AssistantActiveSheet: Identifiable {
    case organization(proposals: [OrganizationProposal], folderMerges: [FolderMergeProposal])
    case cleanup([CleanupTarget])
    case duplicates([DuplicateGroup])

    public var id: String {
        switch self {
        case .organization(let p, let m):
            return "org_\(p.count)_\(m.count)"
        case .cleanup(let items):
            return "clean_\(items.count)"
        case .duplicates(let items):
            return "dup_\(items.count)"
        }
    }
}

public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let isUser: Bool
    public let text: String
    public let result: AIExecutionResult?
    public let timestamp: Date

    public init(id: UUID = UUID(), isUser: Bool, text: String, result: AIExecutionResult? = nil) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.result = result
        self.timestamp = Date()
    }
}

public struct AssistantView: View {
    public var onNavigate: ((NavigationSection) -> Void)?

    @State private var messages: [ChatMessage] = [
        ChatMessage(
            isUser: false,
            text: "Hello! I am MacGuard, your specialized local maintenance assistant. Ask me to organize your Downloads, merge messy folders, clean temporary caches, analyze disk space, or run a full system audit."
        )
    ]
    @State private var currentInput: String = ""
    @State private var isProcessing: Bool = false
    @State private var activeSheet: AssistantActiveSheet? = nil
    @State private var trashedFileNotification: String? = nil

    public init(onNavigate: ((NavigationSection) -> Void)? = nil) {
        self.onNavigate = onNavigate
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.purple)
                    Text("AI Maintenance Assistant")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
                Text("Powered by MacGuard AI Specialized Model (Local Metal)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.05))

            if let notification = trashedFileNotification {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(notification)
                        .font(.system(size: 12))
                    Spacer()
                    Button {
                        trashedFileNotification = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
            }

            Divider()

            // Chat Messages Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { msg in
                            ChatBubbleView(
                                message: msg,
                                onOpenOrganizationSheet: { proposals, folderMerges in
                                    self.activeSheet = .organization(proposals: proposals, folderMerges: folderMerges)
                                },
                                onOpenCleanupSheet: { cleanups in
                                    self.activeSheet = .cleanup(cleanups)
                                },
                                onOpenDuplicateSheet: { duplicates in
                                    self.activeSheet = .duplicates(duplicates)
                                },
                                onTrashFile: { item in
                                    trashSingleFile(item)
                                },
                                onNavigate: onNavigate,
                                onTriggerPrompt: { prompt in
                                    sendQuery(prompt)
                                }
                            )
                        }

                        if isProcessing {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Analyzing filesystem and running neural intent dispatch...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .id("loadingIndicator")
                        }
                    }
                    .padding(20)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Suggested Action Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SuggestionChip(icon: "folder.badge.gearshape", text: "Organize my Downloads folder") {
                        sendQuery("Organize my Downloads folder")
                    }
                    SuggestionChip(icon: "folder.fill.badge.plus", text: "Consolidate duplicate folders") {
                        sendQuery("consolidate duplicate folders in Downloads")
                    }
                    SuggestionChip(icon: "trash", text: "Find unnecessary files taking up space") {
                        sendQuery("Find unnecessary files taking up space")
                    }
                    SuggestionChip(icon: "chart.bar.xaxis", text: "Show largest files on my Mac") {
                        sendQuery("Show me the largest files on my Mac")
                    }
                    SuggestionChip(icon: "doc.on.doc", text: "Find duplicate files") {
                        sendQuery("Find duplicate files")
                    }
                    SuggestionChip(icon: "shield.checkered", text: "Full system audit") {
                        sendQuery("full")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Input Bar
            HStack(spacing: 12) {
                TextField("Ask MacGuard to organize, clean, or inspect...", text: $currentInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                    .onSubmit {
                        submitInput()
                    }

                Button {
                    submitInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .disabled(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.04))
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .organization(let proposals, let folderMerges):
                OrganizationApprovalSheet(
                    proposals: proposals,
                    folderMerges: folderMerges,
                    onApprove: { approvedProposals, approvedMerges in
                        do {
                            if !approvedMerges.isEmpty {
                                try FileOrganizer.shared.executeFolderMerges(approvedMerges)
                            }
                            if !approvedProposals.isEmpty {
                                try FileOrganizer.shared.executeProposals(approvedProposals)
                            }
                            var parts: [String] = []
                            if !approvedMerges.isEmpty {
                                parts.append("consolidated \(approvedMerges.count) redundant folders")
                            }
                            if !approvedProposals.isEmpty {
                                parts.append("organized \(approvedProposals.count) files")
                            }
                            let text = parts.joined(separator: " and ")
                            messages.append(ChatMessage(
                                isUser: false,
                                text: "Successfully \(text) into a clean, unified structure. All changes recorded in the Rollback Ledger."
                            ))
                        } catch {
                            messages.append(ChatMessage(
                                isUser: false,
                                text: "Encountered an issue during organization: \(error.localizedDescription)"
                            ))
                        }
                        activeSheet = nil
                    },
                    onCancel: {
                        activeSheet = nil
                    }
                )

            case .cleanup(let targets):
                CleanupApprovalSheet(
                    targets: targets,
                    onApprove: { approvedTargets in
                        do {
                            let totalSize = approvedTargets.reduce(0) { $0 + $1.size }
                            let formatted = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
                            try CleanupEngine.shared.executeCleanup(targets: approvedTargets)
                            messages.append(ChatMessage(
                                isUser: false,
                                text: "Safely moved \(approvedTargets.count) items (\(formatted)) to macOS Trash. You can undo this anytime from Approvals & History."
                            ))
                        } catch {
                            messages.append(ChatMessage(
                                isUser: false,
                                text: "Cleanup error: \(error.localizedDescription)"
                            ))
                        }
                        activeSheet = nil
                    },
                    onCancel: {
                        activeSheet = nil
                    }
                )

            case .duplicates(let duplicates):
                DuplicateApprovalSheet(
                    duplicates: duplicates,
                    onApprove: { removedCount, freedBytes in
                        let formatted = ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)
                        messages.append(ChatMessage(
                            isUser: false,
                            text: "Safely relocated \(removedCount) duplicate copies (\(formatted)) to macOS Trash. Originals were preserved intact."
                        ))
                        activeSheet = nil
                    },
                    onCancel: {
                        activeSheet = nil
                    }
                )
            }
        }
    }

    private func submitInput() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentInput = ""
        sendQuery(trimmed)
    }

    private func sendQuery(_ query: String) {
        messages.append(ChatMessage(isUser: true, text: query))
        isProcessing = true

        Task {
            let result = await MacGuardAIEngine.shared.processUserQuery(query)
            await MainActor.run {
                switch result {
                case .messageOnly(let msg):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                case .organizationPlan(let msg, _, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                case .cleanupPlan(let msg, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                case .duplicatePlan(let msg, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                case .storageAnalysis(let msg, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                case .fullAudit(let msg, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                }
                isProcessing = false
            }
        }
    }

    private func trashSingleFile(_ item: ScannedItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            RollbackLedger.shared.recordOperation(OperationRecord(
                actionType: .moveToTrash,
                sourcePath: item.path,
                fileSize: item.size,
                reason: "User quick-trashed large file from AI Assistant: \(item.name)"
            ))
            withAnimation {
                trashedFileNotification = "Safely moved '\(item.name)' to macOS Trash (\(item.formattedSize) freed)."
            }
        } catch {
            withAnimation {
                trashedFileNotification = "Failed to trash file: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Chat Bubble View
struct ChatBubbleView: View {
    let message: ChatMessage
    let onOpenOrganizationSheet: ([OrganizationProposal], [FolderMergeProposal]) -> Void
    let onOpenCleanupSheet: ([CleanupTarget]) -> Void
    let onOpenDuplicateSheet: ([DuplicateGroup]) -> Void
    let onTrashFile: (ScannedItem) -> Void
    let onNavigate: ((NavigationSection) -> Void)?
    let onTriggerPrompt: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser {
                Spacer()
                Text(message.text)
                    .font(.system(size: 13))
                    .padding(12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            } else {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey(message.text))
                        .font(.system(size: 13))
                        .foregroundColor(.primary)

                    // Embedded Interactive Action Cards
                    if let result = message.result {
                        switch result {
                        case .organizationPlan(_, let proposals, let folderMerges):
                            if !proposals.isEmpty || !folderMerges.isEmpty {
                                ProposalActionCard(
                                    proposals: proposals,
                                    folderMerges: folderMerges,
                                    onReview: {
                                        onOpenOrganizationSheet(proposals, folderMerges)
                                    }
                                )
                            }

                        case .cleanupPlan(_, let candidates):
                            if !candidates.isEmpty {
                                CleanupActionCard(
                                    candidates: candidates,
                                    onReview: {
                                        onOpenCleanupSheet(candidates)
                                    }
                                )
                            }

                        case .duplicatePlan(_, let duplicates):
                            if !duplicates.isEmpty {
                                DuplicateActionCard(
                                    duplicates: duplicates,
                                    onReview: {
                                        onOpenDuplicateSheet(duplicates)
                                    }
                                )
                            }

                        case .storageAnalysis(_, let overview):
                            StorageActionCard(
                                overview: overview,
                                onTrashFile: onTrashFile,
                                onNavigate: onNavigate,
                                onCleanInstallers: {
                                    onTriggerPrompt("Clean safe installers and temporary caches")
                                }
                            )

                        case .fullAudit(_, let summary):
                            FullAuditCard(
                                summary: summary,
                                onReviewCleanup: {
                                    onOpenCleanupSheet(summary.cleanupCandidates)
                                },
                                onReviewDuplicates: {
                                    onOpenDuplicateSheet(summary.duplicates)
                                },
                                onReviewOrganization: {
                                    onTriggerPrompt("Organize my Downloads folder")
                                },
                                onNavigate: onNavigate
                            )

                        case .messageOnly:
                            EmptyView()
                        }
                    }
                }
                .padding(14)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(14)
                Spacer()
            }
        }
    }
}

// MARK: - Storage Action Card (Large Files & Capacity)
struct StorageActionCard: View {
    let overview: StorageOverview
    let onTrashFile: (ScannedItem) -> Void
    let onNavigate: ((NavigationSection) -> Void)?
    let onCleanInstallers: () -> Void

    @State private var showAllFiles: Bool = false
    @State private var fileToConfirmTrash: ScannedItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Volume Header & Free Space Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive.fill")
                            .foregroundColor(.blue)
                        Text("Macintosh HD (APFS)")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Spacer()
                    Text("\(overview.formattedAvailable) Free")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                    Text("of \(overview.formattedTotal)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                ProgressView(value: overview.usagePercentage)
                    .tint(overview.usagePercentage > 0.85 ? .red : (overview.usagePercentage > 0.70 ? .orange : .blue))
            }

            // Category Distribution Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FileCategory.allCases, id: \.self) { cat in
                        let bytes = overview.categoryBreakdown[cat] ?? 0
                        if bytes > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: cat.systemIcon)
                                    .font(.system(size: 10))
                                Text(cat.rawValue.components(separatedBy: " & ").first ?? cat.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                }
            }

            Divider()

            // Largest Files Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.indigo)
                    Text("Top Largest Files (\(overview.largestFiles.count) Indexed)")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Button(showAllFiles ? "Show Top 5" : "Show All \(overview.largestFiles.count)") {
                        withAnimation {
                            showAllFiles.toggle()
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }

                let displayFiles = showAllFiles ? overview.largestFiles : Array(overview.largestFiles.prefix(5))

                VStack(spacing: 6) {
                    ForEach(displayFiles) { item in
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(categoryColor(for: item.category).opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Image(systemName: item.category.systemIcon)
                                    .font(.system(size: 12))
                                    .foregroundColor(categoryColor(for: item.category))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(item.path)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Text(item.formattedSize)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)

                            // 1-Click Reveal in Finder
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")

                            // 1-Click Move to Trash
                            Button {
                                fileToConfirmTrash = item
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.8))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("Move to Trash")
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
            }

            // Quick Actions Footer
            HStack(spacing: 10) {
                if let onNavigate = onNavigate {
                    Button {
                        onNavigate(.storage)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.pie.fill")
                            Text("Open Storage Analyzer")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: onCleanInstallers) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Clean Disposable Installers")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.blue.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
        .confirmationDialog(
            "Move '\(fileToConfirmTrash?.name ?? "")' to Trash?",
            isPresented: Binding(
                get: { fileToConfirmTrash != nil },
                set: { if !$0 { fileToConfirmTrash = nil } }
            ),
            presenting: fileToConfirmTrash
        ) { item in
            Button("Move to Trash (\(item.formattedSize))", role: .destructive) {
                onTrashFile(item)
                fileToConfirmTrash = nil
            }
            Button("Cancel", role: .cancel) {
                fileToConfirmTrash = nil
            }
        } message: { item in
            Text("This file will be relocated to macOS Trash. This operation is recorded in the Rollback Ledger and can be undone.")
        }
    }

    private func categoryColor(for cat: FileCategory) -> Color {
        switch cat {
        case .installers: return .orange
        case .archives: return .purple
        case .documents: return .blue
        case .media: return .pink
        case .creative: return .indigo
        case .skills: return .mint
        case .academics: return .teal
        case .images: return .teal
        case .code: return .green
        case .caches: return .yellow
        case .junk: return .gray
        case .other: return .secondary
        }
    }
}

// MARK: - Proposal Action Card (File Organization & Folder Consolidation)
struct ProposalActionCard: View {
    let proposals: [OrganizationProposal]
    let folderMerges: [FolderMergeProposal]
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.blue)
                Text("Proposed Organization & Consolidation")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(proposals.count) files • \(folderMerges.count) merges")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.blue)
            }

            // Folder Consolidation Notice
            if !folderMerges.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Consolidate \(folderMerges.count) Redundant Sibling Folders:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }

                    ForEach(folderMerges.prefix(3)) { merge in
                        HStack(spacing: 4) {
                            Text(merge.sourceName)
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Text(merge.destinationName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.blue)
                            Spacer()
                            Text("\(merge.itemCount) items")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(4)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.06))
                .cornerRadius(6)
            }

            // Category pills
            let grouped = Dictionary(grouping: proposals, by: { $0.category })
            HStack(spacing: 6) {
                ForEach(Array(grouped.keys.prefix(4)), id: \.self) { cat in
                    let count = grouped[cat]?.count ?? 0
                    HStack(spacing: 3) {
                        Image(systemName: cat.systemIcon)
                            .font(.system(size: 9))
                        Text("\(cat.rawValue.components(separatedBy: " & ").first ?? cat.rawValue): \(count)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
            }

            // Preview 3 files
            VStack(spacing: 4) {
                ForEach(proposals.prefix(3)) { p in
                    HStack(spacing: 6) {
                        Text(p.fileName)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(p.proposedDestinationURL.deletingLastPathComponent().lastPathComponent)
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                        Spacer()
                        Text(p.formattedSize)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(4)
                }
            }

            Button(action: onReview) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Review & Approve Plan (\(proposals.count) files, \(folderMerges.count) merges)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Cleanup Action Card (Caches & Junk)
struct CleanupActionCard: View {
    let candidates: [CleanupTarget]
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "trash.fill")
                    .foregroundColor(.orange)
                Text("Proposed Safe Cleanup")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                let total = candidates.reduce(0) { $0 + $1.size }
                Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
            }

            Text("Discovered safe developer caches, system logs, disposable installers, and junk ready for Trash.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(candidates.prefix(3)) { target in
                    HStack {
                        Image(systemName: target.safetyTier == .safe ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(target.safetyTier == .safe ? .green : .orange)
                        Text(target.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(target.formattedSize)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(4)
                }
            }

            Button(action: onReview) {
                HStack {
                    Image(systemName: "shield.checkered")
                    Text("Review & Approve Cleanup")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Duplicate Action Card
struct DuplicateActionCard: View {
    let duplicates: [DuplicateGroup]
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.indigo)
                Text("Duplicate Files Detected")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                let wasted = duplicates.reduce(0) { $0 + $1.totalWastedSpace }
                Text(ByteCountFormatter.string(fromByteCount: wasted, countStyle: .file))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.indigo)
            }

            Text("Identified \(duplicates.count) sets of identical files matched cryptographically via SHA-256.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(duplicates.prefix(3)) { group in
                    HStack {
                        Text(group.files.first?.name ?? "Duplicate")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(group.files.count) copies • \(group.formattedWastedSpace) wasted")
                            .font(.system(size: 10))
                            .foregroundColor(.indigo)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(4)
                }
            }

            Button(action: onReview) {
                HStack {
                    Image(systemName: "doc.badge.arrow.up")
                    Text("Review & Clean Duplicates")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.indigo.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.indigo.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Full System Audit Card
struct FullAuditCard: View {
    let summary: FullAuditSummary
    let onReviewCleanup: () -> Void
    let onReviewDuplicates: () -> Void
    let onReviewOrganization: () -> Void
    let onNavigate: ((NavigationSection) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Reclaimable Badge
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    Text("MacGuard System Audit Report")
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
                Text("\(summary.formattedReclaimable) Reclaimable")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(6)
            }

            // 4 Module Diagnostic Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // 1. APFS Storage
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .foregroundColor(.blue)
                        Text("APFS Storage")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text("\(summary.storage.formattedAvailable) available of \(summary.storage.formattedTotal)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    ProgressView(value: summary.storage.usagePercentage)
                        .tint(.blue)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)

                // 2. Safe Cleanups
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.orange)
                        Text("Disposable Caches")
                            .font(.system(size: 11, weight: .bold))
                    }
                    let totalSize = summary.cleanupCandidates.reduce(0) { $0 + $1.size }
                    Text("\(summary.cleanupCandidates.count) targets • \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Button("Review Cleanups", action: onReviewCleanup)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)

                // 3. Duplicates
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "doc.on.doc.fill")
                            .foregroundColor(.indigo)
                        Text("Duplicate Files")
                            .font(.system(size: 11, weight: .bold))
                    }
                    let wasted = summary.duplicates.reduce(0) { $0 + $1.totalWastedSpace }
                    Text("\(summary.duplicates.count) clusters • \(ByteCountFormatter.string(fromByteCount: wasted, countStyle: .file)) wasted")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if !summary.duplicates.isEmpty {
                        Button("Review Duplicates", action: onReviewDuplicates)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)

                // 4. File Organization
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.teal)
                        Text("Downloads Folder")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text("\(summary.unorganizedFilesCount) files • \(summary.folderMergesCount) merges")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Button("Organize & Merge", action: onReviewOrganization)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Suggestion Chip
struct SuggestionChip: View {
    var icon: String? = nil
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(text)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Organization & Consolidation Approval Sheet
struct OrganizationApprovalSheet: View {
    let proposals: [OrganizationProposal]
    let folderMerges: [FolderMergeProposal]
    let onApprove: ([OrganizationProposal], [FolderMergeProposal]) -> Void
    let onCancel: () -> Void

    @State private var selectedProposalIDs: Set<UUID>
    @State private var selectedMergeIDs: Set<UUID>

    init(
        proposals: [OrganizationProposal],
        folderMerges: [FolderMergeProposal],
        onApprove: @escaping ([OrganizationProposal], [FolderMergeProposal]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.proposals = proposals
        self.folderMerges = folderMerges
        self.onApprove = onApprove
        self.onCancel = onCancel
        _selectedProposalIDs = State(initialValue: Set(proposals.map(\.id)))
        _selectedMergeIDs = State(initialValue: Set(folderMerges.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm Organization & Consolidation")
                        .font(.system(size: 16, weight: .bold))
                    Text("Consolidate redundant folders and group loose files. 100% reversible via Rollback Ledger.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Select All") {
                    selectedProposalIDs = Set(proposals.map(\.id))
                    selectedMergeIDs = Set(folderMerges.map(\.id))
                }
                .font(.system(size: 11))
            }

            List {
                // Section 1: Redundant Folders Consolidation
                if !folderMerges.isEmpty {
                    Section(header: Text("Redundant Folders Consolidation (\(folderMerges.count))").font(.system(size: 12, weight: .bold)).foregroundColor(.orange)) {
                        ForEach(folderMerges) { merge in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { selectedMergeIDs.contains(merge.id) },
                                    set: { if $0 { selectedMergeIDs.insert(merge.id) } else { selectedMergeIDs.remove(merge.id) } }
                                ))
                                .labelsHidden()

                                Image(systemName: "folder.fill.badge.plus")
                                    .font(.system(size: 13))
                                    .foregroundColor(.orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(merge.sourceName)
                                            .font(.system(size: 12, weight: .bold))
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Text(merge.destinationName)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.blue)
                                    }
                                    Text(merge.reason)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(merge.itemCount) items • \(merge.formattedSize)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)

                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([merge.sourceURL])
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 12))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal Source in Finder")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Section 2: Loose Files Categorization
                if !proposals.isEmpty {
                    Section(header: Text("Loose Files to Categorize (\(proposals.count))").font(.system(size: 12, weight: .bold)).foregroundColor(.blue)) {
                        ForEach(proposals) { p in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { selectedProposalIDs.contains(p.id) },
                                    set: { if $0 { selectedProposalIDs.insert(p.id) } else { selectedProposalIDs.remove(p.id) } }
                                ))
                                .labelsHidden()

                                Image(systemName: p.category.systemIcon)
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.fileName)
                                        .font(.system(size: 12, weight: .semibold))
                                    HStack(spacing: 4) {
                                        Text(p.sourceURL.deletingLastPathComponent().lastPathComponent)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9))
                                        Text(p.proposedDestinationURL.deletingLastPathComponent().lastPathComponent)
                                            .foregroundColor(.blue)
                                    }
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(p.formattedSize)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([p.sourceURL])
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 12))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .frame(height: 330)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                let totalActions = selectedProposalIDs.count + selectedMergeIDs.count
                Button("Approve Selected (\(totalActions) Operations)") {
                    let approvedProposals = proposals.filter { selectedProposalIDs.contains($0.id) }
                    let approvedMerges = folderMerges.filter { selectedMergeIDs.contains($0.id) }
                    onApprove(approvedProposals, approvedMerges)
                }
                .buttonStyle(.borderedProminent)
                .disabled(totalActions == 0)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 620, height: 460)
    }
}

// MARK: - Cleanup Approval Sheet
struct CleanupApprovalSheet: View {
    let targets: [CleanupTarget]
    let onApprove: ([CleanupTarget]) -> Void
    let onCancel: () -> Void

    @State private var selectedIDs: Set<UUID>

    init(targets: [CleanupTarget], onApprove: @escaping ([CleanupTarget]) -> Void, onCancel: @escaping () -> Void) {
        self.targets = targets
        self.onApprove = onApprove
        self.onCancel = onCancel
        _selectedIDs = State(initialValue: Set(targets.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm Safe Cleanup")
                        .font(.system(size: 16, weight: .bold))
                    Text("Selected items will be safely relocated to macOS Trash. Nothing is deleted permanently.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(selectedIDs.count == targets.count ? "Deselect All" : "Select All") {
                    if selectedIDs.count == targets.count {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(targets.map(\.id))
                    }
                }
                .font(.system(size: 11))
            }

            List {
                ForEach(targets) { t in
                    let isSafe = t.safetyTier == .safe
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { selectedIDs.contains(t.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedIDs.insert(t.id)
                                } else {
                                    selectedIDs.remove(t.id)
                                }
                            }
                        ))
                        .labelsHidden()

                        Image(systemName: isSafe ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isSafe ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name)
                                .font(.system(size: 12, weight: .semibold))
                            Text(t.path)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Text(t.formattedSize)
                            .font(.system(size: 11, weight: .medium))

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([t.url])
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(height: 320)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                let approved = targets.filter { selectedIDs.contains($0.id) }
                let totalApprovedSize = approved.reduce(0) { $0 + $1.size }
                let formatted = ByteCountFormatter.string(fromByteCount: totalApprovedSize, countStyle: .file)

                Button("Approve Cleanup to Trash (\(formatted))") {
                    onApprove(approved)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 600, height: 440)
    }
}

// MARK: - Duplicate Approval Sheet
struct DuplicateApprovalSheet: View {
    let duplicates: [DuplicateGroup]
    let onApprove: (Int, Int64) -> Void
    let onCancel: () -> Void

    @State private var selectedCopyPaths: Set<String> = []

    init(duplicates: [DuplicateGroup], onApprove: @escaping (Int, Int64) -> Void, onCancel: @escaping () -> Void) {
        self.duplicates = duplicates
        self.onApprove = onApprove
        self.onCancel = onCancel

        var initial: Set<String> = []
        for group in duplicates {
            for copy in group.files.dropFirst() {
                initial.insert(copy.path)
            }
        }
        _selectedCopyPaths = State(initialValue: initial)
    }

    private var totalFreedBytes: Int64 {
        var total: Int64 = 0
        for group in duplicates {
            for file in group.files where selectedCopyPaths.contains(file.path) {
                total += file.size
            }
        }
        return total
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm Duplicate Cleanup")
                        .font(.system(size: 16, weight: .bold))
                    Text("Keep the original file and move duplicate copies safely to macOS Trash.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(selectedCopyPaths.isEmpty ? "Select All Copies" : "Deselect All") {
                    if selectedCopyPaths.isEmpty {
                        var all: Set<String> = []
                        for group in duplicates {
                            for copy in group.files.dropFirst() {
                                all.insert(copy.path)
                            }
                        }
                        selectedCopyPaths = all
                    } else {
                        selectedCopyPaths.removeAll()
                    }
                }
                .font(.system(size: 11))
            }

            List {
                ForEach(duplicates) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                                .foregroundColor(.indigo)
                            Text(group.files.first?.name ?? "Cluster")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text("\(group.files.count) copies • \(group.formattedWastedSpace) wasted")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.indigo)
                        }

                        ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                            HStack(spacing: 8) {
                                if index == 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 11))
                                    Text("Keep Original")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.green)
                                } else {
                                    Toggle("", isOn: Binding(
                                        get: { selectedCopyPaths.contains(file.path) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedCopyPaths.insert(file.path)
                                            } else {
                                                selectedCopyPaths.remove(file.path)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                }

                                Text(file.path)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 11))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(height: 320)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()

                let count = selectedCopyPaths.count
                let formatted = ByteCountFormatter.string(fromByteCount: totalFreedBytes, countStyle: .file)

                Button("Clean \(count) Duplicates to Trash (\(formatted))") {
                    let freed = totalFreedBytes
                    var removed = 0
                    for group in duplicates {
                        for file in group.files where selectedCopyPaths.contains(file.path) {
                            do {
                                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                                RollbackLedger.shared.recordOperation(OperationRecord(
                                    actionType: .moveToTrash,
                                    sourcePath: file.path,
                                    fileSize: file.size,
                                    reason: "Duplicate file removed by AI Assistant"
                                ))
                                removed += 1
                            } catch {}
                        }
                    }
                    onApprove(removed, freed)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(selectedCopyPaths.isEmpty)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 600, height: 440)
    }
}
