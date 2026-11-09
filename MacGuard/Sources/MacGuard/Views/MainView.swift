import SwiftUI
import AppKit
import QuickLook

public struct MainView: View {
    @ObservedObject private var coordinator = NavigationCoordinator.shared

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selectedSection: coordinator.selectionBinding)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            Group {
                switch coordinator.selectedSection {
                case .dashboard:
                    DashboardView(onNavigate: { section in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            coordinator.navigateTo(section: section)
                        }
                    })
                case .assistant:
                    AssistantView(onNavigate: { section in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            coordinator.navigateTo(section: section)
                        }
                    })
                case .storage:
                    StorageView()
                case .duplicates:
                    DuplicatesView()
                case .organizer:
                    OrganizerView()
                case .cleanup:
                    CleanupView()
                case .approvals:
                    ApprovalCenterView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(minWidth: 700, minHeight: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            .quickLookPreview($coordinator.previewURL)
        }
    }
}

struct SidebarView: View {
    @Binding var selectedSection: NavigationSection?
    @ObservedObject private var hardware = HardwareMonitor.shared
    @ObservedObject private var coordinator = NavigationCoordinator.shared
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // App Branding Header
            HStack(spacing: 12) {
                ZStack {
                    LinearGradient(
                        colors: [Color.blue, Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(width: 36, height: 36)

                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("MACGUARD")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(0.5)
                    Text("Local AI Maintenance")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 12)

            // Section List
            List(NavigationSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label {
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: section.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedSection == section ? .blue : .secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)

            Spacer()

            // Hardware & Engine Status Pill (Interactive & Dynamic)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    coordinator.navigateToSettings()
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(hardware.hardwareInfo.deviceSummary)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    Text(hardware.hardwareInfo.activeMemorySummary)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(isHovered ? 0.15 : 0.0), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Hardware: \(hardware.hardwareInfo.chipName) (\(hardware.hardwareInfo.coreCount) Cores, \(hardware.hardwareInfo.formattedPhysicalMemory)). Click to open Settings.")
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .padding(12)
        }
    }
}
