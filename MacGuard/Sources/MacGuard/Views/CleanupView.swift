import SwiftUI

public struct CleanupView: View {
    @State private var candidates: [CleanupTarget] = []
    @State private var isLoading: Bool = true
    @State private var showConfirmSheet: Bool = false
    @State private var executionMessage: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intelligent Cleanup Center")
                        .font(.system(size: 22, weight: .bold))
                    Text("Safe cache and temporary file cleanup with 100% reversible Trash integration")
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
            }
            .padding(20)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Scanning user caches, logs, and installer files...")
                Spacer()
            } else if candidates.isEmpty {
                Spacer()
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
                Spacer()
            } else {
                VStack(spacing: 0) {
                    // Action Summary Bar
                    let selectedItems = candidates.filter { $0.isSelected }
                    let selectedBytes = selectedItems.reduce(0) { $0 + $1.size }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(selectedItems.count) of \(candidates.count) Items Selected")
                                .font(.system(size: 14, weight: .bold))
                            Text("Reclaimable space: \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)) • Items move to macOS Trash")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            showConfirmSheet = true
                        } label: {
                            HStack {
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

                    // Targets List
                    List {
                        ForEach($candidates) { $target in
                            HStack(spacing: 12) {
                                Toggle("", isOn: $target.isSelected)
                                    .labelsHidden()

                                ZStack {
                                    Circle()
                                        .fill(badgeColor(target.safetyTier).opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: target.safetyTier == .safe ? "checkmark.shield" : "exclamationmark.triangle")
                                        .foregroundColor(badgeColor(target.safetyTier))
                                        .font(.system(size: 14))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(target.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(target.safetyTier.rawValue)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(badgeColor(target.safetyTier).opacity(0.15))
                                            .foregroundColor(badgeColor(target.safetyTier))
                                            .cornerRadius(4)
                                    }
                                    Text(target.explanation)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(target.path)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary.opacity(0.8))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                Text(target.formattedSize)
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if let msg = executionMessage {
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
            loadCandidates()
        }
        .sheet(isPresented: $showConfirmSheet) {
            let selected = candidates.filter { $0.isSelected }
            let total = selected.reduce(0) { $0 + $1.size }

            VStack(spacing: 16) {
                Text("Confirm Safe Cleanup")
                    .font(.system(size: 16, weight: .bold))

                Text("Are you sure you want to move \(selected.count) items (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))) to macOS Trash?")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Note: Files are relocated to macOS Trash and are NOT permanently deleted. You can restore them anytime.")
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

    private func badgeColor(_ tier: SafetyTier) -> Color {
        switch tier {
        case .safe: return .green
        case .reviewRecommended: return .orange
        case .highRisk: return .red
        case .protected: return .gray
        }
    }
}
