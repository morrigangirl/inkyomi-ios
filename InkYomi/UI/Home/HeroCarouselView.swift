import SwiftUI

struct HeroCarouselView: View {
    let slides: [HeroSlide]
    @State private var currentIndex = 0

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                heroSlideCard(slide)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 200)
    }

    @ViewBuilder
    private func heroSlideCard(_ slide: HeroSlide) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let urlString = slide.bannerImageUrl,
               let url = URL(string: urlString, relativeTo: URL(string: "https://inkcolors.shop")) ?? URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.inkPrimary.opacity(0.1))
                }
            } else {
                Rectangle()
                    .fill(Color.inkPrimary.opacity(0.2))
            }

            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow = slide.eyebrow {
                    Text(eyebrow)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                if let book = slide.book {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.6), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
