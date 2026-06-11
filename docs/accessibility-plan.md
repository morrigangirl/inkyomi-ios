# InkYomi Accessibility Remediation Plan

Status: proposed · Owner: TBD · Created from the 1.0.0 (build 2) accessibility audit.

## Goal

Close the accessibility gaps found in the build-2 audit, **prioritizing the Reader** — the
core experience for blind and low-vision users — and add **spoken read-aloud** so blind
users can actually consume a book, not just navigate the UI.

## Where we are today (1.0.0 / build 2)

Already shipped: VoiceOver labels (16), combined book cards, header traits, reading-progress
value, live status/page-turn announcements, decorative covers hidden, a reader rotor action;
Dynamic Type via semantic fonts; full dark mode + WCAG 2.2 AA contrast palette; keyboard
shortcuts + focus.

**Gaps this plan addresses:**

| Gap | Severity | Today |
|---|---|---|
| Reader **read-aloud / TTS** | **P0** | none — does not exist |
| VoiceOver **book-content** read-through audit | **P0** | partial (nav announcements exist; content path unverified) |
| **Reduce Motion** | P1 | not observed |
| **Reduce Transparency** | P1 | not observed (reader chrome is `ultraThinMaterial`) |
| **Increase Contrast** (`colorSchemeContrast`) | P1 | not observed |
| **Differentiate Without Color** | P2 | not observed (highlights coded by hue) |
| **Bold Text** (`legibilityWeight`) | P2 | inherited from system fonts only |

---

## P0 — Reader, for blind users

### P0-1 · Read-aloud (Text-to-Speech) in the Reader

**Why:** VoiceOver lets a blind user *navigate* the book word-by-word, but there is no
continuous narration. iOS "Speak Screen" only reads the visible page and won't auto-advance
a paginated reader. Blind and low-vision readers need an audiobook-style read-aloud that
flows across pages and chapters.

**Approach — integrate Readium's TTS (don't build from scratch):**
- Wrap `ReadiumNavigator.PublicationSpeechSynthesizer` (backed by `AVTTSEngine` /
  `AVSpeechSynthesizer`). Reference: swift-toolkit `TestApp/.../TTS/TTSViewModel.swift`.
- It tokenizes the publication into utterances, speaks them, emits the current utterance/range
  for **sentence highlighting**, and drives navigation so playback **auto-advances** across
  pages and chapters.
- New `ReaderTTSController` owned by `ReaderViewModel`; wire into `EPUBReaderRepresentable`/
  `ReaderView`.

**UI:**
- Play/Pause "Read aloud" control in the reader chrome (clearly labeled for VoiceOver).
- Rate + voice picker in `ReaderSettingsSheet` (default to the system-selected voice/rate).
- Visually highlight the sentence being spoken (helps low-vision + dyslexic readers too).

**Background audio + lock-screen control (required for real use):**
- Add `audio` to `UIBackgroundModes` in `Info.plist`.
- Configure `AVAudioSession` category `.playback`; handle interruptions + route changes.
- Populate `MPNowPlayingInfoCenter` and wire `MPRemoteCommandCenter` (play/pause/skip) so a
  blind user can control narration from the lock screen / headphones without looking.

**Acceptance:**
- Start read-aloud and hear the book spoken **continuously across page and chapter breaks**.
- Pause/resume; change rate/voice; spoken sentence is highlighted on screen.
- Control playback from the lock screen and headset; survives screen lock and interruptions.

**Effort:** L (the headline item). **Risk:** medium (background audio + nav sync).

### P0-2 · VoiceOver book-content read-through audit

**Why:** confirm a blind user can read the *content* (not just the chrome). The reader renders
EPUB HTML via Readium's GCDWebServer; VoiceOver should expose it, but it must be verified.

**Do:**
- VoiceOver read-through of a real borrowed book end-to-end: reading order, headings, image
  alt text, footnotes/links.
- Confirm page-turn, TOC, bookmarks, and highlight/note creation are fully operable under
  VoiceOver (some support exists: page-turn announcements, "Show reader controls" rotor action).
- Verify reading position ↔ VoiceOver focus stays in sync.

**Acceptance:** VoiceOver reads content in order with headings/alt text, and every reader
action is reachable without sighted gestures.

**Effort:** M (mostly verification + targeted fixes).

---

## P1 — Reader-first low-vision / motion settings

### P1-1 · Reduce Motion
- Observe `@Environment(\.accessibilityReduceMotion)`.
- Targets: `ReaderView` control-chrome `.animation(.easeInOut, value: showControls)` +
  `.transition`s (lines ~129/175), `StorageView`/`LibraryView` transitions, any hero-carousel
  auto-advance.
- When on: replace slide/scale with opacity-or-none; no auto-advancing carousel; instant page
  changes.
- **Acceptance:** with Reduce Motion on, no non-essential motion. **Effort:** S. **Unlocks the
  "Reduced Motion" Nutrition-Label claim.**

### P1-2 · Reduce Transparency
- Observe `@Environment(\.accessibilityReduceTransparency)`.
- Targets: reader chrome `ultraThinMaterial` (`ReaderView` 175/191/233), plus `StorageView`,
  `LibraryView`, `LendingCatalogView`.
- When on: swap materials for an opaque adaptive background color.
- **Acceptance:** reader bars/overlays fully opaque under the setting. **Effort:** S.

### P1-3 · Increase Contrast
- Observe `@Environment(\.colorSchemeContrast)`; when `.increased`, select higher-contrast
  variants in the brand palette (stronger text, borders), **reader text color first**.
- **Acceptance:** reader text + UI hit elevated contrast under the setting. **Effort:** M.

---

## P2 — App-wide polish

### P2-1 · Differentiate Without Color (highlights + status)
- Highlight categories are color-only today (`HighlightEditorSheet`: yellow `#F7D774`, green
  `#A8E6CF`, pink `#FFB7B2`, blue `#B5B9FF`).
- Observe `@Environment(\.accessibilityDifferentiateWithoutColor)`; add non-hue cues — a
  checkmark + color **name** on the selected swatch (names already exist), distinct
  shapes/patterns, and an underline-style highlight option. Add icons to any status badges.
- **Acceptance:** highlight categories + statuses are distinguishable without relying on hue
  (also helps color-blind users generally). **Effort:** M.

### P2-2 · Bold Text
- System semantic fonts already track Bold Text; verify any custom weights honor
  `@Environment(\.legibilityWeight)`, and expose a reader font-weight option (Readium supports
  it). **Effort:** S (mostly verification).

---

## Phasing

- **Phase A (P0) → 1.1:** read-aloud TTS + background audio + VoiceOver content audit.
- **Phase B (P1) → 1.1/1.2:** Reduce Motion, Reduce Transparency, Increase Contrast (reader-first).
- **Phase C (P2) → 1.2:** Differentiate Without Color, Bold Text, app-wide sweep.

## Test matrix (run per phase, Xcode Accessibility Inspector + on-device)

VoiceOver (full reader read-through, TOC, controls, highlights, page-turn) · Read-aloud
(continuous across chapters, lock-screen, interruptions, rate/voice) · Dynamic Type at AX5 ·
Reduce Motion · Reduce Transparency · Increase Contrast · Differentiate Without Color · Bold
Text · Voice Control · Full Keyboard Access.

## Accessibility Nutrition Labels after this plan

Strengthens **VoiceOver / Larger Text / Dark Interface / Sufficient Contrast**; **adds Reduced
Motion** (Phase B) and **Differentiate Without Color** (Phase C). Read-aloud is a feature
highlight (not its own label) that materially improves the blind-user experience.
