# V1 Closeout Assessment — 2026-06-09

> Brutal-honesty state assessment performed 2026-06-09 on `main` (HEAD `2de8efd`, M9 merged).
> Purpose: define what stands between the current state and "done" (ship + portfolio + LinkedIn),
> and prevent scope creep. **Feature freeze is declared as of M9. Nothing below adds features.**
>
> Sequencing decision (Mit, 2026-06-09): make the app as code-ready as possible first;
> app icon and submission checklist come after code is finished; ALL device verification
> happens in one batched session when an Apple Intelligence iPhone is available
> (access will be rare and short — we prepare so that session is maximally efficient).

---

## Verdict

Engineering is done and strong. The product is not ready to show. The gap is not features —
it is (1) unverified core AI promise on real hardware, (2) zero visual identity, (3) submission
mechanics. Estimated 2–3 weeks of closeout work.

## What is verifiably solid (evidence-checked 2026-06-09)

- **107 app tests / 28 suites pass** (clean re-run on iPhone 17 Pro Max sim 2026-06-09;
  an earlier same-day failure was harness-inflicted — app launched onto the sim mid-test-run).
  Core package suite with FSRS-6 parity fixtures additionally green.
- Skill-map gaps all closed with real artifacts: SPM modularization, Swift 6 strict concurrency,
  SwiftData versioned schemas V1–V5, FoundationModels, App Intents, WidgetKit, CloudKit opt-in,
  Vision OCR, Swift Testing, MetricKit + os_signpost. ARCHITECTURE.md = 944 lines of milestone history.
- Review surface is decently crafted: drag physics + rotation, per-grade haptics
  (`ReviewView.swift:312-313`), material card styling, actionable empty states, M9 accessibility pass.
- Build clean (zero errors); app boots and runs on iOS 26 simulator.

## Findings (numbered for reference)

### F1 — Core AI feature never verified on real hardware  **[BLOCKER — batched device session]**
- The app's headline ("on-device AI drafts your flashcards") has never been observed on a phone.
- `docs/EVALS/m5-eval-run.md`: pass rate "**not recorded**" (M2), "**Pending first device run**" (M5).
- M9 device QA was on iPhone 15 (no Apple Intelligence); both AI items deferred.
- Eval set is **3 fixtures**; `foundation.md` §9.2 promises ≥80% on **100 inputs**. Nowhere near
  our own quality bar. Fixture set should grow to 20–30 before the device session so the claim is honest.
- Pre-device option to explore: if the host Mac runs Apple Intelligence, FoundationModels may work
  in the simulator — could verify drafts before any device access.

### F2 — No app icon  **[App Store blocker — deferred by decision until code is finished]**
- Zero `.xcassets` anywhere in the repo. No icon, no custom accent color (default blue tint).
- Loudest "barebones" signal; first thing visible on home screen and in screenshots.

### F3 — UI is 100% stock SwiftUI  **[polish]**
- Across `Packages/AnghkooeyUI`: exactly one custom color usage (`LibraryView.swift:170`),
  animations in one file only (`ReviewView.swift`), no gradients, no custom typography.
- Concrete bugs found in ~10 minutes of live inspection:
  - **F3a** Onboarding pager dots invisible (white-on-white): `OnboardingView.swift:44`
    uses `.tabViewStyle(.page)` without `.indexViewStyle(.page(backgroundDisplayMode: .always))`.
    First page shows no button, no skip, no hint that pages 2–3 exist — looks like a dead end.
  - **F3b** `App/Anghkooey/ContentView.swift:27,73,91` — three `try?`-swallowed failures
    (sample-deck load fails silently). Contradicts M9's "surface load/save failures" theme.
  - **F3c** 14 compiler warnings (redundant `public`, unnecessary `nonisolated(unsafe)`,
    deprecated init in `AnkiPackageParser.swift:63`, unused `try?` results, missing
    `LSSupportsOpeningDocumentsInPlace` declaration).

### F4 — Privacy manifest + README audit now FALSE  **[compliance bug — fix in code phase]**
- README §Required-Reason API Audit claims "No UserDefaults or @AppStorage in production code."
- **Five** production files use UserDefaults: `OnboardingView.swift` (AnghkooeyUI),
  `AnghkooeyApp.swift`, `ClipboardCaptureCoordinator.swift`, `FreezeController.swift`,
  `SyncPreference.swift`.
- `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`) is NOT declared in
  `App/Anghkooey/PrivacyInfo.xcprivacy` → ITMS-91053 warning risk at upload; portfolio
  audit document is factually wrong. Check the Share Extension + Widget manifests too.

### F5 — M6 submission checklist 0/12  **[deferred by decision until code is finished]**
- `docs/STORE/metadata.md` checklist: nothing checked.
- No screenshots (`docs/screenshots/` doesn't exist). Privacy policy written but not hosted.
- Name availability ("Anghkooey": App Store / .com / .app / USPTO TESS) never verified —
  `foundation.md` §0 requires it before ANY public push.
- No TestFlight build ever uploaded. `docs/instruments/` has one JPG, not the three promised traces.

### F6 — README is 27 lines  **[portfolio gap]**
- Front door of the portfolio piece is mostly a privacy table. No screenshots, no architecture
  diagram, no links to ARCHITECTURE.md / PERFORMANCE.md. Undersells everything underneath it.

## Definition of done (the end of the project)

1. All code-level fixes landed (F3a–c, F4), warnings ≤ a handful, tests green.
2. Visual identity: app icon + deliberate accent color + dark-mode check (F2; no redesign).
3. One batched Apple-Intelligence-device session executed from a prepared script:
   eval harness pass rate recorded, Q&A + Cloze E2E verified, E1/E2/E3 resilience checks,
   Instruments traces captured (F1, F5-instruments).
4. Submission mechanics: screenshots, hosted privacy policy, name check, metadata, TestFlight,
   App Store submission (F5).
5. README rewritten as portfolio front door (F6); portfolio site updated; LinkedIn post published.
6. **Then stop.** No iPad UI, no CloudKit two-device verification (descoped), no new features.

## Out of scope forever (anti-scope-creep ledger)

- iPad-optimized UI, macOS app, watchOS — per foundation.md.
- CloudKit two-device sync verification — descoped per v1.1 cut-line; code-complete is acceptable.
- Renaming the product — name availability check only; renaming now = scope creep.
- New capture surfaces, new card types, social anything, streaks, telemetry.
