# App Store Metadata — Anghkooey

> Draft. All fields map to App Store Connect fields. Fill in `[TBD]` items before submission.

---

## App Information

**Name:** Anghkooey  
**Subtitle:** Remember Everything  
**Bundle ID:** `com.[author].anghkooey`  
**Primary category:** Education  
**Secondary category:** Productivity  
**Content rating:** 4+  

---

## Localization: English (U.S.)

### Description (4,000 char max)

```
Anghkooey turns anything you capture into a flashcard — automatically.

Share a passage from Safari, snap a photo of your notes, or type a few lines of anything worth remembering. On-device AI (Apple Intelligence) reads it and drafts the flashcards for you. Review, approve, and you're done. No manual card creation. No subscription. No data leaving your phone.

HOW IT WORKS

Capture — Use the Share Sheet from any app to send text or images to Anghkooey. Or open the app and type directly. The on-device AI generates draft flashcards in seconds.

Review — One tap to accept a draft card. One tap to skip it. Nothing gets added to your deck without your approval.

Remember — A proven spaced-repetition algorithm (FSRS-6) schedules each card at exactly the right moment: sooner when you're shaky, later when you've got it. The review session is a single screen — Got it, Missed it, next card.

PRIVACY FIRST

All your cards live on your device in an on-device database. The AI that generates flashcard drafts runs entirely on your iPhone — no server, no account, no subscription. Nothing is uploaded, analyzed, or sold.

DESIGNED FOR REAL USE

Most spaced-repetition apps fail because creating cards is too much work. Anghkooey removes that friction entirely. The AI does the authoring; you just say yes or no. The result is a flashcard deck that grows naturally as you read, study, or explore — without changing how you already consume content.

REQUIREMENTS

• iPhone running iOS 26 or later
• Apple Intelligence required for on-device AI card generation (available on iPhone 15 Pro and later with the appropriate language and region settings)
• Works offline; AI generation requires the device model to be downloaded
```

### Keywords (100 char max, comma-separated)

```
flashcards,spaced repetition,FSRS,AI study,memory,learning,notes,capture,review,apple intelligence
```

### What's New (v1.0, 4,000 char max)

```
First release. Capture text or photos from any app, let on-device AI draft flashcards, review them with a single tap, and let FSRS-6 schedule your reviews for long-term retention.
```

---

## Support & Legal

**Support URL:** `[TBD — needs a support page; use GitHub Issues URL until launch site exists]`  
**Marketing URL:** `[TBD]`  
**Privacy Policy URL:** `[TBD — required for App Store submission; must be live before submitting]`

---

## Screenshots

> Required sizes: iPhone 6.9" (1320×2868 or 1290×2796), iPad 13" (2064×2752 or 2048×2732).
> Minimum 3 screenshots per device class required.

Planned screenshot set (6.9" iPhone):

1. **Capture tab** — Share Sheet → Anghkooey → draft cards appearing
2. **Card review sheet** — a draft card with Accept / Skip buttons
3. **Review tab** — review session with a card and Got it / Missed it
4. **Empty review state** — "You're all caught up" with the next review time
5. **Privacy callout** — on-device AI badge + "Nothing leaves your phone" copy

> Screenshots not yet captured. Capture from iPhone 17 Pro simulator once UI is finalized.

---

## App Review Notes

```
Anghkooey uses Apple Intelligence (FoundationModels framework) for on-device AI card generation.
This feature requires a device with Apple Intelligence enabled (iPhone 15 Pro or later, iOS 26,
appropriate language/region). The app works without AI — users can still capture text and create
cards manually. The on-device AI is not available in the iOS Simulator; App Review may test on a
real device with Apple Intelligence enabled.

No network calls are made during normal use. The app does not require a login or account.

Test account: not required.
```

---

## Pricing

**Price:** Free  
**In-App Purchases:** None for v1  

---

## Checklist Before Submission

- [ ] Privacy Policy URL is live and accessible
- [ ] Support URL is live and accessible  
- [ ] All screenshots captured on iPhone 17 Pro (or 6.9" device)
- [ ] iPad screenshots captured (or iPad explicitly excluded in Xcode)
- [ ] App icon set (all required sizes) — check with `xcrun simctl` or Xcode asset catalog
- [ ] Bundle version and build number set correctly in Xcode
- [ ] `PrivacyInfo.xcprivacy` passes Xcode validation (`Product → Archive`, check privacy report)
- [ ] App name / subtitle / keywords fit character limits
- [ ] "What's New" text written for this version
- [ ] App Review notes filled in
- [ ] TestFlight external review completed (at least one non-developer tester)
- [ ] Name availability verified: App Store, `.com`/`.app` domain, USPTO TESS (not yet done as of 2026-05-22)
