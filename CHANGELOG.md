# Changelog

## Unreleased

### Added
- **Saved searches.** Bookmark a query+filter+sort combo and recall
  it with one tap. Backed by the new pearlescent-dream
  `/api/data/saved-searches` endpoints (migration 061).
  - **Save**: bookmark toolbar button in `SearchResultsView`'s filter
    sheet; visible only when filters or query are non-default. Tap →
    `.alert(...)` with text field (default = query or comma-joined
    tag slugs). Confirm → POST.
  - **List**: new "Saved searches" Section in `SearchView`'s empty-
    query state, above the existing Recent Searches section. Each
    row shows the name + a small subtitle summarising the filters.
    Swipe-to-delete on the row.
  - **Apply**: tap a saved row → routes to
    `SearchRoute.results(savedSearchId:)`; the ViewModel fetches the
    saved search via the repo and applies its query+filters+sort,
    bypassing the URL-encoded prefilledTagType/Slug path.
  - New `SavedSearch` domain model + `SavedSearchesAPIService` +
    `SavedSearchesDTOs` + `SavedSearchesRepository(Impl)`.
    `AnyJSONObject`/`AnyJSONValue` opaque-JSON helpers + `SearchFilters
    ↔ AnyJSONObject` translator alongside the repo so the saved
    blob round-trips cleanly through the backend's opaque jsonb
    column. `HTTPMethod` enum gained `.patch` so the update endpoint
    can use the right verb.

