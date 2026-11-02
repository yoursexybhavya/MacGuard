import SwiftUI

public struct ApprovalCenterView: View {
    @State private var history: [OperationRecord] = []
    @State private var rollbackMessage: String?
    @State private var isError: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Approval Center & Rollback History")
                        .font(.system(size: 22, weight: .bold))
                    Text("Complete audit log of all file operations with one-click reversible rollback")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    loadHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            if history.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Operations Recorded Yet")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Any file movements or safe cleanups performed in MacGuard will be logged here for full reversibility.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List(history) { record in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(record.actionType == .moveToTrash ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: record.actionType == .moveToTrash ? "trash" : "arrow.right.circle")
                                .foregroundColor(record.actionType == .moveToTrash ? .orange : .blue)
                                .font(.system(size: 15))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(record.actionType.rawValue)
                                    .font(.system(size: 13, weight: .bold))

                                Text(record.timestamp, style: .date)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(record.timestamp, style: .time)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Spacer()

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

                            Text(URL(fileURLWithPath: record.sourcePath).lastPathComponent)
                                .font(.system(size: 12, weight: .medium))

                            if let dest = record.destinationPath {
                                HStack(spacing: 4) {
                                    Text("To:")
                                    Text(dest)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            }

                            Text(record.reason)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !record.isRolledBack {
                            Button("Rollback") {
                                executeRollback(for: record.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let msg = rollbackMessage {
                HStack {
                    Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundColor(isError ? .red : .green)
                    Text(msg)
                        .font(.system(size: 12))
                    Spacer()
                }
                .padding(10)
                .background((isError ? Color.red : Color.green).opacity(0.1))
            }
        }
        .onAppear {
            loadHistory()
        }
    }

    private func loadHistory() {
        history = RollbackLedger.shared.loadHistory()
    }

    private func executeRollback(for id: UUID) {
        do {
            try RollbackLedger.shared.rollback(operationId: id)
            rollbackMessage = "Successfully reversed operation and restored original state."
            isError = false
            loadHistory()
        } catch {
            rollbackMessage = "Rollback failed: \(error.localizedDescription)"
            isError = true
        }
    }
}
