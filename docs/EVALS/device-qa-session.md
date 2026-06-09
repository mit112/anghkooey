# One-Shot Device QA Session — Apple Intelligence iPhone

> Prereq: iPhone 15 Pro or later, iOS 26+, Apple Intelligence enabled and model downloaded
> (Settings → Apple Intelligence & Siri). Budget: ~2.5 hours including the 30-min soak.
> Bring: this checklist, a Mac with Xcode + this repo, a Lightning/USB-C cable.
> Order matters — items are sequenced so reboots/installs don't invalidate earlier steps.

## 0. Setup (10 min)
- [ ] Connect device, trust Mac, enable Developer Mode (Settings → Privacy & Security).
- [ ] Xcode: select device, automatic signing, ⌘R install. App launches → onboarding appears.

## 1. Eval harness + goldens (20 min) — foundation.md §9.2
- [ ] On the Mac (if it has Apple Intelligence) or via the device test host:
      `swift run --package-path Packages/AnghkooeyIntelligence EvalRunner --update-goldens`
      (populates goldens for the 17 new fixtures)
- [ ] `swift run --package-path Packages/AnghkooeyIntelligence EvalRunner` → record pass rate.
- [ ] Gate: ≥ 80% (≥ 16/20). Record per-fixture results in docs/EVALS/m5-eval-run.md.
- [ ] If < 80%: note failing fixtures + failure mode; prompt iteration happens AFTER the
      session (don't burn device time on prompt engineering).

## 2. M9 deferred AI items (15 min)
- [ ] Q&A capture E2E: Safari → select text → Share → Anghkooey → AI draft sheet shows real
      Q/A (not the fallback stub) → edit → accept → card appears in Review tab.
- [ ] Cloze E2E: Capture tab → Cloze mode → paste a sentence → AI proposes cloze deletions →
      accept → cloze card reviews correctly (blank shown, answer on reveal).
- [ ] Time the share-to-draft latency with a stopwatch, 3 samples. Gate: < 5 s median
      (foundation §9.1). Record numbers.

## 3. E1 — Airplane mode fallback (10 min)
- [ ] Airplane mode ON → share text from Safari → fallback draft (question = shared text,
      answer = "(edit to add answer)") → accept → appears in Review.
- [ ] Airplane mode OFF → share again → real AI draft. Check E1 boxes in
      docs/EVALS/resilience-checklist.md.

## 4. Instruments traces (25 min) — PERFORMANCE.md artifacts
- [ ] ⌘I (Profile) → Blank template + os_signpost instrument.
- [ ] Record: seed 3 cards by typing, review 10 cards. Stop.
- [ ] Screenshot `review-tap` intervals → docs/instruments/m6-review-tap-signpost.png
- [ ] Same trace shows `ai-draft-generation` interval from a share capture →
      screenshot → docs/instruments/ai-draft-generation.png
- [ ] Settings → Optimize Schedule → run optimizer → screenshot `fsrs-optimization`
      POI trace → docs/instruments/fsrs-optimization.png

## 5. E2 — 30-minute soak (30 min, can overlap coffee)
- [ ] 20+ cards in queue, review continuously with varied pacing; idle 2–3 min stretches.
- [ ] Xcode Memory Report attached: no unbounded growth. No hangs/ANR.
- [ ] Check E2 boxes in resilience-checklist.md.

## 6. Wrap-up (10 min)
- [ ] E3 (lower-tier device): if iPhone 15 still available, fallback path is already verified
      (2026-06-03 session) — mark E3 with that date/device; otherwise note "verified on
      iPhone 15, 2026-06-03" in App Review notes.
- [ ] Commit: updated m5-eval-run.md, resilience-checklist.md, goldens JSON, 3 PNGs.
- [ ] ~24h later (device can be returned): MetricKit payload appears in Console.app
      (subsystem com.mitsheth.anghkooey, category MetricKit) only after a TestFlight/dev
      run — if captured, paste into PERFORMANCE.md §M6.