### Added
- **Combined Home payload via `/api/data/discover/home`.** The Home
  open is now one round trip instead of three (landing-page +
  browse-hub + trending). New `DiscoveryRepository.getDiscoverHome`
  is the primary fetch path; on failure (404 on a backend that
  hasn't deployed the discover/home route yet, or any 5xx) the
  ViewModel silently falls back to the legacy three-call fanout, so
  this ships safely before or after the backend deploy. Pearlescent-
  dream extracted the three handler bodies into shared loader
  functions and added the new combined endpoint.

### Added
- **Discovery revamp port — Phases 1, 2, and 3.** Brings the iOS app
  to parity with the Android sibling's discovery overhaul (LCP-Reader
  branch). All wiring is mobile-only — backend endpoints have been
  live since pearlescent-dream commit `8bbe9e3`.
  - **Phase 1: Home revamp.**
    - **Trending now** — single horizontal row of the top 12 trending
      books (`GET /api/data/books/trending?limit=12`), inserted between
      Continue Reading and Featured shelves.
    - **Browse the catalog** — vertical stack of section headers, each
      with a 2-column grid of "discovery tiles" pulled from
      `GET /api/data/categories/browse-hub`. Each tile shows a 3-cover
      fanned montage, the label, and the book count. Group key →
      tag-type mapping (`by-genre` → genre, `by-mood` → tone, etc.); tile
      taps route to a pre-filtered `SearchResultsView`. Non-tag groups
      (`by-series`, `by-character`, `featured`) render but their tile
      taps are inert until entity-based search lands.
    - `HomeViewModel` fans out the three home-feed network calls
      (landing-page, trending, browse-hub) in parallel via `async let`.
      Trending + browse-hub failures are swallowed so an outage on one
      new endpoint doesn't blank the Home screen.
    - The Home search bar is no longer an editable inline field — it's
      now a tap-to-navigate `SearchBarLink` that opens the Phase 2
      typeahead overlay.
  - **Phase 2: Search experience.**
    - **`SearchView`** — typeahead overlay. Auto-focuses, debounces
      250 ms to `/api/search/v2/suggest`, renders four grouped sections
      (Books / Authors / Series / Tags). Each row navigates: book →
      `BookDetailView`, author → `SearchResultsView?authorId=…`, series
      → `SearchResultsView?seriesId=…`, tag → `SearchResultsView`
      pre-filtered by tag_type + slug. Empty-query state shows recent
      searches with per-row × and a Clear button (or a hint when none
      persisted yet). Footer "Search for '<query>'" routes the raw
      query to full results.
    - **`SearchResultsView`** — full-screen results. Toolbar Sort menu
      (8 options from `SearchSortOrder`), Filter button with active-count
      badge, active-filter chip strip below the toolbar, adaptive
      `LazyVGrid` of result cards, infinite-scroll pagination via
      `onAppear` triggered when within 6 items of the loaded count.
      Filter sheet (Material-style `.presentationDetents([.medium, .large])`)
      with chip-cloud facet groups for the 8 tag types, paired
      Min/Max price `Slider`s (0..$50, $0/$50+ map to `nil`), and a
      single-thumb rating `Slider` (0..5 step 0.5).
    - `SearchViewModel` + `SearchResultsViewModel` use the
      `@MainActor @Observable` + `.configure()` pattern; cancellation
      uses `Task { try? await Task.sleep ... }` for debounce.
    - New `RecentSearchesPreferences` (UserDefaults-backed,
      `MainActor @Observable`, last 10, case-insensitive dedupe,
      MIN_LENGTH=2). Wired into `DependencyContainer.recentSearches`.
    - Defensive sort: blank-query searches default to `.newest` to
      avoid the pearlescent-dream relevance fallback bug
      (`fix/search-v2-relevance-no-query-bp-bug` not yet deployed).
  - **Phase 3: BookDetail polish.**
    - "More like this" rail at the bottom of `BookDetailView` (compact
      and regular layouts). Fetches `GET /api/data/books/:icin/related`
      after `book.icin` is known. Up to 12 covers in a horizontal
      `ScrollView`, each card showing cover + title + author + the
      strongest backend-provided "reason" line ("Same series", "Shares:
      Fantasy, Romance"). Tap → another BookDetail. Soft enhancement:
      failures are silent.
    - **Clickable tag chips**. Tap a tag → `SearchResultsView` filtered
      by that tag's `tag_type` axis + slug. Required threading
      `tag_type` through the wire format: `TagDto` gained a
      `tagType: String?` field, the `Tag` domain struct (new) carries
      `tagType: TagType?`, and `BookDetail.tags` is now `[Tag]` (was
      `[String]`). Tags whose `tag_type` didn't decode (legacy
      responses) become inert chips.
    - **Clickable author**. When `book.authors` has at least one entry,
      the "by …" line is primary-tinted and routes to
      `SearchResultsView?authorId=…`. Falls back to inert text when
      only the legacy flat `authorName` is set.
  - New domain models: `BrowseHubGroup`, `BrowseHubTile`, `TrendingBook`,
    `RelatedBook`, `Tag`, `TagType`, `SearchSortOrder`, `FacetGroup`,
    `FacetItem`, `SearchFilters`, `SearchResultBook`, `SearchResults`,
    `SuggestBook`, `SuggestEntity`, `SuggestTag`, `SuggestResults`.
    Existing `Book` extended with `icin: String?`; existing `BookDetail`
    extended with `icin: String?` and tag list upgraded to `[Tag]`.
  - New data layer: `DiscoveryAPIService`, `SearchAPIService`,
    `DiscoveryDTOs`, `SearchDTOs`, `DiscoveryRepository(Impl)`,
    `SearchRepository(Impl)`, `RecentSearchesPreferences`. Wired into
    `DependencyContainer`.
  - New navigation route: `SearchRoute` (`Hashable` enum with cases
    `.searchOverlay` / `.results(query, tagType, tagSlug, authorId, seriesId)`),
    registered on `HomeRoot`'s `NavigationStack`.

