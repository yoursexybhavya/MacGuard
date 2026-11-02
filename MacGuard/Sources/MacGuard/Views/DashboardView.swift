import SwiftUI

public struct DashboardView: View {
    public let onNavigate: (NavigationSection) -> Void

    @State private var overview: StorageOverview?
    @State private var cleanupCandidates: [CleanupTarget] = []
    @State private var recentOperations: [OperationRecord] = []
    @State private var isScanning: Bool = false

    public init(onNavigate: @escaping (NavigationSection) -> Void) {
        self.onNavigate = onNavigate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Top Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Overview")
                            .font(.system(size: 26, weight: .bold))
                        Text("Continuous local AI maintenance for your MacBook Pro")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        refreshData()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isScanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .rotationEffect(Angle(degrees: isScanning ? 360 : 0))
                                .animation(isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isScanning)
                            Text("Scan Now")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Storage Ring & Metric Cards
                HStack(spacing: 16) {
                    // Gauge Card
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 14)
                                .frame(width: 130, height: 130)

                            Circle()
                                .trim(from: 0.0, to: CGFloat(overview?.usagePercentage ?? 0.81))
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [.blue, .purple, .cyan]),
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                                )
                                .rotationEffect(Angle(degrees: -90))
                                .frame(width: 130, height: 130)

                            VStack(spacing: 2) {
                                Text("\(Int((overview?.usagePercentage ?? 0.81) * 100))%")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Text("Storage Used")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(spacing: 4) {
                            Text("\(overview?.formattedAvailable ?? "186 GB") Free")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.green)
                            Text("of \(overview?.formattedTotal ?? "994 GB") Total APFS")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(width: 220, height: 230)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(16)

                    // Reclaimable Storage Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ZStack {
                                Circle().fill(Color.orange.opacity(0.15)).frame(width: 36, height: 36)
                                Image(systemName: "sparkles")
                                    .foregroundColor(.orange)
                            }
                            Text("Optimization Opportunity")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }

                        let totalCleanable = cleanupCandidates.reduce(0) { $0 + $1.size }
                        Text(ByteCountFormatter.string(fromByteCount: totalCleanable, countStyle: .file))
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.primary)

                        Text("Identified across safe developer caches, system logs, and uninstalled DMG installers.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            onNavigate(.cleanup)
                        } label: {
                            Text("Review Cleanup Targets")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(20)
                    .frame(height: 230)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(16)

                    // Background Protection Status
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ZStack {
                                Circle().fill(Color.green.opacity(0.15)).frame(width: 36, height: 36)
                                Image(systemName: "shield.checkered")
                                    .foregroundColor(.green)
                            }
                            Text("Security Guard")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("Active")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }

                        Text("Zero Deletions Without Approval")
                            .font(.system(size: 16, weight: .bold))

                        Text("All file relocations and trashings are sandboxed and fully reversible via the Rollback Ledger.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            onNavigate(.approvals)
                        } label: {
                            Text("View Audit History (\(recentOperations.count))")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(20)
                    .frame(height: 230)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(16)
                }

                // Quick Action Center
                VStack(alignment: .leading, spacing: 12) {
                    Text("Intelligent Maintenance Actions")
                        .font(.system(size: 16, weight: .bold))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        QuickActionCard(
                            title: "AI Assistant",
                            subtitle: "Ask MacGuard in natural language",
                            icon: "sparkles",
                            color: .purple
                        ) {
                            onNavigate(.assistant)
                        }

                        QuickActionCard(
                            title: "Organize Files",
                            subtitle: "Sort Downloads by category",
                            icon: "folder.badge.gearshape",
                            color: .blue
                        ) {
                            onNavigate(.organizer)
                        }

                        QuickActionCard(
                            title: "Clean Caches",
                            subtitle: "Safe temporary file removal",
                            icon: "trash.fill",
                            color: .orange
                        ) {
                            onNavigate(.cleanup)
                        }

                        QuickActionCard(
                            title: "Analyze Space",
                            subtitle: "Inspect largest files & folders",
                            icon: "chart.pie.fill",
                            color: .indigo
                        ) {
                            onNavigate(.storage)
                        }
                    }
                }

                // Recent Operations
                if !recentOperations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Actions")
                            .font(.system(size: 16, weight: .bold))

                        VStack(spacing: 8) {
                            ForEach(recentOperations.prefix(4)) { op in
                                HStack {
                                    Image(systemName: op.actionType == .moveToTrash ? "trash" : "arrow.right.circle")
                                        .foregroundColor(op.actionType == .moveToTrash ? .red : .blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(URL(fileURLWithPath: op.sourcePath).lastPathComponent)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(op.reason)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if op.isRolledBack {
                                        Text("Rolled Back")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Active")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.04))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            refreshData()
        }
    }

    private func refreshData() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let overviewResult = StorageAnalyzer.shared.analyzeStorage()
            let cleanups = CleanupEngine.shared.discoverCleanupCandidates()
            let history = RollbackLedger.shared.loadHistory()

            DispatchQueue.main.async {
                self.overview = overviewResult
                self.cleanupCandidates = cleanups
                self.recentOperations = history
                self.isScanning = false
            }
        }
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 16, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
