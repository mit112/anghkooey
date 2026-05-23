# App Store Metadata — Anghkooey

> Draft. All fields map to App Store Connect fields. Fill in `[TBD]` items before submission.

---

## App Information

**Name:** Anghkooey  
**Subtitle:** Remember Everything  
**Bundle ID:** `com.mitsheth.anghkooey`  
**Version:** 1.0 (Build 1)  
**Primary category:** Education  
**Secondary category:** Productivity  
**Content rating:** 4+  

---

## Localization: English (U.S.)

### Description (4,000 char max)

```
Anghkooey turns anything you capture into a flashcard — automatically.

Share a passage from Safari, snap a photo of your notes, or type anything worth remembering. On-device AI (Apple Intelligence) reads it and drafts the flashcards for you. Review, edit, and approve. No manual card creation. No subscription. No data leaving your phone.

HOW IT WORKS

Capture — Use the Share Sheet from any app to send text or images to Anghkooey. Or open the app and use the camera to scan physical books, whiteboards, or handwritten notes. The on-device AI generates draft flashcards in seconds, entirely on your device.

Review and approve — Each AI draft shows you the proposed question, answer, and suggested tags. Edit anything directly before accepting. Nothing enters your deck without your approval.

Study — A proven spaced-repetition algorithm (FSRS-6) schedules each card at the right moment. Swipe right for Good, left for Again, up for Easy — or tap the four-grade buttons. Swipe down to edit a card mid-session. The app never punishes a missed day.

Mnemonics — Stuck on a card? Tap "Generate Mnemonic" to let on-device AI craft a vivid memory device — a concrete image, acronym, or micro-story that makes the answer stick.

Your Library — Browse every card, filter by tag, and edit directly. AI proposes tags when a card is created; you're always in control.

Grace features — Cushion Mode shows a manageable daily batch when you've fallen behind, so you never face an overwhelming queue. Freeze Mode shifts your schedule forward when life gets in the way.

PRIVACY FIRST

All your cards live on your device. The AI runs entirely on your iPhone — no server, no account, no subscription. Nothing is uploaded, analyzed, or sold.

REQUIREMENTS

• iPhone running iOS 26 or later
• Apple Intelligence required for on-device AI card generation (iPhone 15 Pro or later, with Apple Intelligence enabled)
• Works offline; AI generation requires the on-device model to be downloaded
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

**Support URL:** `https://github.com/mit112/anghkooey/issues`  
**Marketing URL:** `[TBD — add after launch site exists]`  
**Privacy Policy URL:** `https://raw.githubusercontent.com/mit112/anghkooey/main/docs/STORE/PRIVACY_POLICY.md` (raw GitHub URL — acceptable for App Store; or use GitHub Pages once configured)

---

## Screenshots

> Required sizes: iPhone 6.9" (1320×2868 or 1290×2796), iPad 13" (2064×2752 or 2048×2732).
> Minimum 3 screenshots per device class required.

Planned screenshot set (6.9" iPhone):

1. **Capture tab** — camera view or Share Sheet animation → draft cards appearing
2. **Card review sheet** — a draft card with question / answer fields and Accept button
3. **Review session** — card with question shown, four-grade swipe buttons visible
4. **Library tab** — card list with tag filter chips at the top
5. **Mnemonic in-session** — answer revealed with "Generate Mnemonic" button visible (or mnemonic text shown)
6. **Cushion Mode banner** — review tab showing "Showing today's batch — N of M due"

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