- Kindle-style sticky sessions. The session is now restored on app launch even when the access token has aged out and the immediate refresh fails for transient reasons (network down, server 5xx, ambiguous 401 with no `invalid_grant` body) — the user stays signed in with the cached profile and the next access-token request retries. New `AuthFailure` enum carries an explicit `terminal` flag, set true only when the auth server returns one of `invalid_grant` / `unauthorized_client` / `invalid_token` (RFC 6749 token-error JSON body). Manual sign-out via Settings → Profile → Sign out is unchanged and remains the canonical user-driven way out. Mirrors the Android `NativeAuthRepository` work shipped 2026-04-25.
- Proactive silent loan renewal. New `LoanRenewalCoordinator` (actor) walks active loans and silently renews any with `dueAt` within 48h that still have renewals available (`canRenew == true`). Triggered from two surfaces: a 24h `BGProcessingTask` (`LoanRenewalScheduler`, network-required, scheduled on app background and registered in `InkYomiApp.init`) and a one-shot fire from `MainTabView.task` once the user is in an authenticated state. The existing on-open auto-renew in `BookRepositoryImpl.ensureLendingDownloaded` is the third layer. Per-loan renewal failures are logged and swallowed; the BGTask always completes successfully so it never enters retry-with-backoff for normal "not yet eligible" rejections. Identifier `shop.inkcolors.InkYomi.loanRenewal` registered in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
- Account / Profile screen at Settings → Profile. Initials avatar bubble, email + display name, registered device count (live from `GET /api/data/devices`) with chevron link to the existing `DeviceListView`, and the destructive Sign out button (relocated from the Settings root).
- Settings revamp into top-level groups: **Account / Storage & data / Legal / Support**. New rows for Privacy Policy and Terms of Service (open `inkcolors.shop` in `SFSafariViewController`), Contact Support (mailto with prefilled subject including app version), About, and a destructive Delete-my-account row that opens a confirmation alert and then a prefilled mailto to `privacy@inkcolors.shop` for GDPR/CCPA deletion.
- About screen with version, "How your reading is counted" disclosure (telemetry on borrowed books is required for author royalties + lending-fraud detection; owned books are not instrumented), a sheet-launched link into the full Privacy Policy via Safari, and an open-source acknowledgements list.
- Storage management screen at Settings → Manage downloads. Reports cache size + file count for owned and borrowed downloads, with a confirmation-gated "Clear borrowed downloads" button that wipes `Documents/lending/` and reports bytes freed in a snackbar. Owned downloads are read-only on this screen by design.
- Loan expiry countdown badge on every card in the Library Borrowed tab. Surfaces "Due today / Due tomorrow / Due in N days / N days overdue" with urgency-tinted Material-style capsules (red for ≤ 0 days, orange for ≤ 3 days, neutral otherwise). New `LoanDisplay` projection in `Domain/Model/LoanDisplay.swift` parses `LoanInfo.dueAt` and exposes `dueLabel`, `urgency`, and a `renewalLabel` ("2 renewals left" / "Final renewal available" / "No renewals left") which is rendered under the title.
- `LinksHelper` (`SafariView` SwiftUI representable + `MailtoComposer`) for in-app legal-page rendering and prefilled email composition, alongside the canonical `InkColorsLinks` URL constants.

### Changed
- Hero carousel slot is now `.aspectRatio(5.0/2.0, contentMode: .fit)` (matching the production banner asset spec, e.g. Shadow Veil at 2400 × 960) instead of `HeroHeight.height(for: hSizeClass)` (a fixed 200 / 320 dp depending on size class). `bannerSlide(url:slide:)` simplified to `AsyncImage { image.resizable().scaledToFill() } placeholder: { Color.inkPrimary.opacity(0.1) }.clipped()` — `.scaledToFill()` is a no-op when slot and asset share an aspect, gracefully centre-crops anything off-spec; the focal-point alignment from `bannerSettings` still applies for off-spec assets so the important part of the image stays visible. The `isPhonePortrait` `.fit`/`.fill` branch is gone — every viewport now uses the same Crop+5:2 logic, eliminating the letterbox bars that previously appeared on iPhone portrait when an image-type slide had no `mobile_banner_url`. `HeroHeight` enum kept in `AdaptiveSize.swift` but no longer referenced; reserved for future iPad layout work. Supersedes the partial fix in commit 066aae5 (which switched to `.fit` and traded one symptom for another). Content-team note: author every new image-type hero banner at 2400 × 960 (5:2).
- App Transport Security tightened in `Info.plist`: `NSAppTransportSecurity` with `NSAllowsArbitraryLoads = false` and `NSAllowsLocalNetworking = false`. The app only ever talks to `https://inkcolors.shop`; staging exceptions should be added per-domain rather than disabling ATS globally.
- Telemetry is documented as TOS-mandatory rather than opt-out (see `AboutView.swift` "How your reading is counted" disclosure). Reading dwell-time on borrowed books is the input to author royalty payments and lending-fraud detection; there is no user-facing toggle. Owned books remain uninstrumented and are disclosed as the privacy carve-out.

### Notes
- All Swift code parses cleanly (`swiftc -parse` on every new and modified file). A full `xcodebuild` of the InkYomi target requires the **iOS 26.4 simulator runtime** to be installed via Xcode → Settings → Components — the current environment ships Xcode 26.4 with only the iOS 26.2 simulator runtime, which makes `ReadiumShared` and `Minizip` (Zip Swift package) fail to find their CoreVideo / IOSurface module maps. This is a toolchain issue, not an InkYomi code issue.
