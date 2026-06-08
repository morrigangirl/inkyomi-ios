# Store / Legal Decisions — Needed Day 0 (in parallel with engineering)

These are **not** code fixes. They require someone with the App Store Connect /
Google Play Console account and/or legal input. They have the longest lead time
and gate store submission, so start them immediately. Each lists the question,
the evidence, the options, and what engineering does per outcome.

---

## D1 (audit C3) — External "buy on website" buttons for digital content
**Severity:** Critical · release-blocking risk on both stores.

**Question:** Are the in-app buttons that open `inkcolors.shop` to buy ebooks /
manage a subscription permitted as-is, or do they require an Apple entitlement
(or removal)?

**Evidence (current behavior — no StoreKit / Play Billing anywhere; purchases
are 100% web):**
- iOS `InkYomi/UI/BookDetail/BookDetailView.swift:269-286` and Android
  `ui/bookdetail/BookDetailScreen.kt:284-296`: **"View Online" / "Pre-order
  Online"** → opens `inkcolors.shop/books/{icin}` in an external browser to
  purchase.
- Android `ui/settings/SettingsScreen.kt:161-167`: **"Manage subscription →
  Subscribe or cancel on inkcolors.shop"**.

**Rules at play:**
- Apple **Guideline 3.1.1** (no in-app buttons/links to external purchase
  mechanisms) vs the **3.1.3(a) "reader" app** exception and the **External Link
  Account Entitlement**.
- Google Play **Payments policy** (external links for digital goods — market- and
  time-dependent enforcement).

**Options:**
1. Classify InkYomi as a reader app and obtain Apple's external-link entitlement;
   keep the links but conform to the entitlement rules (single link, no steering
   language, show the system disclosure sheet).
2. Remove the in-app purchase CTAs (owned/free items show only "Read").
3. Hybrid per platform / market.

**Engineering response per outcome:** (1) add the entitlement's required
disclosure sheet + verify copy compliance — small client change; (2) gate/remove
the CTAs — small client change. **Do not relabel the buttons before the
decision** — the risk is the outbound purchase path, not the wording.

**Owner:** store-account holder + legal. **Blocks:** App Store / Play submission.

---

## D2 (audit H9) — Age / content rating
**Severity:** High · post-launch removal risk if under-rated.

**Question:** What age / content rating should each store list, given the catalog
is browseable with no age gate and the data model carries `spiceLevel` +
`hasContentWarning` (mature romance/erotica signals)?

**Evidence:** `SearchTypes` / `SearchDtos` (`spiceLevel`, `hasContentWarning`) on
both platforms; no age gate anywhere in either app.

**Decision:** Answer Apple's age-rating questionnaire and Google Play / IARC to
match the **most mature browsable content** (likely 17+/Mature). A lower rating
would require age-gating or filtering mature content (a product change).

**Owner:** operator (must characterize the live catalog) + legal.

---

## D3 (audit H10) — App Privacy label + Play Data Safety
**Severity:** High · "inaccurate privacy label" rejection risk.

**Question:** Do the store privacy disclosures match what the apps actually
collect?

**Data actually collected** (no third-party analytics/crash SDKs): email,
display name, app-generated device UUID + device model, per-loan reading
telemetry spans (`loanId` + `deviceId` + timestamp), and server-side IP on every
request.

**Decision:** Complete the App Store Privacy label and Play Data Safety form to
declare the above — purposes App Functionality / Analytics, linked to identity,
**not** used for tracking. Confirm IP/diagnostic-log treatment with the
server-log owner (Vector → `control.inkcolors.shop`).

**Owner:** legal/privacy + backend log owner.

---

## D4 (audit C1, follow-up) — Privacy-manifest data-type confirmation
The iOS `PrivacyInfo.xcprivacy` shipped in Phase 1 declares Email, Name, UserID
(`device_id`), Other Usage Data (reading spans), and `NSPrivacyTracking=false`.
Confirm these **exactly** match the final App Privacy nutrition label in App
Store Connect (they should, per D3).

**Owner:** whoever submits the App Privacy label.
