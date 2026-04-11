import SwiftUI

struct TocSheet: View {
    let tocItems: [TocItem]
    let onItemSelected: (TocItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(flattenedItems) { item in
                    Button {
                        onItemSelected(item)
                    } label: {
                        Text(item.title)
                            .padding(.leading, CGFloat(item.depth) * 16)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Table of Contents")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var flattenedItems: [TocItem] {
        var result: [TocItem] = []
        func flatten(_ items: [TocItem]) {
            for item in items {
                result.append(item)
                flatten(item.children)
            }
        }
        flatten(tocItems)
        return result
    }
}
