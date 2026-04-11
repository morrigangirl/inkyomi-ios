import SwiftUI

struct SearchBarView: View {
    let query: String
    let onQueryChanged: (String) -> Void
    let onClear: () -> Void

    @State private var text = ""

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search books...", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text) { _, newValue in
                    onQueryChanged(newValue)
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
