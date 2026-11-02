import SwiftUI

public struct SettingsView: View {
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
                                Circle().fill(isOllamaOnline ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "cpu")
                                    .foregroundColor(isOllamaOnline ? .green : .orange)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("MacGuard AI Specialized Engine (macguard-ai:latest)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(isOllamaOnline ? "Engine Online • Metal Hardware Accelerated" : "Local Standalone Fallback Active")
                                    .font(.system(size: 11))
                                    .foregroundColor(isOllamaOnline ? .green : .orange)
                            }

                            Spacer()

                            Text("2.5 GB RAM")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(6)
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hardware Architecture")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Apple M5 Pro (15-core unified memory)")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Inference Engine")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Ollama 0.33.3 (localhost:11434)")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Inference Speed")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("~110 tokens/sec")
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
