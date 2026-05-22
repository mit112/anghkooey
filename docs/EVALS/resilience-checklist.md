# Resilience Checklist — Lane E (M5)

Manual verification steps required before App Store submission. Items that cannot be automated.

---

## E1 — Offline / airplane-mode capture

**Status:** Code verified. Unit test `enqueue_onModelUnavailable_queuesFallbackDraft` covers the fallback path.

**What the code does:** When `LiveCardAuthoringService.generateDrafts` throws `AuthoringError.unavailable` (model not ready, device not eligible, or Apple Intelligence not enabled), `AppState.enqueue` catches any error and queues a fallback draft: `CardDraft(question: <captured text>, answer: "(edit to add answer)")`. The fallback draft surfaces in the review sheet exactly like an AI-generated one — the user can accept or skip it.

**Manual verification (on device, airplane mode):**
- [ ] Enable airplane mode on test device
- [ ] Share a text snippet from Safari → Anghkooey
- [ ] Open Anghkooey — share sheet should dismiss, card review sheet should appear
- [ ] Card question = the shared text, answer = "(edit to add answer)" 
- [ ] Accept the card → it appears in Review tab
- [ ] Disable airplane mode — confirm subsequent captures use AI authoring

---

## E2 — 30-minute soak test

**Status:** `MetricsReceiver` (added Lane B) already logs `MXHangDiagnosticPayload` to OSLog. Hang data arrives ~24h after a real-device run. No additional code needed.

**Manual verification:**
- [ ] Install build on device (direct install or TestFlight)
- [ ] Run a 30-minute review session: tap Got it / Missed it continuously, let app idle between taps
- [ ] Monitor Console.app during the session: filter subsystem = bundle ID, category = MetricKit
- [ ] After 24h: confirm `MetricsReceiver` logs appear (MXMetricPayload JSON)
- [ ] Check `MXHangDiagnosticPayload` count = 0 (no main-thread hangs >250ms)
- [ ] Check memory: no unbounded growth visible in Xcode Memory Report during session

**Hang budget:** 0 hangs >250ms during review tab interaction. `InboxDrainer` runs on a background actor; main-thread work is limited to SwiftUI state updates and `ModelContext.save()` (single-row writes, expected <10ms).

---

## E3 — Lower-tier device crash-free verification

**Status:** Pending. No lower-tier device available in current environment.

**Target devices:** iPhone SE (3rd gen, A15) or iPhone 15 (A16). FoundationModels requires A17 Pro+; on lower-tier devices the app should fall back gracefully (E1 path).

**Manual verification:**
- [ ] Install on iPhone SE or iPhone 15
- [ ] Confirm app launches without crash (SwiftData container opens cleanly)
- [ ] Confirm Share Extension appears in share sheet
- [ ] Share text → fallback draft shown (AI unavailable on these devices)
- [ ] Accept draft → card persists to SwiftData → Review tab loads it
- [ ] Review tab: Got it / Missed it work; haptics fire; empty state shows after queue clear
- [ ] No crash in 10-minute session

**Expected:** AI authoring unavailable (device not eligible), full capture→review flow works via fallback.
