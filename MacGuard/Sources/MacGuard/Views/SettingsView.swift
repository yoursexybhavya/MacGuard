import SwiftUI
import AppKit

public enum AppSettingsKeys {
    public static let selectedOllamaModel = "selectedOllamaModel"
    public static let customOllamaModel = "customOllamaModel"
    public static let enableBackgroundMonitoring = "enableBackgroundMonitoring"
    public static let monitoringFrequencyMinutes = "monitoringFrequencyMinutes"
    public static let enableDownloadsWatch = "enableDownloadsWatch"
    public static let downloadsClutterThreshold = "downloadsClutterThreshold"
    public static let lowStorageThresholdGB = "lowStorageThresholdGB"
    public static let enableAutoCleanupAlerts = "enableAutoCleanupAlerts"
}

public struct AppSettings {
    public static let defaultSelectedModel = "macguard-ai:latest"
    public static let defaultCustomModel = ""
    public static let defaultEnableBackgroundMonitoring = true
    public static let defaultMonitoringFrequencyMinutes: Double = 15.0
    public static let defaultEnableDownloadsWatch = true
    public static let defaultDownloadsClutterThreshold: Double = 40.0
    public static let defaultLowStorageThresholdGB: Double = 15.0
    public static let defaultEnableAutoCleanupAlerts = true

    public static func resetToDefaults(userDefaults: UserDefaults = .standard) {
        userDefaults.set(defaultSelectedModel, forKey: AppSettingsKeys.selectedOllamaModel)
        userDefaults.set(defaultCustomModel, forKey: AppSettingsKeys.customOllamaModel)
        userDefaults.set(defaultEnableBackgroundMonitoring, forKey: AppSettingsKeys.enableBackgroundMonitoring)
        userDefaults.set(defaultMonitoringFrequencyMinutes, forKey: AppSettingsKeys.monitoringFrequencyMinutes)
        userDefaults.set(defaultEnableDownloadsWatch, forKey: AppSettingsKeys.enableDownloadsWatch)
        userDefaults.set(defaultDownloadsClutterThreshold, forKey: AppSettingsKeys.downloadsClutterThreshold)
        userDefaults.set(defaultLowStorageThresholdGB, forKey: AppSettingsKeys.lowStorageThresholdGB)
        userDefaults.set(defaultEnableAutoCleanupAlerts, forKey: AppSettingsKeys.enableAutoCleanupAlerts)
    }

    public static func effectiveOllamaModel(userDefaults: UserDefaults = .standard) -> String {
        let selected = userDefaults.string(forKey: AppSettingsKeys.selectedOllamaModel) ?? defaultSelectedModel
        if selected == "custom" {
            let custom = userDefaults.string(forKey: AppSettingsKeys.customOllamaModel)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return custom.isEmpty ? defaultSelectedModel : custom
        }
        return selected
    }

