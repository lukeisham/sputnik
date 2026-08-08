import SwiftUI

struct ASCIIStudioLibraryView: View {
    @Bindable var model: ASCIIStudioModel
    let library: ASCIILibraryBrowser
    @ObservedObject var imageEditor: ASCIIImageEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search library…", text: $model.librarySearchQuery)

            Picker("Category:", selection: $model.selectedCategory) {
                ForEach(ASCIILibraryBrowser.Category.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!model.librarySearchQuery.isEmpty)

            let clips = filteredClips
            if clips.isEmpty {
                VStack {
                    Spacer()
                    Text(model.librarySearchQuery.isEmpty
                        ? "No clips available for \(model.selectedCategory.rawValue)."
                        : "No clips match \"\(model.librarySearchQuery)\".")
                        .foregroundStyle(.secondary)
                    if model.librarySearchQuery.isEmpty {
                        Text("Add .txt files to Resources/ASCIILibrary/\(model.selectedCategory.rawValue)/")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 200))],
                        spacing: 8
                    ) {
                        ForEach(clips) { clip in clipCard(clip) }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
    }

    private var filteredClips: [ASCIILibraryBrowser.Clip] {
        if model.librarySearchQuery.isEmpty {
            return library.clips(for: model.selectedCategory)
        }
        return ASCIILibraryBrowser.Category.allCases
            .flatMap { library.clips(for: $0) }
            .filter { $0.name.localizedCaseInsensitiveContains(model.librarySearchQuery) }
    }

    private func clipCard(_ clip: ASCIILibraryBrowser.Clip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(clip.name)
                .font(.caption.bold())
                .lineLimit(1)
            Text(clip.content)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(8)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Insert") {
                    guard let tv = ASCIIStudioCoordinator.activeTextView() else { return }
                    library.insert(clip, into: tv)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Edit") {
                    imageEditor.load(clip.content, targetColumns: 80)
                    model.sourceImageName = clip.name
                    model.selectedTab = .imageToASCII
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
