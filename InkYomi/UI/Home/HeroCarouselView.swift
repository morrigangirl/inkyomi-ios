import SwiftUI

struct HeroCarouselView: View {
    let slides: [HeroSlide]
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var currentIndex: Int? = 0

    var body: some View {
        // Native iOS 17 paged horizontal scroll. We deliberately avoid
        // `TabView(.page)` here: the UIPageViewController it wraps eats
        // short tap gestures before NavigationLink can pick them up, so
        // hero slides with `book` payloads stopped navigating reliably.
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        heroSlideCard(slide)
                            // Fill the ScrollView's width. 5:2 matches the
                            // production banner asset spec (e.g. 2400×960);
                            // compliant banners fill the slot edge-to-edge.
                            .containerRelativeFrame(.horizontal)
                            .aspectRatio(5.0 / 2.0, contentMode: .fit)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentIndex)

            if slides.count > 1 {
                pageIndicator
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<slides.count, id: \.self) { index in
                Circle()
                    .fill((currentIndex ?? 0) == index
                          ? Color.inkPrimary
                          : Color.inkPrimary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentIndex)
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
        // The carousel slot is now pinned to 5:2 (banner asset spec), so a
        // compliant banner fills it perfectly with `.scaledToFill()`. The
        // `.clipped()` keeps off-spec assets from spilling over the corners.
        // Focal-point alignment via `bannerSettings` is preserved for the
        // off-spec case so the important part of the image stays visible.
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.inkPrimary.opacity(0.1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: focalAlignment(for: slide.bannerSettings))
            .clipped()

            textOverlay(slide)
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
