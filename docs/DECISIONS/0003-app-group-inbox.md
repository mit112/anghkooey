# 0003 — App Group Inbox: Design Contract for Share Extension ↔ Main App Handoff

**Date:** 2026-05-21  
**Status:** Accepted  
**Milestone:** M3 entry gate — no Share Extension code lands until this ADR is committed.

---

## Context

M3 ships two capture surfaces: a Share Extension (primary) and an in-app camera (secondary). Both funnel captured material into `CardAuthor` for AI-assisted card generation. The Share Extension runs in a sandboxed process separate from the main app. It must persist captures to shared storage so the main app can drain them — even if the main app is not running when the extension fires.

Key constraints that shaped this design:

1. **Share Extensions have a hard 60-second wall-clock budget** from presentation to `completeRequest`. OCR on a typical page image (VNRecognizeTextRequest, accurate mode) takes 1–3 seconds on A-series — within budget but consuming a meaningful chunk of it. Keeping the extension lightweight is preferable.
2. **Extension memory limit is ~120 MB** (observed; not guaranteed by Apple). Vision OCR can spike past this on dense images.
3. **The main app may be foregrounded** when the extension fires (e.g., user switches from Anghkooey to Safari, selects text, shares back). The main app must drain without waiting for the next foreground transition.
4. **Race conditions between extension writes and main-app reads must be safe** without distributed locking. The design must achieve this through structural separation (extension appends, main app deletes) rather than file locks.
5. **Duplicate submissions are a real UX problem.** A user who taps "Share" twice on the same selection (a common mistake) must not get two identical card drafts.

---

## Decision

### 1. On-disk format

**One JSON file per submission.** No append-only log.

Rationale: atomic writes are trivial with individual files (temp-file + rename on the same filesystem). An append-only log requires either a write lock or CRDT-style conflict resolution that adds complexity for no benefit at this scale. Individual files can also be deleted independently after draining without touching other in-flight items.

### 2. Path layout

```
<AppGroupContainer>/               (group.com.mitsheth.anghkooey)
  inbox/
    <UUID>.json                    # one file per submission
    images/
      <UUID>.heic                  # raw capture for imageRef items only
```

- `inbox/` — extension writes here; main app drains and deletes here.
- `inbox/images/` — image files referenced by `.imageRef` inbox items. The main app deletes the image file after OCR completes (on drain), not before.
- The `UUID` in the image filename matches the `id` field of the corresponding `.json` item, making cleanup unambiguous.

### 3. Schema

Each `<UUID>.json` is a UTF-8 JSON object with the following fields:

```json
{
  "schemaVersion": 1,
  "id": "<UUID-v4>",
  "capturedAt": "<ISO 8601 UTC>",
  "sourceApp": "<bundle-id of host app, e.g. com.apple.mobilesafari>",
  "kind": "text",
  "text": "<raw captured string>",
  "textHash": "<SHA-256 hex of normalized text, see §6>",
  "imagePath": null
}
```

For image captures (`kind: "imageRef"`):

```json
{
  "schemaVersion": 1,
  "id": "<UUID-v4>",
  "capturedAt": "<ISO 8601 UTC>",
  "sourceApp": "<bundle-id>",
  "kind": "imageRef",
  "text": null,
  "textHash": null,
  "imagePath": "images/<UUID>.heic"
}
```

- `imagePath` is always **relative to the `inbox/` directory**, not an absolute path. App Group container paths are stable per-device, but relative paths survive any future container relocation.
- `schemaVersion: 1` allows the main app to skip items it cannot parse if this ADR is ever revised during an in-flight upgrade.
- Swift representation: `InboxItem` struct in `AnghkooeyCore`, decoded with `Codable`. `kind` is an enum with cases `text` and `imageRef`.

### 4. Atomic write pattern

The extension must never leave a partial `.json` file visible to the main app.

```
write to:   inbox/<UUID>.json.tmp   (extension's private staging file)
rename to:  inbox/<UUID>.json       (atomic on same filesystem)
```

Implementation: `FileManager.moveItem(at:to:)` on the same volume is atomic on Darwin (single `rename(2)` syscall). The main app only enumerates files ending in `.json` (not `.tmp`), so a crashed extension leaves an orphan `.tmp` at worst — never a corrupt `.json`.

