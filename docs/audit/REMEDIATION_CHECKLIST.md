# Audit Remediation Checklist

Accessibility / privacy / performance / store-compliance audit of the InkYomi
reader apps (iOS `inkyomi-ios`, Android `inkyomi-reader`), 2026-06. This file
tracks remediation. Companion: [`STORE_LEGAL_DECISIONS.md`](./STORE_LEGAL_DECISIONS.md)
(the human/legal items).

**Status:** ✅ done · 🟡 in progress · ⬜ not started · 🧑‍⚖️ needs human/legal decision

**Hard constraint (every item):** minimal patch — no redesign and no change to
architecture, reader behavior, entitlement logic, payments, authentication, or
backend APIs unless a specific compliance/accessibility issue requires it.

**Golden path (must never regress):** sign in → browse library → open book →
read → bookmark → settings → logout.

## Phases
| Phase | Scope | Status |
|------|-------|--------|
| 0 | Human/legal decisions, started Day 0 in parallel (C3, H9, H10, C1-label) | 🧑‍⚖️ |
| 1 | Store-unblock + quick wins: C1, C2, H7 | ✅ |
| 2 | Test net (regression guards + manual AT scripts) | 🟡 |
| 3 | Accessibility (additive labels / announcements / contrast / Dynamic Type) | ⬜ |
| 4 | Stability / performance (C6, H8, M8–M10) | ⬜ |
| 5 | Privacy hardening (M1–M3) | ⬜ |
| 6 | Polish / i18n + C3 code once the entitlement decision lands | ⬜ |

## Critical
| ID | Finding | Platform | Phase | Status |
|----|---------|----------|-------|--------|
| C1 | App Store privacy manifest missing from shippable app | iOS | 1 | ✅ `PrivacyInfo.xcprivacy` added; verified at `.app` root |
| C2 | Account deletion mailto-only → in-app deletion | both | 1 | ✅ wired to `/deletion-request`; email fallback kept |
| C3 | External "buy on website" buttons for digital goods | both | 0 | 🧑‍⚖️ decision D1 |
| C4 | iOS reader controls unlabeled (VoiceOver) | iOS | 3 | ⬜ port Android `contentDescription`s |
| C5 | iOS Return/Renew/Lending icon menus unlabeled | iOS | 3 | ⬜ |
| C6 | Large-EPUB license-injection buffers whole ZIP → OOM | both | 4 | ⬜ stream entry bytes |

## High
| ID | Finding | Platform | Phase | Status |
|----|---------|----------|-------|--------|
| H1 | iOS covers unlabeled + cards fragment | iOS | 3 | ⬜ hide cover + `.accessibilityElement(.combine)` |
| H2 | Loading/error not announced to screen readers | both | 3 | ⬜ live regions / announcements |
| H3 | Highlight color swatches color-only | both | 3 | ⬜ name + selected semantics |
| H4 | iOS book descriptions ignore Dynamic Type | iOS | 3 | ⬜ `HTMLTextView` font strip |
| H5 | iOS reader font/theme controls lack AT value/selected state | iOS | 3 | ⬜ |
| H6 | Due-date badge + success text fail WCAG contrast | iOS | 3 | ⬜ opaque tones |
| H7 | Unconditional reader debug file-logging | iOS | 1 | ✅ gated `#if DEBUG`; scaffold removed |
| H8 | iOS owned covers full-res, no downsampling | iOS | 4 | ⬜ card-variant DTO + downsample |
| H9 | Mature catalog vs age/content rating | both | 0 | 🧑‍⚖️ decision D2 |
| H10 | App Privacy label / Play Data Safety accuracy | both | 0 | 🧑‍⚖️ decision D3 |

## Medium
| ID | Finding | Platform | Phase |
|----|---------|----------|-------|
| M1 | Access token + PII in plaintext (UserDefaults / DataStore) | both | 5 |
| M2 | iOS logout leaves reading data / downloads / DRM secrets / search | iOS | 5 |
| M3 | Android sign-out leaves PII / LCP secrets / downloads (`UserDataWipe` exists) | Android | 5 |
| M4 | Material You dynamic color overrides verified palette | Android | 3 (🧑‍⚖️ design) |
| M5 | Hero overlay text contrast over banner art | both | 3 |
| M6 | EPUB paginated; no AT-aware scroll fallback | both | 3 |
| M7 | Reading progress not surfaced meaningfully to AT | both | 3 |
| M8 | iOS owned-book download writes whole EPUB on MainActor | iOS | 4 |
| M9 | Resource-decrypt LRU bounded by count, not bytes | both | 4 |
| M10 | iOS hero `AsyncImage` no caching (refetch each appearance) | iOS | 4 |
| M11 | iOS titles/authors clip under large Dynamic Type | iOS | 3 |
| M12 | iOS section headers not exposed as headings | iOS | 3 |
| M13 | Android borrowed card nested clickables confuse TalkBack | Android | 3 |
| M14 | Android hero banner unlabeled when `bannerAlt` is null | Android | 3 |

## Low (batch into Phase 3 / 6)
- **iOS:** sub-44pt touch targets (Revoke / chips / clear); auth error not field-associated; borrowed cover `onTapGesture` not an AT action; notes color cue visual-only; decode-error logs response body (mark `privacy: .private`).
- **Android:** brightness slider unlabeled + emoji; filter-count not in Filters label; hero pager position not announced; continue-reading progress no spoken context; English-only AT strings (i18n); debug-only OkHttp BODY logging (release-safe).
- **Both:** LCP passphrase = `SHA-256(email)` (DRM design note, not a client flaw); Android load-all-then-filter + dead loan query (`LsdStatusChecker` / `LendingRepositoryImpl` → `getLoanById`); Android book-open crypto on the main dispatcher.

## Phase-1 delivered
- **iOS** PR #20 (`fix/ios-store-compliance-phase1`) — C1, C2, H7 + `InkYomiTests/AccountDeletionDecodingTests`.
- **Android** PR #13 (`fix/android-store-compliance-phase1`) — C2 + `AccountDeletionDtoTest`.

## Test net (Phase 2)
**Automated guards added (this work):**
- iOS `InkYomiTests/AccountDeletionDecodingTests` — `xcodebuild build-for-testing` → TEST BUILD SUCCEEDED.
- Android `AccountDeletionDtoTest` — `./gradlew :app:testProdDebugUnitTest --tests "*AccountDeletionDtoTest"` → BUILD SUCCESSFUL.

**To add (needs CI / device wiring):**
- iOS XCUITest target running `app.performAccessibilityAudit()` over the golden path (catches missing labels, contrast, clipped text, hit-region — maps to C4/C5/H1/H4/H6).
- Android instrumented tests: new `androidTest` source set + `AccessibilityChecks.enable()` (Espresso) + Compose semantics assertions; wire the Play pre-launch report.
- Large-EPUB memory test around license injection (guards C6).

**Manual AT scripts (no substitute):** VoiceOver + TalkBack pass of the golden
path, confirming every control is named, loading/errors are announced, and
headings/values read; Dynamic Type / `fontScale` at max; light+dark contrast via
Accessibility Inspector / Accessibility Scanner.

**Per-PR gate:** compile + the finding's "tests after fix" + golden-path smoke +
no new accessibility-audit or profiler regressions.
