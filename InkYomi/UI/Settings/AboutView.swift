import SwiftUI

struct AboutView: View {
    @State private var showingPrivacy = false

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("InkColors Reader")
                    .font(.largeTitle.weight(.semibold))
                Text(versionString)
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 8)

                Text("How your reading is counted")
                    .font(.headline)
                Text(disclosureText)
                    .font(.body)

                Button {
                    showingPrivacy = true
                } label: {
                    Text("Read the full Privacy Policy →")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .foregroundStyle(Color.inkPrimary)
                }

                Divider().padding(.vertical, 8)

                Text("Open-source acknowledgements")
                    .font(.headline)
                ForEach(attributions, id: \.self) { line in
                    HStack(alignment: .top) {
                        Text("•").foregroundStyle(.secondary)
                        Text(line).font(.callout)
                    }
                }

                Spacer(minLength: 24)

                Text("© InkColors. All rights reserved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPrivacy) {
            SafariView(url: InkColorsLinks.privacyURL)
                .ignoresSafeArea()
        }
    }

    private let disclosureText = """
        InkColors is a lending platform. When you borrow a book, the app records how long you spend on each labelled span of the text. That dwell time is what pays the author and lets us catch borrow-and-rip abuse. It is required for the service to function — there is no opt-out.

        Books you purchase outright are not instrumented and send no telemetry. Returning a borrowed book stops telemetry collection for that loan immediately.
        """

    private let attributions: [String] = [
        "Readium Swift Toolkit (BSD-3-Clause)",
        "SwiftUI & Foundation (Apple)",
        "Nuke image loading (MIT)",
        "ZIPFoundation (MIT)",
        "CryptoKit (Apple)",
        "ZIP Foundation, GCDWebServer, Fuzi via Readium",
    ]
}
