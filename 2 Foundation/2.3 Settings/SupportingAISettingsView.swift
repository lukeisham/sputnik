import SwiftUI

/// Settings tab for Supporting AI provider configuration.
///
/// The Supporting AI is the app's built-in AI service used exclusively for resource
/// features: help lookups, completions, and More Context. This is NOT the Main AI
/// (the user-loaded AI in the terminal).
///
/// Presents a provider selector (DeepSeek / Gemini / Local), model name field, API
/// key field (Keychain-backed via `KeychainService`), optional base URL override,
/// and live session-usage metrics.
struct SupportingAISettingsView: View {
    let settings: SettingsStore
    let supportingAIMonitor: SupportingAIMonitor?
    @Environment(AppState.self) private var appState

    @State private var apiKey: String = ""
    @State private var isKeySaved: Bool = false
    @State private var showKey: Bool = false
    @State private var keyStatusMessage: String = ""

    var body: some View {
        Form {
            // MARK: Provider
            Section {
                LabeledContent("Provider") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { settings.supportingAIConfig.provider },
                            set: { newProvider in
                                let current = settings.supportingAIConfig
                                settings.setSupportingAIConfig(
                                    SupportingAIConfiguration(
                                        provider: newProvider,
                                        modelName: current.modelName,
                                        baseURL: current.baseURL
                                    ))
                            }
                        )
                    ) {
                        ForEach(SupportingAIProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue.capitalized).tag(provider)
                        }
                    }
                    .frame(width: 160)
                }
            }

            // MARK: Model
            Section {
                LabeledContent("Model") {
                    TextField(
                        "e.g. deepseek-chat",
                        text: Binding(
                            get: { settings.supportingAIConfig.modelName },
                            set: {
                                let current = settings.supportingAIConfig
                                settings.setSupportingAIConfig(
                                    SupportingAIConfiguration(
                                        provider: current.provider,
                                        modelName: $0,
                                        baseURL: current.baseURL
                                    ))
                            }
                        )
                    )
                    .frame(width: 260)
                }
            }

            // MARK: API Key
            Section {
                LabeledContent("API Key") {
                    HStack(spacing: 6) {
                        Group {
                            if showKey {
                                TextField("Paste your API key", text: $apiKey)
                            } else {
                                SecureField("Paste your API key", text: $apiKey)
                            }
                        }
                        .frame(width: 200)
                        .onAppear {
                            apiKey = KeychainService.load() ?? ""
                            updateKeyStatus()
                        }

                        Button(showKey ? "Hide" : "Show") {
                            showKey.toggle()
                        }
                        .buttonStyle(.borderless)

                        Button("Clear") {
                            apiKey = ""
                            do {
                                try KeychainService.delete()
                                isKeySaved = false
                                keyStatusMessage = "Key cleared"
                            } catch {
                                keyStatusMessage = "Failed to clear key"
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(apiKey.isEmpty)
                    }
                }

                if !keyStatusMessage.isEmpty {
                    LabeledContent("") {
                        Text(keyStatusMessage)
                            .font(.caption)
                            .foregroundStyle(isKeySaved ? .secondary : .orange)
                    }
                }
            }

            // MARK: Base URL
            Section {
                LabeledContent("Base URL") {
                    HStack(spacing: 6) {
                        TextField(
                            settings.supportingAIConfig.provider.defaultBaseURL.absoluteString,
                            text: Binding(
                                get: { settings.supportingAIConfig.baseURL?.absoluteString ?? "" },
                                set: {
                                    let url = $0.isEmpty ? nil : URL(string: $0)
                                    let current = settings.supportingAIConfig
                                    settings.setSupportingAIConfig(
                                        SupportingAIConfiguration(
                                            provider: current.provider,
                                            modelName: current.modelName,
                                            baseURL: url
                                        ))
                                }
                            )
                        )
                        .frame(width: 260)

                        Button("Default") {
                            let current = settings.supportingAIConfig
                            settings.setSupportingAIConfig(
                                SupportingAIConfiguration(
                                    provider: current.provider,
                                    modelName: current.modelName,
                                    baseURL: nil
                                ))
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.supportingAIConfig.baseURL == nil)
                    }
                }

                Text(
                    "Leave empty to use the provider default: \(settings.supportingAIConfig.provider.defaultBaseURL.absoluteString)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // MARK: Save
            Section {
                HStack {
                    Button("Save") {
                        do {
                            try KeychainService.save(key: apiKey)
                            isKeySaved = true
                            keyStatusMessage = "API key saved to Keychain"
                        } catch {
                            isKeySaved = false
                            keyStatusMessage = "Error: \(error.localizedDescription)"
                        }
                    }
                    .keyboardShortcut(.defaultAction)

                    Text("Your API key is stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Usage (this session)
            if let usage = appState.supportingAIUsage {
                Section("Usage (This Session)") {
                    LabeledContent("Model") {
                        Text(settings.supportingAIConfig.modelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Context Window") {
                        ProgressView(
                            value: usage.percentUsed,
                            total: 100
                        )
                        .frame(width: 120)
                        Text(String(format: "%.1f%%", usage.percentUsed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50)
                    }

                    LabeledContent("Tokens Used") {
                        Text(formattedTokens(usage.totalTokensSinceLaunch))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updateKeyStatus() {
        let loaded = KeychainService.load() ?? ""
        if !loaded.isEmpty {
            isKeySaved = true
            keyStatusMessage = "Key is stored in Keychain"
        } else {
            isKeySaved = false
            keyStatusMessage = "No API key set"
        }
    }

    private func formattedTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: count)) ?? "\(count)") + " tokens"
    }
}
