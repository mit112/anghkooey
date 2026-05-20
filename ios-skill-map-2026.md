# iOS Skill Map 2026 — Demand, Gaps, Future Projects

> **Owner:** Mit Sheth · **Date:** 2026-05-20 · **Market:** US (remote + onsite)
> **Target role:** Entry / new grad iOS, with stretch toward mid-level signal
> **Sources:** Apple Developer docs, WWDC 2024 + 2025 sessions, 2025–2026 US job postings (LinkedIn, ZipRecruiter, Built In, Apple Jobs, Disney, Sentry, JPMC, Owner, Pinnacle, etc.), GitHub trending Swift, Pointfree TCA.
> **Method:** 12 parallel Sonnet research agents → aggregated → local repo gap analysis on StreakSync + FlickSwiper.

---

## Phase 1 — 2026 iOS Skill Map (US market)

| # | Domain | Top 3 specific skills | Demand | Junior portfolio bar |
|---|---|---|---|---|
| 1 | **SwiftUI / Apple UI (iOS 26 Liquid Glass)** | Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`), respecting Reduced Transparency · `@Observable` + `@Environment` migrating off `ObservableObject` · `NavigationStack(path:)` value-driven routing + `NavigationSplitView` + `UIViewControllerRepresentable` interop | **5/5** | Universal iPhone/iPad app on iOS 26 with `@Observable` VMs, typed `NavigationStack`, a `GlassEffectContainer`, and one UIKit-wrapped screen. |
| 2 | **Swift 6 strict concurrency** | Production migration to Swift 6 strict (triaging Sendable, killing `@unchecked Sendable`, `@preconcurrency` as scaffold) · `@MainActor` UI + dedicated `actor` for I/O, `nonisolated` library APIs, `@concurrent` for CPU work · Replacing GCD with `async let`/`TaskGroup`/`AsyncSequence`, proper cancellation | **5/5** | One app whose every module compiles under Swift 6 strict with zero `@unchecked Sendable`, an `actor` for networking, and one `AsyncStream` replacing a NotificationCenter pipeline. |
| 3 | **Data & persistence (SwiftData / Core Data / CloudKit)** | `NSPersistentCloudKitContainer` with merge policy + shared/public DB · SwiftData with `@Model` + `ModelConfiguration(cloudKitDatabase:)` + `SchemaMigrationPlan` · Offline-first sync with deterministic conflict resolution (LWW + actor/opId metadata) | **5/5** | SwiftData or Core Data + working CloudKit private-DB sync across two devices with a documented conflict-resolution case in the README. |
| 4 | **On-device AI (Foundation Models / Core ML / Vision)** | Foundation Models framework (`LanguageModelSession`, `@Generable` guided generation, streaming, `Tool` protocol) · Core ML + Create ML conversion/quantization, ANE optimization, `.mlpackage` shipping · Apple Intelligence surfaces (App Intents for Siri/Spotlight, Writing Tools, Image Playground, Vision/NL) | **5/5** | SwiftUI app with `LanguageModelSession` + `@Generable` + a custom `Tool`, plus one Core ML or Vision feature. Open-source it. |
| 5 | **Architecture & modularization** | SPM feature/core package modularization with enforced layer boundaries · TCA (Composable Architecture) reducer + dependency clients + `TestStore` · Clean / MVVM in SwiftUI with protocol-based DI swappable mock/prod | **4/5** | One SwiftUI app split into 2–3 SPM packages (Feature + Domain + protocol-mocked Networking) with `@Observable` VMs and Swift Testing. TCA optional at junior. |
| 6 | **Networking** | URLSession async + typed errors + retry/backoff · Background URLSession (resumable downloads/uploads) · `URLSessionWebSocketTask` + reconnect; certificate pinning via `URLSessionDelegate` | **5/5** | Hand-rolled async `APIClient` (no Alamofire), typed errors, retry-with-backoff, `URLProtocol`-stubbed tests, and either a WebSocket or background download feature. |
| 7 | **Testing & CI** | Swift Testing (`@Test`, parameterized, `@Suite` tags, parallel) · XCUITest + snapshot tests (pointfreeco/swift-snapshot-testing) wired into CI · Hybrid Swift Testing + XCTest under Swift 6 strict concurrency | **4/5** | Public repo with green CI badge running both Swift Testing and XCTest, at least one snapshot test, one XCUITest happy path, coverage in README. |
| 8 | **Platform breadth (Widgets / App Intents / Live Activities)** | App Intents donation + `AppEntity` for Siri / Spotlight / Action Button / Apple Intelligence · Interactive Live Activities + Dynamic Island with ActivityKit push tokens · Control Center widgets (`ControlWidget`, iOS 18+) with Smart Stack relevance | **4/5** | One polished app with a Home Screen widget, an interactive Live Activity driven by an App Intent, and at least one Shortcuts-exposed AppIntent. |
| 9 | **Performance & observability** | Diagnosing hangs/hitches via Instruments Hangs/Time Profiler + `os_signpost` · Launch-time optimization (`MXAppLaunchMetric.timeToFirstDraw`, deferred framework loads) · MetricKit ingestion → backend dashboard with SLOs (crash-free ≥99.5%, hang rate <0.5%) | **5/5** *(senior signal)* | App with a written perf report: Instruments trace before/after, `os_signpost`-annotated slow path, MetricKit payload screenshot showing measurable improvement. |
| 10 | **Security & privacy** | `PrivacyInfo.xcprivacy` + Required Reason API audit (Apple mandates since May 2024) · Passkeys via AuthenticationServices (iOS 26 auto-upgrade, WebAuthn Signal API) · App Attest + DeviceCheck server-side attestation, Keychain biometric ACL, Secure Enclave-bound `SecKey` | **5/5** | Sample app with PrivacyInfo covering ≥3 required-reason APIs, Sign in with Apple **or** Passkey login, and Keychain-stored secrets gated by `LAContext`. |
| 11 | **DevOps / release** | GitHub Actions (macos-latest) + Fastlane `match` + App Store Connect API key for TestFlight on tag push · Xcode Cloud workflows with ci_scripts and secret management · Release automation: semver, build-bump, changelog, phased rollout with feature flags (Firebase Remote Config / LaunchDarkly) | **4/5** | Public repo whose `.github/workflows/ios.yml` ships a TestFlight build on tag push via Fastlane + `match` + ASC API key — README documents signing flow. |
| 12 | **Cross-platform (secondary skill only)** | RN/Expo with iOS-native module debugging (Fabric/TurboModules) · KMP — consuming XCFramework from Swift · Flutter prototyping for secondary surfaces | **3/5** *(as secondary)* | **No** — a junior iOS portfolio should go deeper in Swift/SwiftUI, not dilute it. Add RN/KMP only after one production-quality native iOS app. |

---

## Phase 2 — Capability Gap Analysis vs. Your Apps

Read from local repos at `~/Documents/StreakSync` and `~/Documents/FlickSwiper`.

### Coverage matrix

Legend: **✅ Covered** · **⚠️ Partial** · **❌ Missing**

| Skill Map row | StreakSync | FlickSwiper | Evidence / note |
|---|---|---|---|
| 1. SwiftUI / Liquid Glass | ✅ | ⚠️ | StreakSync README badges iOS 26 + Liquid Glass; FlickSwiper iOS 26 but no glass-effect mention. |
| 2. Swift 6 concurrency | ✅ | ✅ | Both: `actor` services, `@MainActor` VMs, `async/await` throughout. StreakSync `GameResultIngestionActor`; FlickSwiper `TMDBService` actor + 429 retry. |
| 3. Data & persistence | ⚠️ | ⚠️ | **StreakSync**: UserDefaults + App Group + Firestore — **no SwiftData, no CloudKit**. **FlickSwiper**: SwiftData with versioned V1→V4 migrations (strong) + Firestore — but **no CloudKit**. |
| 4. On-device AI (Foundation Models / Core ML / Vision) | ❌ | ❌ | Neither app uses Foundation Models, Core ML, Vision, NL, Apple Intelligence. |
| 5. Architecture & modularization | ⚠️ | ⚠️ | Both: MVVM + `@Observable` + protocol-mocked services (✅). But **single-target monoliths — no SPM feature packages, no TCA**. StreakSync `AppContainer` DI is clean; FlickSwiper uses environment injection. |
| 6. Networking | ⚠️ | ⚠️ | Both have async URLSession. FlickSwiper has 429 retry. **Neither has background URLSession, WebSockets, or certificate pinning.** |
| 7. Testing & CI | ⚠️ | ⚠️ | StreakSync: 335 XCTest + GH Actions CI + 10 UI tests + Firestore pen-test suite (strong). FlickSwiper: 128 XCTest + GH Actions + 78-test Firestore pen-test suite. **Both use XCTest, not Swift Testing. Neither has snapshot tests.** |
| 8. Platform breadth (Widgets / App Intents / Live Activities) | ⚠️ | ❌ | StreakSync has a **Share Extension** (✅, distinguishing). Neither has **widgets, App Intents, Live Activities, Control Center widgets, watchOS, or visionOS**. |
| 9. Performance & observability | ❌ | ❌ | No MetricKit ingestion, no `os_signpost` work, no documented Instruments perf reports in either repo. |
| 10. Security & privacy | ✅ | ✅ | Both: Privacy Manifest, Firestore security rules with pen-test suites (100 / 78 cases), Sign in with Apple, full account deletion, Keychain. **Neither has Passkeys, App Attest, or DeviceCheck.** |
| 11. DevOps / release | ⚠️ | ⚠️ | Both: GitHub Actions CI. **Neither uses Fastlane `match`, Xcode Cloud, ASC API key automation, or feature flags / Remote Config.** |
| 12. Cross-platform | ❌ | ❌ | Pure Swift/SwiftUI both — which is **correct for a junior iOS portfolio**, not a gap. |

### Skills you can credibly claim on a résumé today

- **Production SwiftUI on iOS 26** with `@Observable` (Swift Observation), `NavigationStack`/`NavigationSplitView`, Liquid Glass (StreakSync)
- **Swift 6 strict concurrency** — actors, `@MainActor` isolation, structured concurrency, `nonisolated` Sendable boundaries
- **MVVM with protocol-mocked services** + dependency injection container (`AppContainer`)
- **SwiftData with versioned schema migrations** (V1→V4) — uncommon and senior-flavored
- **Firebase production stack**: Auth (Sign in with Apple + Google + anonymous linking), Firestore real-time snapshot listeners, security rules with **100-case + 78-case penetration test suites** — this is a strong, rare signal
- **Share Extension pipeline** with App Group bridge, Darwin notifications, deep links (StreakSync) — concrete platform skill
- **iOS Universal Links via Apple App Site Association** (FlickSwiper)
- **GitHub Actions CI for iOS** with simulator builds + tests on every push
- **Privacy Manifest + full account-deletion flow** (App Store compliance)
- **Real-time social/leaderboard** features with Firestore listeners and offline retry via Keychain queue
- **335 + 128 unit/UI tests** plus rules pen-testing — testing discipline well above new-grad average

### Gaps you cannot yet claim — ranked by demand × portfolio leverage

| Rank | Gap | Demand | Why it matters for a 2026 résumé |
|---|---|---|---|
| 1 | **Foundation Models framework / Apple Intelligence** | 5/5 | Newest, hottest 2026 skill. Zero-cost on-device LLM. Almost no junior portfolios have it yet — strong differentiator. |
| 2 | **App Intents + Siri/Spotlight/Shortcuts** | 4/5 | Apple Intelligence routes through this. Without it your app is invisible to system AI surfaces. |
| 3 | **WidgetKit + Live Activities + Dynamic Island** | 4/5 | Table stakes at consumer-app shops. Retention surface. Pairs with App Intents. |
| 4 | **CloudKit (private DB) sync** | 5/5 | You have Firebase, but CloudKit is the Apple-only consumer default. Adds a second sync paradigm to your résumé. |
| 5 | **MetricKit / Instruments / `os_signpost` perf work** | 5/5 | Senior signal. A written perf report in a portfolio repo is rare and impressive. |
| 6 | **SPM modularization** (Feature + Domain + Networking packages) | 4/5 | Required at any team >5 engineers. Easy to retrofit into a future project. |
| 7 | **Swift Testing + snapshot tests** | 4/5 | You have XCTest depth; adding Swift Testing parameterized + snapshot tests modernizes the story. |
| 8 | **Passkeys + App Attest + DeviceCheck** | 5/5 | Fintech/health gate. Pairs with your existing Sign-in-with-Apple work. |
| 9 | **Background URLSession + WebSockets + cert pinning** | 5/5 | Real-time / resilient networking. Common in any non-trivial backend integration. |
| 10 | **Fastlane `match` + Xcode Cloud + ASC API key** | 4/5 | Release-engineering signal. One repo with a working pipeline checks this box forever. |
| 11 | **Core ML / Vision / Create ML** | 4/5 | Pair with Foundation Models for a credible "on-device AI" story. |
| 12 | **watchOS companion** (or visionOS) | 3–4/5 | Vertical-specific (fitness/health). High signal but optional. |
| 13 | **TCA exposure** | 3/5 *(junior)* | Nice to have at senior-leaning shops (Pointfree-aligned teams, fintech). |

---

## Phase 3 — Future Project Proposals (each closes ≥3 gaps, shippable solo in 4–8 weeks)

### Project A — **Verbal** · On-device AI daily journal & reflection coach
**One-line pitch:** A SwiftUI journal where Apple's on-device Foundation Models summarizes your week, surfaces themes, and answers reflection questions — all offline, no API bills, no data leaves the device.

**Gaps closed:**
1. Foundation Models framework (`LanguageModelSession`, `@Generable`, custom `Tool` for retrieving past entries)
2. App Intents + Siri ("Hey Siri, journal that I felt anxious today")
3. WidgetKit + interactive Live Activity for the daily prompt
4. SwiftData + **CloudKit private DB** sync (vs. your Firebase work)
5. Swift Testing framework with parameterized tests
6. SPM modularization (`Journal`, `Intelligence`, `Persistence` packages)

**Core frameworks:** SwiftUI · FoundationModels · SwiftData + CloudKit · AppIntents · WidgetKit · ActivityKit · Swift Testing.

**MVP (4 weeks):** Write/read entries (SwiftData) → on-device summary via `LanguageModelSession` with `@Generable` Themes struct → CloudKit sync → one `AppIntent` ("Open today's journal").

**Stretch (weeks 5–8):** Interactive Live Activity, Spotlight donation, Writing Tools integration, watchOS quick-jot companion, snapshot tests, GitHub Actions + Fastlane match TestFlight pipeline.

**Why it scores:** Cleanly covers the #1 and #4 ranked gaps (Foundation Models, CloudKit) plus surface-area gaps (Widgets, App Intents). Distinct from StreakSync/FlickSwiper — text-input app, no game/swipe metaphor.

---

### Project B — **PaceLab** · Workout tracker with on-device ML and runtime perf rigor
**One-line pitch:** A GPS run tracker that classifies workout type with Core ML, runs a Dynamic Island Live Activity during sessions, and ships with a written MetricKit-driven perf report.

**Gaps closed:**
1. **Core ML + Vision** (activity classifier + OCR a race bib as a stretch demo)
2. **Background URLSession + background location** (real backgrounding work)
3. **MetricKit ingestion + Instruments perf report** (the senior signal)
4. **Interactive Live Activity** with ActivityKit push updates (compact/expanded/minimal)
5. **App Intents** ("Start a run with Siri")
6. **watchOS companion** with WatchConnectivity
7. Snapshot tests for the charts screens

**Core frameworks:** SwiftUI · CoreLocation · CoreMotion · CoreML · WidgetKit · ActivityKit · MetricKit · WatchKit · Background Tasks · `os_signpost` · Instruments.

**MVP (4 weeks):** Start/stop a run, map polyline, save to SwiftData, basic Live Activity with elapsed time + pace, watchOS app shows the same stats via WatchConnectivity.

**Stretch (weeks 5–8):** Train a tiny Create ML activity classifier (walk/jog/run/sprint), ship MetricKit payload → small Cloud Run backend with a dashboard, write a `PERFORMANCE.md` with before/after Instruments traces (launch time, hang rate, hitch rate).

**Why it scores:** Hits the rarest senior signal (real perf work + MetricKit). Background URLSession + WebSockets-ready architecture sets up real-time. Different surface area from StreakSync (passive tracking) and FlickSwiper (passive consumption).

---

### Project C — **Vouch** · Privacy-first encrypted expense splitter with Passkeys
**One-line pitch:** Tinder-style "did you spend this?" review queue for trips with friends, with Passkey + App Attest auth, end-to-end Keychain-bound secrets, modular SPM architecture, and a real release pipeline.

**Gaps closed:**
1. **Passkeys via AuthenticationServices** (iOS 26 auto-upgrade, WebAuthn signal API)
2. **App Attest + DeviceCheck** attestation pipeline against a small backend
3. **SPM modularization** (`Core`, `Networking`, `Auth`, `Features/Trips`, `Features/Settle` packages)
4. **Fastlane `match` + GitHub Actions + Xcode Cloud** TestFlight on tag push
5. **WebSockets** (`URLSessionWebSocketTask`) for live-settle updates across devices
6. **Certificate pinning** via `URLSessionDelegate`
7. **TCA** (Pointfree Composable Architecture) for the trips reducer — one screen, to learn it
8. **Swift Testing** + snapshot tests + Firestore-rule-style backend pen tests

**Core frameworks:** SwiftUI · AuthenticationServices (Passkeys) · DeviceCheck/AppAttest · CryptoKit (Secure Enclave SecKey) · URLSession (WebSockets, pinned) · Swift Testing · TCA (optional one feature).

**MVP (4 weeks):** Create a trip, add expenses, split-fairly algorithm, sign in with Passkey, sync via REST + WebSocket to a tiny Fly.io/Cloud Run backend.

**Stretch (weeks 5–8):** App Attest assertion middleware, biometric-gated Keychain for friend tokens, Fastlane match + ASC API key + Xcode Cloud pipeline shipping TestFlight builds, snapshot tests on settlement screens, public README documenting the attestation flow.

**Why it scores:** Closes the fintech-flavored security gaps (5/5 demand at fintech/health shops), plus modularization and release engineering — three of the highest-leverage gaps in one repo. Surface area (trip-based, multi-user) is unrelated to StreakSync (single-user streaks) and FlickSwiper (single-user media).

---

## Suggested execution order

1. **Project A first (Verbal)** — biggest market signal (Foundation Models is the 2026 talking point), fastest to ship, lowest moving parts. Start while Foundation Models is still trending in recruiter searches.
2. **Project B second (PaceLab)** — adds the senior perf-report signal, watchOS, and background work. Heavier engineering. Best for late summer 2026.
3. **Project C third (Vouch)** — most ambitious. Save for fall 2026 when applying to fintech/health-leaning shops. Backend dependency makes it longer.

## What to **stop** doing in the next project

- Don't repeat single-target monoliths — split at least one project into SPM packages.
- Don't default to Firebase — at least one project must demonstrate **CloudKit** as the sync substrate (recruiter pattern-match).
- Don't write only XCTest — adopt Swift Testing as the primary suite, keep XCTest only for UI tests.
- Don't ship without a `PERFORMANCE.md` and a `PrivacyInfo.xcprivacy` audit in the README.

---

*Generated 2026-05-20.*
