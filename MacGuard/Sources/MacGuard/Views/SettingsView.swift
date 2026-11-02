import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var updater = AutoUpdateManager.shared
    @State private var isOllamaOnline: Bool = false
    @State private var models: [OllamaModelInfo] = []
    @State private var enableDownloadsWatch: Bool = true
    @State private var lowStorageThreshold: Double = 15.0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings & Model Management")
                        .font(.system(size: 22, weight: .bold))
                    Text("Configure your local AI inference, privacy rules, and background monitoring")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Divider()

                // AI Engine Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("Local AI Intelligence Model")
                        .font(.system(size: 14, weight: .bold))

                    VStack(spacing: 12) {
                        HStack {
                            ZStack {
                                Circle().fill(Color.green.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "cpu")
                                    .foregroundColor(.green)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Native Standalone AI Engine (No Ollama Required)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("On-Demand Metal Lifecycle • 0 MB Unified Memory when Idle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }

                            Spacer()

                            Text("0 MB Idle RAM")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hardware Acceleration")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Apple Silicon Metal (15-Core GPU)")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Inference Runtime")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Native Embedded / Standalone")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("RAM Management")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Lazy Load & Instant Unload")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)
                }

                // Privacy & Security Safeguards
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

                // Background Monitoring
                VStack(alignment: .leading, spacing: 14) {
                    Text("Background Monitoring")
                        .font(.system(size: 14, weight: .bold))

                    VStack(spacing: 12) {
                        Toggle(isOn: $enableDownloadsWatch) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Monitor Downloads Accumulation")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Notifies when Downloads clutter exceeds 40 unorganized items")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Low Storage Warning Threshold")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text("\(Int(lowStorageThreshold)) GB")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Slider(value: $lowStorageThreshold, in: 5...50, step: 5)
                            Text("Alerts you before APFS startup disk becomes constrained.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)
                }

                // Live Auto-Update Section (Vercel Edge Distribution)
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

                // App Info
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
            .padding(24)
        }
        .onAppear {
            checkStatus()
            Task {
                await updater.checkForUpdates(isUserInitiated: false)
            }
        }
    }

    private func checkStatus() {
        Task {
            let online = await OllamaService.shared.isServiceAvailable()
            let fetchedModels = (try? await OllamaService.shared.fetchLocalModels()) ?? []
            await MainActor.run {
                self.isOllamaOnline = online
                self.models = fetchedModels
            }
        }
    }
}

struct SecurityRuleRow: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
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
