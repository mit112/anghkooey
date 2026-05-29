# Anki .apkg Import — Design Spec (v1.5)

> Status: Approved. Implementation plan target: v1.5.
> Reviewed by: Codex (gpt-5.5 xhigh), 2026-05-28 (two passes).

---

## Scope

One-way import of Anki `.apkg` files into Anghkooey. No export. No round-trip. Positions Anghkooey as a migration destination for lapsed Anki users.

**In scope:**
- Basic (Front/Back) note type only — discriminated by `model.type == 0` AND field names contain "Front" and "Back" (case-insensitive). All other notes skipped with count.
- HTML tag stripping + entity decoding + Anki audio token stripping
- Anki due date preservation (cards don't all pile up on day 1)
- Deck name → tag mapping (nested decks split on `::`)
- Duplicate detection on re-import
- In-app document picker entry point

**Out of scope:**
- Cloze, Image Occlusion, custom note types, or `model.type == 0` notes without Front/Back fields — all skipped
- Media (images, audio files) — stripped silently; `[sound:...]` tokens removed from text
- Anki review history / SM-2 scheduling state
- Export back to Anki

---

## 1. Architecture & Module Layout

```
AnghkooeyCore/Sources/AnghkooeyCore/
└── Import/
    ├── AnkiImporter.swift          # protocol + live impl; public API
    ├── SQLiteReader.swift          # thin libsqlite3 C wrapper
    ├── AnkiPackageParser.swift     # unzip + SQLite query → [AnkiNote]
    ├── AnkiNoteMapper.swift        # AnkiNote → MappedCard
    └── HTMLSanitizer.swift         # entity decode + tag strip + audio token strip

AnghkooeyUI/Sources/AnghkooeyUI/
└── Import/
    └── AnkiImportView.swift        # document picker + progress + result sheet
```

### Public API

Two-phase API — scan first, import second. The UI Confirm state sits between them; no stream is suspended waiting for user input.

```swift
public protocol AnkiImporterProtocol: Sendable {

    /// Phase 1: extract metadata without writing to the store.
    func scanPackage(at url: URL) async throws -> AnkiScanResult

    /// Phase 2: write cards to the store, streaming progress.
    func importPackage(
        at url: URL,
        now: Date,
        maxCards: Int
    ) -> AsyncThrowingStream<AnkiImportProgress, any Error>
}

public struct AnkiScanResult: Sendable {
    public let totalNotes: Int
    public let skippableNotes: Int   // non-Basic / missing Front+Back
    public let deckNames: [String]   // for display in Confirm UI
}

public enum AnkiImportProgress: Sendable {
    case importing(imported: Int, total: Int)
    case completed(AnkiImportResult)
}

public struct AnkiImportResult: Sendable {
    public let imported: Int
    public let skipped: Int      // non-Basic / unrecognised note types
    public let duplicates: Int   // matched sourceSpan, already in store
    public let truncated: Bool   // true if maxCards limit was hit
}

public enum AnkiImportError: Error, @unchecked Sendable {
    case notAnApkgFile
    case fileAccessDenied
    case corruptedArchive
    case databaseCorrupted
    case storeFailed(underlying: any Error)
}
```

`@unchecked Sendable` on `AnkiImportError` is the standard Swift 6 pattern for error types that wrap `any Error`; the enum has no mutable state so the annotation is safe.

`LiveAnkiImporter` takes a `CardStoreProtocol` at init. `MockAnkiImporter` returns fixed values/streams for tests and SwiftUI previews. All parsing types below `AnkiImporter` are `internal`.

### CardStoreProtocol additions

```swift
/// Dedup check — returns existing card if sourceSpan already in store.
func findBySourceSpan(_ span: String) async throws -> Card.Snapshot?

/// Import path — accepts a caller-supplied dueAt rather than defaulting to now.
func createImported(
    question: String,
    answer: String,
    sourceSpan: String?,
    tags: [String],
    dueAt: Date,
    now: Date
) async throws -> Card.Snapshot
```

The existing `create(question:answer:sourceSpan:tags:now:)` is unchanged; `createImported` is a new overload used exclusively by the importer to preserve Anki due dates.

### Schema change (V4)

`AnghkooeySchemaV4` adds `@Attribute([.indexed])` to `Card.sourceSpan`. This is a lightweight migration (index-only, no data movement). Required so `findBySourceSpan` doesn't do a full-table scan across large libraries.

---

## 2. Data Flow

```
URL (.apkg)
  → security-scoped resource access (failure → .fileAccessDenied)
  → [ZipFoundation] probe file order: .anki21b → .anki21 → .anki2
      note: .anki21b is zstd-compressed; decompress before SQLite open (see Open Item #1)
      extract to tmp dir
  → [SQLiteReader] open DB
      query col   → crt (collection created timestamp), models JSON, decks JSON
      query notes → id, mid, flds, tags
      query cards → nid, did, odid, type, due, odue
      JOIN notes + cards on notes.id = cards.nid
  → [AnkiPackageParser]
      parse models JSON → Map<modelId, (type: Int, fields: [String])>
      parse decks JSON  → Map<deckId, deckName>
      produce [AnkiNote]

  ── PHASE 1 ENDS: return AnkiScanResult ──

  → [AnkiNoteMapper] for each AnkiNote → MappedCard or skip
      skip if model.type != 0
      skip if model fields don't contain "Front" and "Back" (case-insensitive)
      split flds on \x1f → front, back
      HTMLSanitizer.process(front), HTMLSanitizer.process(back)
      split deckName on "::" → tags array (e.g. "Medical::Anatomy" → ["Medical","Anatomy"])
      dueAt = dueDate(cardType, due, odue, odid, collectionCreatedAt, importedAt)
  → [CardStoreProtocol]
      findBySourceSpan("anki:\(note.id)") → if found, increment duplicates, skip
      createImported(question:answer:sourceSpan:tags:dueAt:now:) per MappedCard
      emit .importing(imported:total:) per card
  → emit .completed(AnkiImportResult)
  → cleanup tmp dir
```

### Due date conversion

```swift
func dueDate(
    cardType: Int,
    due: Int,
    odue: Int,
    odid: Int,
    collectionCreatedAt: Date,
    importedAt: Date
) -> Date? {
    let effectiveDue = odid != 0 ? odue : due  // filtered deck: use odue
    switch cardType {
    case 0:        // new — due is queue position, not a date
        return nil
    case 1, 3:     // learning / relearning — due is Unix timestamp (seconds)
        return Date(timeIntervalSince1970: Double(effectiveDue))
    case 2:        // review — due is days since collection creation
        return collectionCreatedAt.addingTimeInterval(Double(effectiveDue) * 86_400)
    default:
        return nil
    }
}
```

`nil` due date → card imported as `.new`, `dueAt = importedAt` (due immediately).

### HTMLSanitizer contract

Order is strict: **decode entities → strip audio tokens → strip HTML tags.**

1. Decode HTML entities: `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&nbsp;` (→ space), numeric `&#NNN;` forms.
2. Strip Anki audio tokens: `[sound:filename.mp3]` patterns (regex `\[sound:[^\]]+\]`).
3. Strip HTML tags: all `<...>` sequences including self-closing.

LaTeX delimiters (`[latex]...[/latex]`) and MathJax (`\(...\)`, `\[...\]`) are left as-is.

---

## 3. UI

Entry point: **Import** button in Library tab toolbar. Presents `AnkiImportView` as a sheet.

### State machine

```
Idle → Picking → Scanning → Confirm → Importing → Done
                                  ↓               ↓
                                Cancel          Cancel (partial import kept)
                                  ↓
                                Idle
                Error (from any phase) → Error state → Try Again → Idle
```

### States

| State | Content |
|---|---|
| **Idle** | Explainer ("Import an Anki .apkg file. Only Basic cards are imported. Images are removed.") + "Choose File" button |
| **Picking** | `fileImporter` with `UTType("com.ankimobile.apkg")` — no fallback to `.item`; invalid extension/access surfaces appropriate error |
| **Scanning** | Indeterminate `ProgressView` + "Reading package…" |
| **Confirm** | "Found N cards (M unsupported will be skipped). Import up to 5,000?" — Import / Cancel |
| **Importing** | Determinate `ProgressView(value: imported, total: total)` + "Importing… N of M cards" + Cancel button |
| **Done** | "Imported N cards · Skipped M · X duplicates skipped[· Truncated at 5,000]" + Dismiss |
| **Error** | Human-readable message per `AnkiImportError` case + "Try Again" (→ Idle) |

`AnkiImportError` → UI message mapping:

| Case | Message |
|---|---|
| `notAnApkgFile` | "This file doesn't appear to be an Anki package (.apkg)." |
| `fileAccessDenied` | "Anghkooey couldn't access this file. Try moving it to a local folder first." |
| `corruptedArchive` | "The package file is corrupted or incomplete." |
| `databaseCorrupted` | "The deck database inside this package couldn't be read." |
| `storeFailed` | "Something went wrong saving cards. Your existing cards are safe." |

**Edge cases handled:** empty package (0 importable cards → Done with imported=0), all-skipped, maxCards truncation, security-scoped URL failure, picker cancelled (sheet dismisses silently).

**Cancellation disclosure** shown inline below Cancel button during Importing: "Already imported cards are kept. Re-importing this file will skip duplicates."

**`onOpenURL` handler** in `AnghkooeyApp` sets a pending URL that triggers `AnkiImportView` to open and pre-populates the file URL, bypassing the picker step.

---

## 4. Testing

All tests in `AnghkooeyTests` app target (consistent with existing suite).

### `AnkiNoteMapperTests` — inject `AnkiNote` structs directly (no fixture)

| Test | Covers |
|---|---|
| `parse_basicNote_mapsToMappedCard` | Correct question/answer/tags/dueAt |
| `parse_clozeNote_isSkipped` | model.type != 0 → skipped |
| `parse_modelMissingFrontBack_isSkipped` | type==0 but fields aren't Front/Back → skipped |
| `parse_nestedDeck_splitToTags` | `Medical::Anatomy` → `["Medical","Anatomy"]` |
| `dueDate_reviewCard_usesCollectionEpoch` | type=2 → collectionCreatedAt + days |
| `dueDate_learningCard_usesUnixTimestamp` | type=1 → Unix timestamp |
| `dueDate_newCard_returnsNil` | type=0 → nil |
| `dueDate_filteredDeck_usesOdue` | odid!=0 → uses odue |

### `HTMLSanitizerTests`

`@Test(arguments: sanitizerCases)` parameterized over ≥5 input/output pairs:
- Entity decoded before tag stripped: `&lt;b&gt;text&lt;/b&gt;` → `text`
- Audio token stripped: `hello [sound:beep.mp3] world` → `hello  world`
- Nested tags: `<div><b>x</b></div>` → `x`
- Self-closing: `foo<br/>bar` → `foobar`
- LaTeX passthrough: `\(x^2\)` → `\(x^2\)` (unchanged)

### `AnkiImporterTests` — hand-crafted fixture + MockCardStore

| Test | Covers |
|---|---|
| `import_duplicate_incrementsDuplicateCount` | Re-import same noteId → duplicates=1 |
| `import_maxCards_truncatesAt5000` | 6,000-note fixture → imported=5,000, truncated=true |
| `import_storeFailure_propagatesError` | `createImported` throws → stream throws |
| `stream_progressEventsAreOrdered` | Emitted imported counts strictly increase |
| `stream_throwingPath_terminatesOnFirstError` | Fatal error → throws, no further events |
| `parse_corruptedZip_throwsCorruptedArchive` | Invalid zip bytes → `corruptedArchive` |
| `parse_corruptedSQLite_throwsDatabaseCorrupted` | Valid zip, bad SQLite → `databaseCorrupted` |
| `scan_returnsCorrectCounts` | Phase 1 returns expected totalNotes and skippableNotes |
| `smoke_realApkgExport_importsNonZero` | Real Anki-exported fixture → imported > 0, no crash |

**Fixtures:**
- `Tests/Fixtures/sample.apkg` — hand-crafted (~5 KB): 2 Basic notes, 1 Cloze, 1 nested-deck card, 1 HTML-heavy card, 1 audio-token card
- `Tests/Fixtures/real-export.apkg` — one real AnkiWeb public deck (Basic note type), committed for smoke test

Stream consumption: `for try await event in stream { ... }` — assert ordered `.importing` events then `.completed`.

---

## 5. Package & Configuration Changes

### `AnghkooeyCore/Package.swift`

```swift
// dependency (pin exact version, not range)
.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19"),

// target linkerSettings
.linkedLibrary("sqlite3")
```

Verify MIT license at integration time. Exact version pin is required — do not use `.upToNextMajor`.

### `App/Anghkooey/Info.plist`

```xml
<key>UTImportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key><string>com.ankimobile.apkg</string>
    <key>UTTypeConformsTo</key><array><string>public.zip-archive</string></array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array><string>apkg</string></array>
    </dict>
  </dict>
</array>
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key><string>Anki Package</string>
    <key>LSItemContentTypes</key><array><string>com.ankimobile.apkg</string></array>
    <key>CFBundleTypeRole</key><string>Viewer</string>
  </dict>
</array>
```

`LSSupportsOpeningDocumentsInPlace` — explicitly **absent**.

### `PrivacyInfo.xcprivacy`

Existing `NSPrivacyAccessedAPICategoryFileTimestamp` covers ZipFoundation and SQLite file I/O. Before shipping: audit ZipFoundation + libsqlite3 for `getattrlist` / `statfs` calls; add `NSPrivacyAccessedAPICategoryDiskSpace` only if found.

### `project.yml`

No new targets, schemes, or entitlements. Import is pure in-process.

---

## Open Items (resolve during implementation)

1. **`.anki21b` zstd support** — confirm whether ZipFoundation 0.9.x handles zstd-compressed entries or whether a separate decompression step is needed. If unsupported, show `corruptedArchive` with message: "Export from Anki as a legacy .apkg to import."
2. **ZipFoundation exact version** — confirm `0.9.19` is current stable; check release notes for iOS 26 compatibility before pinning.
3. **Real-export smoke fixture** — source a small public Basic-only deck from AnkiWeb; commit as `Tests/Fixtures/real-export.apkg`.
