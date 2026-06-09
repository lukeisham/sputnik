import SwiftUI

/// Settings tab for AI provider configuration.
///
/// Presents fields for model name, API key (stored in the Keychain via
/// `KeychainService`), and an optional base URL. Shows a status indicator
/// for the current API key state.
struct AISettingsView: View {
    let settings: SettingsStore

    @State private var apiKey: String = ""
    @State private var isKeySaved: Bool = false
    @State private var showKey: Bool = false
    @State private var keyStatusMessage: String = ""

    var body: some View {
        Form {
            // MARK: Model

            LabeledContent("Model") {
                TextField(
                    "e.g. claude-sonnet-4-20250514",
                    text: Binding(
                        get: { settings.aiConfig.modelName },
                        set: {
                            settings.setAIConfig(
                                AIConfiguration(modelName: $0, baseURL: settings.aiConfig.baseURL))
                        }
                    )
                )
                .frame(width: 260)
            }

            // MARK: API Key

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
                        // Load existing key on appear.
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

            // Key status
            if !keyStatusMessage.isEmpty {
                LabeledContent("") {
                    Text(keyStatusMessage)
                        .font(.caption)
                        .foregroundStyle(isKeySaved ? .secondary : .orange)
                }
            }

            // MARK: Base URL

            LabeledContent("Base URL") {
                HStack(spacing: 6) {
                    TextField(
                        "https://api.anthropic.com/v1",
                        text: Binding(
                            get: { settings.aiConfig.baseURL?.absoluteString ?? "" },
                            set: {
                                let url = $0.isEmpty ? nil : URL(string: $0)
                                settings.setAIConfig(
                                    AIConfiguration(
                                        modelName: settings.aiConfig.modelName, baseURL: url))
                            }
                        )
                    )
                    .frame(width: 260)

                    Button("Clear") {
                        settings.setAIConfig(
                            AIConfiguration(modelName: settings.aiConfig.modelName, baseURL: nil))
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.aiConfig.baseURL == nil)
                }
            }

            Divider()

            // Save button — persists both config (to UserDefaults) and API key (to Keychain).
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
    }

    /// Updates the key-status message and flag based on whether a key is already stored.
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
}
