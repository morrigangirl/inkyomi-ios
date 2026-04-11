import SwiftUI

struct HighlightEditorSheet: View {
    let viewModel: ReaderViewModel

    private let colorOptions = [
        "#F7D774",  // Yellow
        "#A8E6CF",  // Green
        "#FFB7B2",  // Pink
        "#B5B9FF",  // Purple
    ]

    var body: some View {
        NavigationStack {
            Form {
                if let quote = viewModel.pendingHighlight?.quote {
                    Section("Selected Text") {
                        Text(quote)
                            .font(.subheadline)
                            .italic()
                    }
                }

                Section("Color") {
                    HStack(spacing: 16) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button {
                                viewModel.pendingHighlight?.colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .yellow)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if viewModel.pendingHighlight?.colorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.black.opacity(0.6))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                Section("Note (optional)") {
                    TextField("Add a note...", text: Binding(
                        get: { viewModel.pendingHighlight?.note ?? "" },
                        set: { viewModel.pendingHighlight?.note = $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelPendingHighlight()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.confirmHighlight()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