The image file for `imageRef` items is written **before** the `.json` is renamed into place. If the extension crashes between image write and rename, the main app's orphan-cleanup pass (§5) handles the dangling image.

### 5. Lifecycle

**Extension (write path):**

1. Receive `NSExtensionItem` from host app.
2. For `text` kind: extract string, compute `textHash`, check dedup (§6), write `<UUID>.json.tmp`, rename to `<UUID>.json`.
3. For `imageRef` kind: write image to `inbox/images/<UUID>.heic`, write `<UUID>.json.tmp`, rename to `<UUID>.json`.
4. Post Darwin notification `com.mitsheth.anghkooey.inboxDidChange` (§8).
5. Call `extensionContext?.completeRequest(returningItems: nil)`.
6. The extension process never reads or deletes inbox items. **Extension is write-only.**

**Main app (drain path):**

The `InboxDrainer` actor in `AnghkooeyCore` owns all drain logic.

1. Enumerate `inbox/*.json` (sorted by `capturedAt` ascending — oldest first).
2. For each item:
   a. Decode `InboxItem`. On decode failure: delete the file (corrupt item), continue.
   b. If `schemaVersion > 1`: skip (cannot parse), leave for a future app version.
   c. If `kind == .imageRef`: run `VNRecognizeTextRequest` on the image at `imagePath`. On OCR failure: delete both files, emit a `Logger.error`, continue.
   d. Route the resulting text to `CardAuthor` (or to the manual-entry sheet if `CardAuthor` is unavailable — mirrors M2 design).
   e. On success: delete `<UUID>.json` (and `images/<UUID>.heic` if applicable).
   f. On failure to route (e.g. `CardAuthor` throws): **leave the item in the inbox** and stop the current drain. The next drain will retry from the top.
3. After all items processed: delete any `inbox/images/<orphan>.heic` files that have no corresponding `.json` (crash-cleanup).
4. Delete any `inbox/<UUID>.json` or `inbox/images/<UUID>.heic` files with `capturedAt` more than **7 days** in the past (orphan eviction). This covers items that failed routing persistently (e.g. `CardAuthor` always unavailable during a bad build) without filling the App Group indefinitely.

**Drain is triggered by:**
- App launch (`AnghkooeyApp.init` or `applicationDidFinishLaunching`).
- Scene entering foreground (`sceneWillEnterForeground` / `UIApplication.willEnterForegroundNotification`).
- Darwin notification observer (§8) — fires when extension writes while app is foregrounded.

### 6. Dedup strategy

Goal: prevent duplicate card drafts from a user tapping "Share" twice on the same selection.

**Text items:**
- Normalize: `text.trimmingCharacters(in: .whitespacesAndNewlines)`, then lowercase.
- Hash: SHA-256 of the UTF-8 bytes. Store as lowercase hex in `textHash`.
- Before writing a new item, the extension lists all `.json` files in `inbox/` with `capturedAt` within the **60-second dedup window** of `now`. If any existing item has the same `textHash`, the new submission is silently dropped and the extension calls `completeRequest` normally (the user sees no error — they already shared it).
- SHA-256 is used (not MD5/CRC) because it is available in `CryptoKit` with no additional import and its collision resistance is appropriate for dedup keys on user-generated text.

**Image items:**
- No dedup. Images from the Share Extension are rare and identical image shares are even rarer. The complexity of perceptual hashing or byte-level hashing of potentially large HEIC files is not justified in v1.

**Limitation acknowledged:** A race where two extension processes fire simultaneously (uncommon, requires the user to share from two apps in the same 60-second window) could result in both items passing the dedup check. The outcome — two identical card drafts — is annoying but not dangerous. The user dismisses the duplicate. This is acceptable in v1.

### 7. Maximum payload size and overflow handling

| Kind | Limit | Overflow behavior |
|------|-------|-------------------|
| Text (`text` field) | 50,000 characters | Truncate at the last sentence boundary (`.`, `!`, `?`) before the limit. Append `" [truncated]"` as a suffix. Write the truncated text. |
| Image file | 25 MB | On drain, if the image file exceeds 25 MB, the main app deletes it and emits a `Logger.warning`. No card draft is produced. |
| Total `inbox/` directory | No explicit cap | Orphan eviction (7-day TTL) keeps this bounded in practice. If the directory exceeds 50 items (implies a persistently broken drain), the main app logs a `Logger.fault` — this is a bug signal, not something the app recovers from silently. |

