import SwiftUI

struct ReaderSettingsSheet: View {
    let viewModel: ReaderViewModel

    private let fontFamilies = ["serif", "sans-serif", "Georgia", "Palatino", "System"]
    private let highlightColors = ["#F7D774", "#A8E6CF", "#FFB7B2", "#B5B9FF"]

    var body: some View {
        NavigationStack {
            List {
                // Font Size
                Section("Font Size") {
                    HStack {
                        Text("A")
                            .font(.caption)
                        Slider(
                            value: Binding(
                                get: { viewModel.fontScale },
                                set: { viewModel.updateFontScale($0) }
                            ),
                            in: 0.8...1.8,
                            step: 0.1
                        )
                        .accessibilityLabel("Font size")
                        .accessibilityValue(String(format: "%.0f%%", viewModel.fontScale * 100))
                        Text("A")
                            .font(.title)
                    }
                    Text(String(format: "%.0f%%", viewModel.fontScale * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Line Height
                Section("Line Height") {
                    Slider(
                        value: Binding(
                            get: { viewModel.lineHeight },
                            set: { viewModel.updateLineHeight($0) }
                        ),
                        in: 1.0...2.5,
                        step: 0.1
                    )
                    .accessibilityLabel("Line height")
                    .accessibilityValue(String(format: "%.1f", viewModel.lineHeight))
                    Text(String(format: "%.1f", viewModel.lineHeight))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Page Margins
                Section("Margins") {
                    Slider(
                        value: Binding(
                            get: { viewModel.pageMargins },
                            set: { viewModel.updatePageMargins($0) }
                        ),
                        in: 0.5...2.0,
                        step: 0.1
                    )
                    .accessibilityLabel("Margins")
                    .accessibilityValue(String(format: "%.1f", viewModel.pageMargins))
                }

                // Font Family
                Section("Font") {
                    Picker("Font Family", selection: Binding(
                        get: { viewModel.fontFamily },
                        set: { viewModel.updateFontFamily($0) }
                    )) {
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Theme
                Section("Theme") {
                    HStack(spacing: 16) {
                        ForEach(ReaderTheme.allCases, id: \.self) { theme in
                            themeButton(theme)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                // Page Layout
                Section("Page Layout") {
                    Picker("Layout", selection: Binding(
                        get: { viewModel.pageLayout },
                        set: { viewModel.updatePageLayout($0) }
                    )) {
                        ForEach(ReaderPageLayout.allCases, id: \.self) { layout in
                            Text(layout.label).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func themeButton(_ theme: ReaderTheme) -> some View {
        Button {
            viewModel.updateTheme(theme)
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.previewBackground)
                    .frame(width: 60, height: 40)
                    .overlay {
                        Text("Aa")
                            .foregroundStyle(theme.previewText)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                viewModel.theme == theme ? Color.inkPrimary : .clear,
                                lineWidth: 2
                            )
                    )
                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(viewModel.theme == theme ? .isSelected : [])
    }
}

extension ReaderTheme {
    var displayName: String {
        switch self {
        case .light: "Light"
        case .sepia: "Sepia"
        case .dark: "Dark"
        }
    }

    var previewBackground: Color {
        switch self {
        case .light: .white
        case .sepia: Color(red: 245/255, green: 230/255, blue: 200/255)
        case .dark: Color(red: 26/255, green: 26/255, blue: 26/255)
        }
    }

    var previewText: Color {
        switch self {
        case .light: .black
        case .sepia: Color(red: 91/255, green: 70/255, blue: 54/255)
        case .dark: Color(red: 204/255, green: 204/255, blue: 204/255)
        }
    }
}
