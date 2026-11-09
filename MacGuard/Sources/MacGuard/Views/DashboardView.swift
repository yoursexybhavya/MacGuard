import SwiftUI
import AppKit

// MARK: - Storage Gauge Button Style
public struct StorageGaugeButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Interactive Circular Storage Gauge Card (Feature F12)
public struct DashboardStorageGaugeCard: View {
    public let usagePercentage: Double
    public let formattedAvailable: String
    public let formattedTotal: String
    public let onSelect: () -> Void

    @State private var isHovered: Bool = false

    public init(
        usagePercentage: Double,
        formattedAvailable: String,
        formattedTotal: String,
        onSelect: @escaping () -> Void
    ) {
        self.usagePercentage = usagePercentage
        self.formattedAvailable = formattedAvailable
        self.formattedTotal = formattedTotal
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 14) {
                ZStack {
                    // Inactive Track
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 14)
                        .frame(width: 130, height: 130)

                    // Dynamic Progress Arc
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(1.0, max(0.0, usagePercentage))))
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.blue, .purple, .cyan, .blue]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(Angle(degrees: -90))
                        .frame(width: 130, height: 130)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: usagePercentage)

                    // Center Readout & Affordance
                    VStack(spacing: 2) {
                        Text("\(Int(usagePercentage * 100))%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("Storage Used")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        // Hover cue
                        HStack(spacing: 3) {
                            Text("Inspect")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                        .opacity(isHovered ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.18), value: isHovered)
                    }
                }

                // Sub-labels
                VStack(spacing: 4) {
                    Text("\(formattedAvailable) Free")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                    Text("of \(formattedTotal) Total APFS")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .frame(width: 220, height: 230)
            .background(isHovered ? Color.secondary.opacity(0.10) : Color.secondary.opacity(0.06))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovered ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        }
        .buttonStyle(StorageGaugeButtonStyle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Click to inspect detailed storage breakdown in Storage Analyzer")
    }
}

// MARK: - Quick Action Card (Feature F12)
public struct QuickActionCard: View {
    public let title: String
    public let subtitle: String
    public let icon: String
    public let color: Color
    public let action: () -> Void

    @State private var isHovered: Bool = false

    public init(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(isHovered ? 0.25 : 0.15))
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
            .background(isHovered ? color.opacity(0.08) : Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? color.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        }
        .buttonStyle(StorageGaugeButtonStyle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Recent Operation Row View (Feature F12)
public struct RecentOperationRowView: View {
    public let op: OperationRecord
    public let onRollback: (UUID) -> Void
    public let onReveal: (String) -> Void

    @State private var isHovered: Bool = false

    public init(
        op: OperationRecord,
        onRollback: @escaping (UUID) -> Void,
        onReveal: @escaping (String) -> Void
    ) {
        self.op = op
        self.onRollback = onRollback
        self.onReveal = onReveal
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Leading Action Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 32, height: 32)
                Image(systemName: op.systemImageName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconForegroundColor)
            }

            // Primary Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(op.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(op.formattedSize)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(op.formattedDate)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(op.reason)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status Badge
            if op.isRolledBack {
                Text("Rolled Back")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundColor(.secondary)
                    .cornerRadius(5)
            } else {
                Text("Active")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(5)
            }

            // Inline Rollback Button
            if !op.isRolledBack {
                Button {
                    onRollback(op.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Rollback")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Undo this operation and safely restore file to original location")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.04))
        .cornerRadius(10)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            if !op.isRolledBack {
                Button {
                    onRollback(op.id)
                } label: {
                    Label("Rollback Operation", systemImage: "arrow.uturn.backward")
                }
            }

            Button {
                onReveal(op.destinationPath ?? op.sourcePath)
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(op.sourcePath, forType: .string)
            } label: {
                Label("Copy Original Path", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                NavigationCoordinator.shared.navigateToApprovals()
            } label: {
                Label("View Audit Center", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private var iconForegroundColor: Color {
        switch op.actionType {
        case .moveToTrash: return .orange
        case .moveFile: return .blue
        case .createDirectory: return .purple
        }
    }

    private var iconBackgroundColor: Color {
        iconForegroundColor.opacity(0.15)
    }
}

// MARK: - Dashboard Main View
public struct DashboardView: View {
    public let onNavigate: (NavigationSection) -> Void

    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var ledger = RollbackLedger.shared

    @State private var liveMetrics: LiveVolumeMetrics = StorageAnalyzer.shared.getLiveVolumeMetrics()
    @State private var overview: StorageOverview?
    @State private var cleanupCandidates: [CleanupTarget] = []
    @State private var isScanning: Bool = false
    @State private var feedbackBanner: String? = nil
    @State private var isFeedbackError: Bool = false

    public init(onNavigate: @escaping (NavigationSection) -> Void = { _ in }) {
        self.onNavigate = onNavigate
    }

    private var activeUsagePercentage: Double {
        if let ov = overview, ov.totalCapacity > 0 {
            return ov.usagePercentage
        }
        return liveMetrics.usagePercentage
    }

    private var activeFormattedAvailable: String {
        overview?.formattedAvailable ?? liveMetrics.formattedAvailable
    }

    private var activeFormattedTotal: String {
        overview?.formattedTotal ?? liveMetrics.formattedTotal
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

                // Full Disk Access Alert Banner
                if !permissions.hasFullDiskAccess {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.orange.opacity(0.18))
                                .frame(width: 38, height: 38)
                            Image(systemName: "lock.laptopcomputer")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.orange)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Full Disk Access Recommended")
                                    .font(.system(size: 13, weight: .bold))
                                Text("One-Time macOS Setup")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                            Text("Prevent repeated macOS permission popups and allow MacGuard to inspect disk space, clean developer caches, and find duplicates across your entire drive.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            permissions.openFullDiskAccessSettings()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.forward.app")
                                Text("Grant Full Disk Access")
                            }
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
                }

                // Storage Ring & Metric Cards
                HStack(spacing: 16) {
                    // Interactive Gauge Card (Feature F12)
                    DashboardStorageGaugeCard(
                        usagePercentage: activeUsagePercentage,
                        formattedAvailable: activeFormattedAvailable,
                        formattedTotal: activeFormattedTotal
                    ) {
                        navigateToSection(.storage)
                    }

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
                            navigateToSection(.cleanup)
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
                            Text(permissions.hasFullDiskAccess ? "Full Disk Access" : "Standard Access")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((permissions.hasFullDiskAccess ? Color.green : Color.orange).opacity(0.2))
                                .foregroundColor(permissions.hasFullDiskAccess ? .green : .orange)
                                .cornerRadius(6)
                        }

                        Text("Zero Deletions Without Approval")
                            .font(.system(size: 16, weight: .bold))

                        Text("All file relocations and trashings are sandboxed and fully reversible via the Rollback Ledger.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            navigateToSection(.approvals)
                        } label: {
                            Text("View Audit History (\(ledger.operations.count))")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(20)
                    .frame(height: 230)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(16)
                }

                // Quick Action Center (Feature F12: Wired with Clean Caches, Duplicates, Organizer, Storage)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Intelligent Maintenance Actions")
                        .font(.system(size: 16, weight: .bold))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        QuickActionCard(
                            title: "Clean Caches",
                            subtitle: "Safe temporary file removal",
                            icon: "trash.fill",
                            color: .orange
                        ) {
                            navigateToSection(.cleanup)
                        }

                        QuickActionCard(
                            title: "Find Duplicates",
                            subtitle: "Locate identical files & waste",
                            icon: "doc.on.doc.fill",
                            color: .teal
                        ) {
                            NavigationCoordinator.shared.navigateToDuplicates()
                            onNavigate(.duplicates)
                        }

                        QuickActionCard(
                            title: "Organize Files",
                            subtitle: "Sort Downloads by category",
                            icon: "folder.badge.gearshape",
                            color: .blue
                        ) {
                            navigateToSection(.organizer)
                        }

                        QuickActionCard(
                            title: "Analyze Space",
                            subtitle: "Inspect largest files & folders",
                            icon: "chart.pie.fill",
                            color: .indigo
                        ) {
                            NavigationCoordinator.shared.navigateToStorage()
                            onNavigate(.storage)
                        }
                    }
                }