The 50,000-character text limit covers approximately 10 pages of prose — far beyond any realistic share-sheet selection. It is a safety valve against a Share Extension receiving a pathological input (e.g., a user sharing a 300-page PDF's full text).

### 8. Concurrency when extension fires while main app is foregrounded

**Cross-process signaling: Darwin notifications**

After the atomic rename (§4), the extension posts to the Darwin notification center:

```swift
// Extension — after successful rename:
CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    "com.mitsheth.anghkooey.inboxDidChange" as CFString,
    nil, nil, true   // deliverImmediately: true
)
```

The main app registers an observer once (on launch):

```swift
// Main app — AppDelegate or AnghkooeyApp.init:
CFNotificationCenterAddObserver(
    CFNotificationCenterGetDarwinNotifyCenter(),
    nil,
    { _, _, _, _, _ in
        Task { await InboxDrainer.shared.drain() }
    },
    "com.mitsheth.anghkooey.inboxDidChange" as CFString,
    nil,
    .deliverImmediately
)
```

`InboxDrainer` is a Swift actor — the `Task { await ... }` ensures drain calls serialize naturally even if multiple Darwin notifications arrive in quick succession.

**Filesystem concurrency invariant:**
- Extension only creates new files (writes `<UUID>.json`, `images/<UUID>.heic`).
- Main app only deletes files (after successful drain) and reads files (during drain enumeration).
- These operations are disjoint on the filesystem. No file is ever written by one process and simultaneously written by the other. `rename(2)` is atomic. This design requires no POSIX file lock.

**Edge case — extension fires mid-drain:** The main app's drain enumeration captures a snapshot of `inbox/` at the start of the drain. A file written by the extension after enumeration starts is not in that snapshot. The Darwin notification triggers a second drain (queued behind the active one in the actor). The new item is picked up by the second drain. No item is lost.

---

## Consequences

- **Positive:** Simple, auditable, crash-safe handoff. Each item is an independent file — a crash anywhere leaves the other items intact.
- **Positive:** OCR runs in the main app (drain path), which has full memory headroom and can surface progress UI. The extension stays lightweight.
- **Positive:** Darwin notifications give zero-polling, zero-latency wakeup when the app is foregrounded.
- **Positive:** The 7-day orphan TTL prevents App Group storage from growing unbounded even if `CardAuthor` is persistently unavailable (e.g., during development).
- **Negative:** The extension must enumerate existing inbox items for dedup, which adds a small filesystem round-trip before every write. Acceptable — `inbox/` is expected to hold < 20 items at any time.
- **Negative:** `imageRef` items require two files (JSON + HEIC). Crash between them leaves an orphan image; cleaned up on next drain. This is a known, handled edge case, not a correctness bug.
- **Action required:** The App Group entitlement (`com.apple.security.application-groups` = `group.com.mitsheth.anghkooey`) must be added to both the main app target and the Share Extension target in Xcode, and provisioned in the Apple Developer portal, before any inbox code can be tested on device.
- **Action required:** The Share Extension needs its own `PrivacyInfo.xcprivacy` (separate from the main app's), audited for any required-reason API usage (file timestamps, `CFNotificationCenter`). This is an M3 exit gate requirement.

---

## Constants (locked by this ADR)

These values are defined in `AnghkooeyCore/InboxConstants.swift` (single source of truth):

```swift
enum InboxConstants {
    static let appGroupID          = "group.com.mitsheth.anghkooey"
    static let inboxDirectory      = "inbox"
    static let imagesDirectory     = "inbox/images"
    static let darwinNotificationName = "com.mitsheth.anghkooey.inboxDidChange"
    static let dedupWindowSeconds: TimeInterval = 60
    static let textCharacterLimit  = 50_000
    static let imageFileSizeLimit  : Int64 = 25 * 1_024 * 1_024   // 25 MB
    static let orphanEvictionDays  = 7
    static let inboxItemLimit      = 50   // fault threshold, not a hard cap
    static let schemaVersion       = 1
}
```

Any future change to these values constitutes a revision to this ADR and must bump `schemaVersion` if it affects the JSON format.
