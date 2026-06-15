import Foundation
import SwiftUI

// MARK: - Pending request model

/// Carries a selected template and its raw content to the placeholder-expansion sheet.
///
/// `Identifiable` so it can drive `.sheet(item:)` on `ContentView`.
public struct TemplatePendingRequest: Identifiable, Sendable {
    public let id: UUID
    public let record: TemplateRecord
    public let rawContent: String

    public init(record: TemplateRecord, rawContent: String) {
        self.id = UUID()
        self.record = record
        self.rawContent = rawContent
    }
}

// MARK: - Sheet view

/// Presents a text field for each `{{key}}` placeholder found in the selected template.
///
/// If the template has no placeholders the sheet never appears — `AppState.openTemplate`
/// calls `openTemplateDocument` directly instead.
public struct TemplatePlaceholderSheet: View {

    public let request: TemplatePendingRequest
    public let onConfirm: ([String: String]) -> Void

    /// One entry per unique placeholder key, in order of first appearance.
    private let keys: [String]

    /// The live field values, seeded with auto-defaults (e.g. today's date).
    @State private var values: [String: String]

    public init(request: TemplatePendingRequest, onConfirm: @escaping ([String: String]) -> Void) {
        self.request = request
        self.onConfirm = onConfirm
        let discovered = TemplatePlaceholderExpander.placeholders(in: request.rawContent)
        self.keys = discovered
        _values = State(initialValue: TemplatePlaceholderExpander.defaultValues(for: discovered))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fill in Placeholders")
                .font(.headline)

            Text("Template: \(request.record.name).\(request.record.fileExtension)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(keys, id: \.self) { key in
                LabeledContent(key.capitalized) {
                    TextField(key, text: Binding(
                        get: { values[key, default: ""] },
                        set: { values[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onConfirm([:])
                }
                .keyboardShortcut(.cancelAction)

                Button("Open") {
                    onConfirm(values)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hasEmptyRequiredField)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// `true` when any non-date key has an empty value — blocks the Open button.
    private var hasEmptyRequiredField: Bool {
        keys.contains { key in
            key != "date" && values[key, default: ""].trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