                // Recent Operations (Feature F12: Reactive RollbackLedger, File Sizes, Relative Dates, Rollback & Context Menu)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent Actions")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                        Button {
                            navigateToSection(.approvals)
                        } label: {
                            Text("View Full Ledger →")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }

                    if let msg = feedbackBanner {
                        HStack {
                            Image(systemName: isFeedbackError ? "exclamationmark.triangle" : "checkmark.circle")
                                .foregroundColor(isFeedbackError ? .red : .green)
                            Text(msg)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(10)
                        .background((isFeedbackError ? Color.red : Color.green).opacity(0.1))
                        .cornerRadius(8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if ledger.recentOperations.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Zero Pending Operations")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("All file cleanups, trashings, and moves are recorded here with instant one-click reversible rollback.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(10)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(ledger.recentOperations.prefix(5)) { op in
                                RecentOperationRowView(
                                    op: op,
                                    onRollback: { id in
                                        executeRollback(for: id)
                                    },
                                    onReveal: { path in
                                        revealPath(path)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            permissions.checkPermissions()
            liveMetrics = StorageAnalyzer.shared.getLiveVolumeMetrics()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.checkPermissions()
            liveMetrics = StorageAnalyzer.shared.getLiveVolumeMetrics()
        }
    }

    private func navigateToSection(_ section: NavigationSection) {
        NavigationCoordinator.shared.navigateTo(section: section)
        onNavigate(section)
    }

    private func refreshData() {
        liveMetrics = StorageAnalyzer.shared.getLiveVolumeMetrics()
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let overviewResult = StorageAnalyzer.shared.analyzeStorage()
            let cleanups = CleanupEngine.shared.discoverCleanupCandidates()

            DispatchQueue.main.async {
                self.overview = overviewResult
                self.cleanupCandidates = cleanups
                self.liveMetrics = StorageAnalyzer.shared.getLiveVolumeMetrics()
                self.isScanning = false
            }
        }
    }

    private func executeRollback(for id: UUID) {
        do {
            let restoredURL = try RollbackLedger.shared.rollback(recordId: id)
            withAnimation(.easeInOut(duration: 0.2)) {
                self.feedbackBanner = "Successfully restored '\(restoredURL.lastPathComponent)' to original location."
                self.isFeedbackError = false
            }
        } catch {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.feedbackBanner = "Rollback failed: \(error.localizedDescription)"
                self.isFeedbackError = true
            }
        }
    }

    private func revealPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            NSWorkspace.shared.open(parent)
        }
    }
}
