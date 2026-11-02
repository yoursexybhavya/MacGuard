import SwiftUI

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
    @State private var messages: [ChatMessage] = [
        ChatMessage(
            isUser: false,
            text: "Hello! I am MacGuard, your specialized local maintenance assistant. Ask me to organize your Downloads, find duplicate files, clean temporary caches, or analyze your disk space."
        )
    ]
    @State private var currentInput: String = ""
    @State private var isProcessing: Bool = false
    @State private var pendingProposals: [OrganizationProposal] = []
    @State private var pendingCleanups: [CleanupTarget] = []
    @State private var showApprovalSheet: Bool = false
    @State private var approvalType: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
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

            Divider()

            // Chat Messages Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { msg in
                            ChatBubbleView(
                                message: msg,
                                onApproveOrganization: { proposals in
                                    self.pendingProposals = proposals
                                    self.approvalType = "organization"
                                    self.showApprovalSheet = true
                                },
                                onApproveCleanup: { cleanups in
                                    self.pendingCleanups = cleanups
                                    self.approvalType = "cleanup"
                                    self.showApprovalSheet = true
                                }
                            )
                        }

                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Analyzing filesystem...")
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

            // Suggested Prompts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SuggestionChip(text: "Organize my Downloads folder") {
                        sendQuery("Organize my Downloads folder")
                    }
                    SuggestionChip(text: "Find unnecessary files taking up space") {
                        sendQuery("Find unnecessary files taking up space")
                    }
                    SuggestionChip(text: "Find duplicate files") {
                        sendQuery("Find duplicate files")
                    }
                    SuggestionChip(text: "Show largest files on my Mac") {
                        sendQuery("Show me the largest files on my Mac")
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
        .sheet(isPresented: $showApprovalSheet) {
            if approvalType == "organization" {
                OrganizationApprovalSheet(
                    proposals: pendingProposals,
                    onApprove: {
                        try? FileOrganizer.shared.executeProposals(pendingProposals)
                        messages.append(ChatMessage(isUser: false, text: "Successfully organized \(pendingProposals.count) files. All changes recorded in the Rollback Ledger."))
                        showApprovalSheet = false
                    },
                    onCancel: {
                        showApprovalSheet = false
                    }
                )
            } else {
                CleanupApprovalSheet(
                    targets: pendingCleanups,
                    onApprove: {
                        try? CleanupEngine.shared.executeCleanup(targets: pendingCleanups)
                        messages.append(ChatMessage(isUser: false, text: "Safely moved \(pendingCleanups.count) items to macOS Trash. You can undo this anytime from the Rollback Ledger."))
                        showApprovalSheet = false
                    },
                    onCancel: {
                        showApprovalSheet = false
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
                case .organizationPlan(let msg, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                case .cleanupPlan(let msg, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                case .duplicatePlan(let msg, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                case .storageAnalysis(let msg, _):
                    messages.append(ChatMessage(isUser: false, text: msg, result: result))
                }
                isProcessing = false
            }
        }
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    let onApproveOrganization: ([OrganizationProposal]) -> Void
    let onApproveCleanup: ([CleanupTarget]) -> Void

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

                VStack(alignment: .leading, spacing: 10) {
                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)

                    // Embedded Tool Action Cards
                    if let result = message.result {
                        switch result {
                        case .organizationPlan(_, let proposals):
                            if !proposals.isEmpty {
                                ProposalActionCard(proposals: proposals, onApprove: {
                                    onApproveOrganization(proposals)
                                })
                            }

                        case .cleanupPlan(_, let candidates):
                            if !candidates.isEmpty {
                                CleanupActionCard(candidates: candidates, onApprove: {
                                    onApproveCleanup(candidates)
                                })
                            }

                        case .duplicatePlan(_, let duplicates):
                            if !duplicates.isEmpty {
                                DuplicateActionCard(duplicates: duplicates)
                            }

                        case .storageAnalysis(_, let overview):
                            StorageActionCard(overview: overview)

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

struct ProposalActionCard: View {
    let proposals: [OrganizationProposal]
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.blue)
                Text("Proposed File Organization")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(proposals.count) files")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text("Files will be categorized into subfolders without overwriting existing files.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button(action: onApprove) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Review & Approve Plan")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(10)
    }
}

struct CleanupActionCard: View {
    let candidates: [CleanupTarget]
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "trash.fill")
                    .foregroundColor(.orange)
                Text("Proposed Safe Cleanup")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                let total = candidates.reduce(0) { $0 + $1.size }
                Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
            }

            Text("Identified safe developer caches, system logs, and unneeded disk images.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button(action: onApprove) {
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
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }
}

struct DuplicateActionCard: View {
    let duplicates: [DuplicateGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.indigo)
                Text("Duplicate Files Found")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                let wasted = duplicates.reduce(0) { $0 + $1.totalWastedSpace }
                Text(ByteCountFormatter.string(fromByteCount: wasted, countStyle: .file))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.indigo)
            }
            Text("Cryptographically matched across size and SHA-256 hash.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.indigo.opacity(0.08))
        .cornerRadius(10)
    }
}

struct StorageActionCard: View {
    let overview: StorageOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(overview.formattedAvailable) Free")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)
                Text("of \(overview.formattedTotal)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            ProgressView(value: overview.usagePercentage)
                .tint(.blue)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
    }
}

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

struct OrganizationApprovalSheet: View {
    let proposals: [OrganizationProposal]
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Confirm File Organization")
                .font(.system(size: 16, weight: .bold))

            Text("MacGuard will move the following \(proposals.count) files into categorized folders. This action is 100% reversible via the Rollback Ledger.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            List(proposals) { p in
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.fileName)
                        .font(.system(size: 12, weight: .semibold))
                    HStack {
                        Text(p.sourcePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.right")
                        Text(p.destinationPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .frame(height: 250)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Approve Selected", action: onApprove)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 540)
    }
}

struct CleanupApprovalSheet: View {
    let targets: [CleanupTarget]
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Confirm Safe Cleanup")
                .font(.system(size: 16, weight: .bold))

            Text("Selected items will be safely relocated to macOS Trash. Nothing will be permanently deleted.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            List(targets) { t in
                HStack {
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
                }
                .padding(.vertical, 4)
            }
            .frame(height: 250)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Approve Cleanup to Trash", action: onApprove)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 540)
    }
}
