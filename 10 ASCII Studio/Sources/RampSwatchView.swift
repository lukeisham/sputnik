import SwiftUI

/// Renders a character density ramp as a horizontal swatch over a black-to-white gradient.
///
/// Shows up to 20 characters so the user can see at a glance whether the ramp
/// runs light-to-dark or dark-to-light without doing a full conversion.
struct RampSwatchView: View {

    let characters: [String]

    private var displayChars: [String] {
        Array(characters.prefix(20))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, .white],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))

            if displayChars.isEmpty {
                Text("—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    ForEach(displayChars.indices, id: \.self) { i in
                        let progress = displayChars.count > 1
                            ? Double(i) / Double(displayChars.count - 1)
                            : 0.5
                        Text(displayChars[i])
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(progress < 0.5 ? .white : .black)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(height: 24)
    }
}