    public static func formatFrequency(_ minutes: Double) -> String {
        let mins = Int(minutes)
        if mins < 60 {
            return "Every \(mins) minutes"
        } else {
            return "Every 1 hour"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject private var updater = AutoUpdateManager.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var hardware = HardwareMonitor.shared

    // Persisted Preferences via @AppStorage
    @AppStorage(AppSettingsKeys.selectedOllamaModel) private var selectedOllamaModel: String = AppSettings.defaultSelectedModel
    @AppStorage(AppSettingsKeys.customOllamaModel) private var customOllamaModel: String = AppSettings.defaultCustomModel
    @AppStorage(AppSettingsKeys.enableBackgroundMonitoring) private var enableBackgroundMonitoring: Bool = AppSettings.defaultEnableBackgroundMonitoring
    @AppStorage(AppSettingsKeys.monitoringFrequencyMinutes) private var monitoringFrequencyMinutes: Double = AppSettings.defaultMonitoringFrequencyMinutes
    @AppStorage(AppSettingsKeys.enableDownloadsWatch) private var enableDownloadsWatch: Bool = AppSettings.defaultEnableDownloadsWatch
    @AppStorage(AppSettingsKeys.downloadsClutterThreshold) private var downloadsClutterThreshold: Double = AppSettings.defaultDownloadsClutterThreshold
    @AppStorage(AppSettingsKeys.lowStorageThresholdGB) private var lowStorageThresholdGB: Double = AppSettings.defaultLowStorageThresholdGB
    @AppStorage(AppSettingsKeys.enableAutoCleanupAlerts) private var enableAutoCleanupAlerts: Bool = AppSettings.defaultEnableAutoCleanupAlerts

    // Ephemeral Live Ollama & UI State
    @State private var isOllamaOnline: Bool = false
    @State private var isTestingConnection: Bool = false
    @State private var connectionLatencyMs: Int? = nil
    @State private var connectionStatusBanner: String? = nil
    @State private var isConnectionSuccess: Bool = false
    @State private var models: [OllamaModelInfo] = []

    // UI Feedback & Reset State
    @State private var showResetConfirmation: Bool = false
    @State private var resetToastMessage: String? = nil
    @State private var hardwareRotationAngle: Double = 0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerView

                Divider()

                // Apple Silicon Hardware & Metal Acceleration Card
                hardwareSpecsCard

                // Local AI Intelligence Model Card
                localAICard

                // Background Monitoring Card
                backgroundMonitoringCard

                // Privacy & Security Safeguards Card
                privacyAndSecurityCard

                // Full Disk Access (FDA) Permission Management Card
                fullDiskAccessCard

                // Reset & Defaults Management Card
                resetDefaultsCard

                // Live Auto-Update Section (Vercel Edge Distribution)
                softwareUpdatesCard

                // App Info Footer
                appInfoFooter
            }
            .padding(24)
        }
        .confirmationDialog(
            "Reset All Settings to Defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Preferences", role: .destructive) {
                resetAllSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore default background scan frequencies, model preferences, and warning thresholds.\nNo files, caches, or rollback history will be deleted.")
        }
        .onAppear {
            permissions.checkPermissions()
            hardware.refresh()
            testOllamaConnection()
            Task {
                await updater.checkForUpdates(isUserInitiated: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.checkPermissions()
            hardware.refresh()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Settings & System Intelligence")
                        .font(.system(size: 22, weight: .bold))
                    Text("Feature F18")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                Text("Configure your Apple Silicon Metal acceleration, local AI inference, and persisted background monitor")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showResetConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Defaults")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .help("Reset all settings to factory defaults")
        }
    }

    private var hardwareSpecsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Apple Silicon Hardware & Metal Acceleration")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        hardwareRotationAngle += 360
                    }
                    hardware.refresh()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(hardwareRotationAngle))
                        Text("Refresh Specs")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Query live Metal device and memory utilization")
            }

            VStack(spacing: 12) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: "cpu")
                            .foregroundColor(.blue)
                            .font(.system(size: 16, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hardware.hardwareInfo.chipName)
                            .font(.system(size: 14, weight: .bold))
                        Text("\(hardware.hardwareInfo.coreCount) Active Cores • \(hardware.hardwareInfo.hasUnifiedMemory ? "Apple Unified Memory Architecture" : "Discrete VRAM")")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(hardware.hardwareInfo.formattedPhysicalMemory)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                        Text(hardware.hardwareInfo.formattedSystemFree)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(6)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Metal Acceleration")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Metal Shading Language (Active)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RAM Management")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(hardware.hardwareInfo.activeMemorySummary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Architecture")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(hardware.hardwareInfo.hasUnifiedMemory ? "Unified RAM" : "Discrete")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private var localAICard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Local AI Intelligence & Neural Inference")
                    .font(.system(size: 14, weight: .bold))
                Spacer()

                // Connection status pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(isOllamaOnline ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    if isOllamaOnline {
                        Text(connectionLatencyMs != nil ? "Online (\(connectionLatencyMs!)ms)" : "Online")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    } else {
                        Text("Offline (Native Fallback)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((isOllamaOnline ? Color.green : Color.orange).opacity(0.12))
                .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ollama Daemon Endpoint")
                            .font(.system(size: 12, weight: .medium))
                        Text("http://127.0.0.1:11434 • Local neural inference acceleration")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        testOllamaConnection()
                    } label: {
                        HStack(spacing: 5) {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(isTestingConnection ? "Testing..." : "Test Connection")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingConnection)
                }

                if let banner = connectionStatusBanner {
                    HStack(spacing: 6) {
                        Image(systemName: isConnectionSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isConnectionSuccess ? .green : .orange)
                        Text(banner)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button {
                            connectionStatusBanner = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background((isConnectionSuccess ? Color.green : Color.orange).opacity(0.1))
                    .cornerRadius(6)
                }

                Divider()

                // Model Selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Neural Model")
                        .font(.system(size: 12, weight: .medium))

                    HStack(spacing: 12) {
                        Picker("Model", selection: $selectedOllamaModel) {
                            Text("macguard-ai:latest (Default Fine-Tuned)")
                                .tag("macguard-ai:latest")

                            ForEach(models, id: \.name) { model in
                                if model.name != "macguard-ai:latest" {
                                    let sizeText = model.size != nil ? " (\(ByteCountFormatter.string(fromByteCount: model.size!, countStyle: .file)))" : ""
                                    Text("\(model.name)\(sizeText)")
                                        .tag(model.name)
                                }
                            }

                            Text("Custom Model Tag...")
                                .tag("custom")
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 320)

                        if selectedOllamaModel == "custom" {
                            TextField("e.g. llama3.2:3b", text: $customOllamaModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: 220)
                        }
                    }

                    Text("Effective Model: \(AppSettings.effectiveOllamaModel())")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                        .font(.system(size: 12))
                    Text("When Ollama is unreachable, MacGuard instantly falls back to its built-in rule engine (0 MB idle RAM, 0ms latency).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(6)
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private var backgroundMonitoringCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background Monitoring & Storage Health")
                .font(.system(size: 14, weight: .bold))

            VStack(spacing: 14) {
                Toggle(isOn: $enableBackgroundMonitoring) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Background Health Monitoring")
                            .font(.system(size: 13, weight: .medium))
                        Text("Silently audits APFS storage and downloads accumulation at scheduled intervals")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                if enableBackgroundMonitoring {
                    Divider()

                    // Audit Frequency
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Audit Frequency")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(AppSettings.formatFrequency(monitoringFrequencyMinutes))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                        }

                        Slider(value: $monitoringFrequencyMinutes, in: 5...60, step: 5)

                        HStack(spacing: 8) {
                            ForEach([5.0, 15.0, 30.0, 60.0], id: \.self) { mins in
                                Button {
                                    monitoringFrequencyMinutes = mins
                                } label: {
                                    Text(mins == 60 ? "1h" : "\(Int(mins))m")
                                        .font(.system(size: 10, weight: monitoringFrequencyMinutes == mins ? .bold : .regular))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 3)
                                        .background(monitoringFrequencyMinutes == mins ? Color.blue : Color.secondary.opacity(0.1))
                                        .foregroundColor(monitoringFrequencyMinutes == mins ? .white : .primary)
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }

                    Divider()

                    // Downloads Folder Watch
                    Toggle(isOn: $enableDownloadsWatch) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monitor Downloads Clutter")
                                .font(.system(size: 13, weight: .medium))
                            Text("Alerts when unorganized downloads exceed threshold")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    if enableDownloadsWatch {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Downloads Clutter Threshold")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text("\(Int(downloadsClutterThreshold)) items")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Slider(value: $downloadsClutterThreshold, in: 20...100, step: 5)
                        }
                    }

                    Divider()

                    // Low Storage Warning Threshold
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Low Storage Warning Threshold")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(lowStorageThresholdGB)) GB")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Slider(value: $lowStorageThresholdGB, in: 5...50, step: 5)
                        Text("Alerts you before APFS startup disk becomes constrained.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Auto-cleanup recommendations
                    Toggle(isOn: $enableAutoCleanupAlerts) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Proactive Cache Recommendations")
                                .font(.system(size: 13, weight: .medium))
                            Text("Notifies when safe Xcode DerivedData or diagnostic logs exceed 10 GB")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private var privacyAndSecurityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Security & Privacy Controls")
                .font(.system(size: 14, weight: .bold))

            VStack(alignment: .leading, spacing: 10) {
                SecurityRuleRow(
                    icon: "lock.shield.fill",
                    title: "100% Offline & Local-First",
                    desc: "Zero document bytes or telemetry ever leave your MacBook. All LLM queries process locally."
                )
                SecurityRuleRow(
                    icon: "hand.raised.fill",
                    title: "Strict Approval Gates",
                    desc: "MacGuard is architecturally prohibited from deleting or moving files without prior approval."
                )
                SecurityRuleRow(
                    icon: "trash.circle.fill",
                    title: "Non-Destructive Operations",
                    desc: "Cleanups target macOS Trash. No permanent file unlinking without manual user intervention."
                )
                SecurityRuleRow(
                    icon: "slash.circle.fill",
                    title: "Protected System Whitelist",
                    desc: "/System, /Library, /usr, /bin, and sensitive user roots (.ssh, Keychains) are strictly immutable."
                )
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private var fullDiskAccessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("macOS System Permissions & Full Disk Access")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(permissions.hasFullDiskAccess ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(permissions.hasFullDiskAccess ? "Full Disk Access Enabled" : "Access Pending")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(permissions.hasFullDiskAccess ? .green : .orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((permissions.hasFullDiskAccess ? Color.green : Color.orange).opacity(0.12))
                .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Why grant Full Disk Access?")
                    .font(.system(size: 13, weight: .semibold))

                Text("By default, macOS asks for permission separately for Documents, Downloads, Music, etc. Granting Full Disk Access permanently silences these repeated popups and permits MacGuard to analyze APFS storage, locate duplicate files across your Mac, and clean developer caches.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)

                HStack(spacing: 12) {
                    Button {
                        permissions.openFullDiskAccessSettings()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                            Text("Open Full Disk Access in System Settings")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(permissions.hasFullDiskAccess ? .secondary : .blue)

                    Button {
                        let appURL = URL(fileURLWithPath: "/Applications/MacGuard.app")
                        NSWorkspace.shared.activateFileViewerSelecting([appURL])
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app")
                            Text("Reveal MacGuard in Finder")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private var resetDefaultsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reset & Defaults Management")
                .font(.system(size: 14, weight: .bold))

            VStack(alignment: .leading, spacing: 12) {
                Text("Restore Application Defaults")
                    .font(.system(size: 13, weight: .semibold))

                Text("Revert all background monitoring intervals, neural model choices, downloads clutter limits, and low disk thresholds to their default factory values. This will not touch any of your files or rollback history.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)

                HStack {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise.circle")
                            Text("Reset to Defaults...")
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if let toast = resetToastMessage {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(toast)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                        .transition(.opacity)
                    }
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private var softwareUpdatesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Software Updates & Vercel Distribution")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if updater.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Installed Version:")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("v\(updater.currentVersion)")
                                .font(.system(size: 12, weight: .bold))
                        }

                        Text("Update Server: https://updater-server-kappa.vercel.app")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                    }

                    Spacer()

                    Button {
                        Task {
                            await updater.checkForUpdates(isUserInitiated: true)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(updater.isChecking ? "Checking..." : "Check for Updates")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(updater.isChecking || updater.isDownloading)
                }

                if let status = updater.statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: updater.isUpdateAvailable ? "sparkles" : "checkmark.circle.fill")
                            .foregroundColor(updater.isUpdateAvailable ? .orange : .green)
                        Text(status)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(8)
                    .background((updater.isUpdateAvailable ? Color.orange : Color.green).opacity(0.1))
                    .cornerRadius(6)
                }

                if let err = updater.updateError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }

                if updater.isUpdateAvailable, let update = updater.availableUpdate {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New Version: \(update.version)")
                            .font(.system(size: 13, weight: .bold))
                        Text(update.releaseNotes)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if updater.isDownloading {
                            ProgressView(value: updater.downloadProgress)
                                .progressViewStyle(.linear)
                        } else {
                            Button {
                                Task {
                                    await updater.performUpdate()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Update to Version \(update.version) Now")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.06))
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private var appInfoFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MACGUARD for macOS")
                    .font(.system(size: 12, weight: .bold))
                Text("Version 1.0.0 (Build 2026.11) • Private Build")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.top, 10)
    }

    // MARK: - Actions

    private func testOllamaConnection() {
        isTestingConnection = true
        let start = CFAbsoluteTimeGetCurrent()

        Task {
            let online = await OllamaService.shared.isServiceAvailable()
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            let fetchedModels = (try? await OllamaService.shared.fetchLocalModels()) ?? []

            await MainActor.run {
                self.isOllamaOnline = online
                self.connectionLatencyMs = elapsedMs
                self.models = fetchedModels
                self.isTestingConnection = false
                self.isConnectionSuccess = online

                if online {
                    self.connectionStatusBanner = "Connected to Ollama daemon (\(elapsedMs)ms latency) • \(fetchedModels.count) models available"
                } else {
                    self.connectionStatusBanner = "Ollama daemon unreachable at 127.0.0.1:11434. MacGuard is operating using native rule-based offline engine."
                }
            }
        }
    }

    private func resetAllSettings() {
        AppSettings.resetToDefaults()

        // Sync view local AppStorage bindings
        selectedOllamaModel = AppSettings.defaultSelectedModel
        customOllamaModel = AppSettings.defaultCustomModel
        enableBackgroundMonitoring = AppSettings.defaultEnableBackgroundMonitoring
        monitoringFrequencyMinutes = AppSettings.defaultMonitoringFrequencyMinutes
        enableDownloadsWatch = AppSettings.defaultEnableDownloadsWatch
        downloadsClutterThreshold = AppSettings.defaultDownloadsClutterThreshold
        lowStorageThresholdGB = AppSettings.defaultLowStorageThresholdGB
        enableAutoCleanupAlerts = AppSettings.defaultEnableAutoCleanupAlerts

        withAnimation {
            resetToastMessage = "Settings restored to defaults"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                self.resetToastMessage = nil
            }
        }
    }
}

public struct SecurityRuleRow: View {
    public let icon: String
    public let title: String
    public let desc: String

    public init(icon: String, title: String, desc: String) {
        self.icon = icon
        self.title = title
        self.desc = desc
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.green)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}
