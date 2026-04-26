import SwiftUI

struct HeroCarouselView: View {
    let slides: [HeroSlide]
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var currentIndex = 0

    /// iPhone in portrait: compact width + regular height. Banner images get
    /// awkwardly cropped at this aspect, so we fit-not-fill there only.
    private var isPhonePortrait: Bool {
        hSizeClass == .compact && vSizeClass == .regular
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                heroSlideCard(slide)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: HeroHeight.height(for: hSizeClass))
    }

    @ViewBuilder
    private func heroSlideCard(_ slide: HeroSlide) -> some View {
        let clickable = slide.book != nil && (slide.bannerSettings?.isClickable ?? true)
        Group {
            if clickable, let book = slide.book {
                NavigationLink(value: book.id) {
                    slideContent(slide)
                }
                .buttonStyle(.plain)
            } else {
                slideContent(slide)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func slideContent(_ slide: HeroSlide) -> some View {
        if let urlString = effectiveBannerUrl(for: slide), let url = resolveURL(urlString) {
            bannerSlide(url: url, slide: slide)
        } else if let book = slide.book {
            bookCoverSlide(book: book, slide: slide)
        } else {
            fallbackSlide(slide: slide)
        }
    }

    @ViewBuilder
    private func bannerSlide(url: URL, slide: HeroSlide) -> some View {
        let fitMode: ContentMode = isPhonePortrait ? .fit : .fill
        // .fit is centered; focal-point alignment only matters for .fill cropping.
        let alignment: Alignment = isPhonePortrait
            ? .center
            : focalAlignment(for: slide.bannerSettings)
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Color.inkPrimary.opacity(0.1)   // letterbox fill when .fit leaves gaps
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: fitMode)
                } placeholder: {
                    Rectangle().fill(Color.inkPrimary.opacity(0.1))
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
                .clipped()

                textOverlay(slide)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func bookCoverSlide(book: Book, slide: HeroSlide) -> some View {
        HStack(spacing: 16) {
            BookCoverView(
                url: book.coverUrl,
                width: CoverSize.continueRow.width(for: hSizeClass),
                height: CoverSize.continueRow.height(for: hSizeClass)
            )

            VStack(alignment: .leading, spacing: 6) {
                if let eyebrow = slide.eyebrow {
                    Text(eyebrow)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                if let author = book.authorName {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.inkPrimary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func fallbackSlide(slide: HeroSlide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow = slide.eyebrow {
                Text(eyebrow)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.inkPrimary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func textOverlay(_ slide: HeroSlide) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    // MARK: - Resolution helpers

    private func effectiveBannerUrl(for slide: HeroSlide) -> String? {
        // Prefer mobile-specific banner on compact size class when available.
        if hSizeClass == .compact,
           let mobile = slide.bannerSettings?.mobileBannerUrl,
           !mobile.isEmpty {
            return mobile
        }
        return slide.bannerImageUrl
    }

    /// Maps server focal-point percentages to one of nine SwiftUI alignments.
    /// Approximates web's continuous `object-position` — pixel-perfect focal
    /// would require knowing the loaded image's natural dimensions; the 9-point
    /// quantization matches the server's overlayPosition vocabulary anyway.
    private func focalAlignment(for settings: BannerSettings?) -> Alignment {
        let fx = effectiveFocalX(settings)
        let fy = effectiveFocalY(settings)
        let h: HorizontalAlignment = fx < 33 ? .leading : (fx > 67 ? .trailing : .center)
        let v: VerticalAlignment = fy < 33 ? .top : (fy > 67 ? .bottom : .center)
        return Alignment(horizontal: h, vertical: v)
    }

    private func effectiveFocalX(_ settings: BannerSettings?) -> Double {
        guard let settings else { return 50 }
        if hSizeClass == .compact, let m = settings.mobileFocalX { return m }
        return settings.focalX ?? 50
    }

    private func effectiveFocalY(_ settings: BannerSettings?) -> Double {
        guard let settings else { return 50 }
        if hSizeClass == .compact, let m = settings.mobileFocalY { return m }
        return settings.focalY ?? 50
    }

    private func resolveURL(_ urlString: String) -> URL? {
        URL(string: urlString, relativeTo: URL(string: "https://inkcolors.shop")) ?? URL(string: urlString)
    }
}
