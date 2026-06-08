import SwiftUI

public struct TitleBar: View {
    let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title)
            .font(.headline)
            .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview {
    TitleBar("Sputnik")
}
#endif
