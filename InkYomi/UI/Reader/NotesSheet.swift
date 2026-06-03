import SwiftUI

struct NotesSheet: View {
    let viewModel: ReaderViewModel
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            Picker("", selection: $selectedTab) {
                Text("Bookmarks").tag(0)
                Text("Highlights").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                if selectedTab == 0 {
                    bookmarksList
                } else {
                    highlightsList
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var bookmarksList: some View {
        List {
            if viewModel.bookmarks.isEmpty {
                ContentUnavailableView("No Bookmarks", systemImage: "bookmark")
            } else {
                ForEach(viewModel.bookmarks) { bookmark in
                    Button {
                        navigateToBookmark(bookmark)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.label ?? "Bookmark")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let chapter = bookmark.chapterTitle {
                                Text(chapter)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.deleteBookmark(id: bookmark.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var highlightsList: some View {
        List {
            if viewModel.highlights.isEmpty {
                ContentUnavailableView("No Highlights", systemImage: "highlighter")
            } else {
                ForEach(viewModel.highlights) { highlight in
                    Button {
                        navigateToHighlight(highlight)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let quote = highlight.quote {
                                Text(quote)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                            }
                            if let note = highlight.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color(hex: highlight.colorHex) ?? .yellow)
                                .frame(width: 3)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.deleteHighlight(id: highlight.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Menu("Change Color") {
                            ForEach(highlightColorOptions, id: \.self) { hex in
                                Button {
                                    viewModel.editHighlight(id: highlight.id, colorHex: hex, note: nil)
                                } label: {
                                    Label(colorName(hex), systemImage: "circle.fill")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private let highlightColorOptions = ["#F7D774", "#A8E6CF", "#FFB7B2", "#B5B9FF"]

    private func colorName(_ hex: String) -> String {
        switch hex {
        case "#F7D774": return "Yellow"
        case "#A8E6CF": return "Green"
        case "#FFB7B2": return "Pink"
        case "#B5B9FF": return "Blue"
        default: return "Color"
        }
    }

    private func navigateToBookmark(_ bookmark: ReaderBookmark) {
        viewModel.isNotesSheetVisible = false
        NotificationCenter.default.post(name: .readerNavigateToHref, object: bookmark.locatorJson)
    }

    private func navigateToHighlight(_ highlight: ReaderHighlight) {
        viewModel.isNotesSheetVisible = false
        NotificationCenter.default.post(name: .readerNavigateToHref, object: highlight.locatorJson)
    }
}

// Utility to create Color from hex
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b)
    }
}
