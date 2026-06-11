import SwiftUI

/// A reusable picker for one of the seven `AutoCompleteDebounceStep` values.
///
/// Renders as a menu (dropdown) style picker — compact enough for a settings form column.
/// Accepts a binding and a label string; no logic beyond binding and display.
public struct DebounceStepPicker: View {
    @Binding private var step: AutoCompleteDebounceStep
    private let label: String

    public init(label: String, step: Binding<AutoCompleteDebounceStep>) {
        self.label = label
        self._step = step
    }

    public var body: some View {
        Picker(label, selection: $step) {
            ForEach(AutoCompleteDebounceStep.allCases, id: \.self) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.menu)
    }
}
