import SwiftUI

public enum NavigationSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case assistant = "AI Assistant"
    case storage = "Storage Analyzer"
    case organizer = "File Organizer"
    case cleanup = "Cleanup Center"
    case approvals = "Approvals & History"
    case settings = "Settings & Model"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dashboard: return "speedometer"
        case .assistant: return "sparkles"
        case .storage: return "chart.pie.fill"
        case .organizer: return "folder.badge.gearshape"
        case .cleanup: return "trash.fill"
        case .approvals: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct MainView: View {
    @State private var selectedSection: NavigationSection? = .dashboard

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selectedSection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            Group {
                switch selectedSection ?? .dashboard {
                case .dashboard:
                    DashboardView(onNavigate: { section in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            selectedSection = section
                        }
                    })
                case .assistant:
                    AssistantView()
                case .storage:
                    StorageView()
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
        }
    }
}

struct SidebarView: View {
    @Binding var selectedSection: NavigationSection?

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

            // Hardware & Engine Status Pill
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Apple M5 Pro • Metal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Text("Qwen 2.5 3B • Local Offline")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(12)
        }
    }
}
