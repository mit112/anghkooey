# Anghkooey — *remember everything*

Anghkooey is a capture-first, privacy-first spaced-repetition iOS app. It removes the card-authoring tax by using on-device AI (FoundationModels / Apple Intelligence) to generate flashcards from anything you capture — text, photos, or voice — and then schedules review using the FSRS-6 algorithm so you actually remember what you learn. All card data stays on-device and in your iCloud private database; nothing leaves your ecosystem.

**Tech stack:** iOS 26 · Swift 6 · SwiftUI · FoundationModels · FSRS-6 · SwiftData + CloudKit · SPM modularization (`AnghkooeyCore` / `AnghkooeyIntelligence` / `AnghkooeyUI`)

See [`foundation.md`](foundation.md) for the authoritative product spec and v1 scope.

## Required-Reason API Audit

Apple requires apps to declare a reason for accessing certain sensitive APIs in their privacy manifest (`PrivacyInfo.xcprivacy`). The table below documents every required-reason API used by Anghkooey and the declared reason code.

| API category | Reason code | Where used | Justification |
|---|---|---|---|
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `3B52.1` | `InboxDrainer` (main app) | Reads `contentModificationDateKey` and `attributesOfItem` on inbox JSON/image files the app creates and manages in the App Group container, to process items in arrival order. |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `DDA9.1` | `InboxWriter` (Share Extension) | Checks the inbox for existing pending items written from content shared by other apps via the Share Sheet. |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Main app (`OnboardingState`, `SyncPreference`, `FreezeController`, `ClipboardCaptureCoordinator`) | App's own settings only: onboarding-completed flag, iCloud sync opt-in, freeze state, clipboard-offer dedupe. No third-party access. |

**APIs audited and confirmed not used:**

| API category | Status |
|---|---|
| `NSPrivacyAccessedAPICategorySystemBootTime` | Not used — no `systemUptime`, `mach_absolute_time`, or monotonic clock calls in production code |
| `NSPrivacyAccessedAPICategoryDiskSpace` | Not used — no `volumeAvailableCapacity` or `attributesOfFileSystem` calls |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | Not used — no `UITextInputMode.activeInputModes` calls |

**No tracking, no third-party SDKs, no data collection.** All card data stays on-device in SwiftData. CloudKit private DB sync (v1.1) will also remain in the user's private iCloud account.
