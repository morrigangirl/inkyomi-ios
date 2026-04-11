import SwiftUI

struct CartView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel = CartViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("Cart Empty", systemImage: "cart", description: Text("Add books to get started."))
            } else {
                List {
                    ForEach(viewModel.items) { item in
                        HStack(spacing: 12) {
                            BookCoverView(url: item.coverUrl, width: 50, height: 75)
                            VStack(alignment: .leading) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                if let author = item.authorName {
                                    Text(author)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(String(format: "$%.2f", item.priceUsd))
                                .font(.subheadline.weight(.semibold))
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                Task { await viewModel.removeItem(bookId: item.bookId) }
                            }
                        }
                    }

                    Section {
                        HStack {
                            Text("Total")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "$%.2f", viewModel.total))
                                .font(.headline)
                        }

                        Button {
                            Task { await viewModel.checkout() }
                        } label: {
                            Text("Checkout")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.inkPrimary)
                    }
                }
            }
        }
        .navigationTitle("Cart")
        .sheet(isPresented: $viewModel.showCheckout) {
            if let url = viewModel.checkoutURL {
                SafariViewRepresentable(url: url)
            }
        }
        .task {
            viewModel.configure(checkoutRepository: container.checkoutRepository)
            await viewModel.loadCart()
        }
    }
}
