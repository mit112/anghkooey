# Anki .apkg Import — Design Spec (v1.5)

> Status: Approved. Implementation plan target: v1.5.
> Reviewed by: Codex (gpt-5.5 xhigh), 2026-05-28.

---

## Scope

One-way import of Anki `.apkg` files into Anghkooey. No export. No round-trip. Positions Anghkooey as a migration destination for lapsed Anki users.

**In scope:**
- Basic (Front/Back) note type only
- HTML tag stripping + entity decoding
- Anki due date preservation (cards don't all pile up on day 1)
- Deck name → tag mapping (nested decks split on `::`)
- Duplicate detection on re-import
- In-app document picker entry point

**Out of scope:**
- Cloze, Image Occlusion, or custom note types (skipped with count)
- Media (images, audio) — stripped silently
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
    └── HTMLSanitizer.swift         # entity decode + tag strip

AnghkooeyUI/Sources/AnghkooeyUI/
└── Import/
    └── AnkiImportView.swift        # document picker + progress + result sheet
```

### Public API

```swift
public protocol AnkiImporterProtocol: Sendable {
    func importPackage(
        at url: URL,
        now: Date,
        maxCards: Int
    ) -> AsyncThrowingStream<AnkiImportProgress, AnkiImportError>
}

public enum AnkiImportProgress: Sendable {
    case scanning                           // archive + DB scan phase
    case ready(total: Int, skippable: Int)  // metadata parsed; awaiting confirm
    case importing(imported: Int, total: Int)
    case completed(AnkiImportResult)
}

public struct AnkiImportResult: Sendable {
    public let imported: Int
    public let skipped: Int      // non-Basic / unrecognised note types
    public let duplicates: Int   // matched sourceSpan, already in store
    public let truncated: Bool   // true if maxCards limit was hit
}

public enum AnkiImportError: Error, Sendable {
    case notAnApkgFile
    case corruptedArchive
    case databaseCorrupted
    case storeFailed(underlying: Error)
}
```

`LiveAnkiImporter` takes a `CardStoreProtocol` at init. `MockAnkiImporter` returns a fixed stream for tests and SwiftUI previews. All parsing types below `AnkiImporter` are `internal`.

### CardStoreProtocol addition

```swift
func findBySourceSpan(_ span: String) async throws -> Card.Snapshot?
```

Used for dedup; `sourceSpan = "anki:\(noteId)"` is the key. Anki note IDs are stable integers across re-exports of the same deck.

---

## 2. Data Flow

```
URL (.apkg)
  → security-scoped resource access
  → [ZipFoundation] probe file order: .anki21b → .anki21 → .anki2
      note: .anki21b is zstd-compressed; decompress before SQLite open
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
  → [AnkiNoteMapper] for each AnkiNote → MappedCard or skip
      skip if model.type != 0
      skip if model fields don't contain "Front" and "Back" (case-insensitive)
      split flds on \x1f → front, back
      HTMLSanitizer.process(front), HTMLSanitizer.process(back)
      split deckName on "::" → tags array (e.g. "Medical::Anatomy" → ["Medical","Anatomy"])
      dueAt = dueDate(cardType, due, odue, odid, collectionCreatedAt, importedAt)
  → emit .ready(total:skippable:) — UI shows confirmation
  → [CardStoreProtocol]
      findBySourceSpan("anki:\(note.id)") → if found, increment duplicates, skip
      create(question:answer:sourceSpan:tags:now:) per MappedCard
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
    case 0:        // new — not yet seen; due is queue position, not a date
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

`nil` due date → card imported as `.new`, `dueAt = importedAt` (due immediately, no fabricated ordering).

### HTMLSanitizer contract

Order is strict: **decode entities first, then strip tags.**

Entities decoded: `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&nbsp;` (→ space), numeric `&#NNN;` forms.
Tags stripped: all `<...>` sequences including self-closing.
LaTeX delimiters (`[latex]...[/latex]`), MathJax (`\(...\)`, `\[...\]`) are left as-is — not stripped.

---

## 3. UI

Entry point: **Import** button in Library tab toolbar. Presents `AnkiImportView` as a sheet.

### States

| State | Content |
|---|---|
| **Idle** | Explainer ("Import an Anki .apkg file. Only Basic cards are imported. Images are removed.") + "Choose File" button |
| **Picking** | `fileImporter` with `UTType("com.ankimobile.apkg")` — no fallback to `.item`; invalid extension surfaces `notAnApkgFile` |
| **Scanning** | Indeterminate `ProgressView` + "Reading package…" |
| **Confirm** | "Found N cards (M unsupported will be skipped). Import up to 5,000?" — Import / Cancel |
| **Importing** | Determinate `ProgressView(value: imported, total: total)` + "Importing… N of M cards" + Cancel button |
| **Done** | "Imported N cards · Skipped M · X duplicates skipped[· Truncated at 5,000]" + Dismiss |
| **Error** | Human-readable message per `AnkiImportError` case + "Try Again" (→ Idle) |

**Edge cases handled:** empty package (0 importable cards), all-skipped (imported=0), maxCards truncation, security-scoped URL failure, picker cancelled by user (sheet dismisses silently).

**Cancellation disclosure** shown inline below Cancel button: "Already imported cards are kept. Re-importing this file will skip duplicates."

**Partial import is valid.** A cancelled import leaves committed cards in the store. Re-import of the same `.apkg` deduplicates via `sourceSpan`.

**`onOpenURL` handler** in `AnghkooeyApp` triggers `AnkiImportView` programmatically when `.apkg` arrives from Files/Share Sheet open-in.

---

## 4. Testing

All tests in `AnghkooeyTests` app target (consistent with existing suite).

### `AnkiNoteMapperTests` — inject `AnkiNote` structs directly (no fixture)

| Test | Covers |
|---|---|
| `parse_basicNote_mapsToMappedCard` | Correct question/answer/tags/dueAt |
| `parse_clozeNote_isSkipped` | Non-Basic → skipped count |
| `parse_modelMissingFrontBack_isSkipped` | type==0 but fields aren't Front/Back |
| `parse_nestedDeck_splitToTags` | `Medical::Anatomy` → `["Medical","Anatomy"]` |
| `dueDate_reviewCard_usesCollectionEpoch` | type=2 → epoch+days |
| `dueDate_learningCard_usesUnixTimestamp` | type=1 → Unix ts |
| `dueDate_newCard_returnsNil` | type=0 → nil |
| `dueDate_filteredDeck_usesOdue` | odid!=0 → uses odue |

### `HTMLSanitizerTests`

`@Test(arguments: sanitizerCases)` parameterized over ≥5 input/output pairs including entity-before-tag case, nested tags, self-closing tags, LaTeX passthrough.

### `AnkiImporterTests` — use hand-crafted fixture + MockCardStore

| Test | Covers |
|---|---|
| `import_duplicate_incrementsDuplicateCount` | Re-import same noteId → duplicates=1 |
| `import_maxCards_truncatesAt5000` | 6,000-note fixture → imported=5,000, truncated=true |
| `import_storeFailure_propagatesError` | `CardStore.create` throws → stream throws |
| `stream_progressEventsAreOrdered` | Emitted imported counts strictly increase |
| `stream_throwingPath_terminatesOnFirstError` | Fatal error → throws, no further events |
| `parse_corruptedZip_throwsCorruptedArchive` | Invalid zip bytes → `corruptedArchive` |
| `parse_corruptedSQLite_throwsDatabaseCorrupted` | Valid zip, bad SQLite → `databaseCorrupted` |
| `smoke_realApkgExport_importsNonZero` | Real Anki-exported fixture → imported > 0, no crash |

**Fixtures:**
- `Tests/Fixtures/sample.apkg` — hand-crafted (~5 KB): 2 Basic notes, 1 Cloze, 1 nested-deck card, 1 HTML-heavy card
- `Tests/Fixtures/real-export.apkg` — one real AnkiWeb public deck (Basic note type), committed for smoke test

Stream consumption pattern: `for try await event in stream { ... }` — assert ordered progress then final `.completed`.

---

## 5. Package & Configuration Changes

### `AnghkooeyCore/Package.swift`

```swift
// dependency (pin exact version, not range)
.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19"),

// target
.linkedLibrary("sqlite3")  // linkerSettings on AnghkooeyCore target
```

Verify MIT license at integration time. Pin via `Package.resolved` — do not use `.upToNextMajor`.

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

`LSSupportsOpeningDocumentsInPlace` — explicitly **absent** (import-only, not edit-in-place).

### `PrivacyInfo.xcprivacy`

Existing `NSPrivacyAccessedAPICategoryFileTimestamp` covers ZipFoundation and SQLite file I/O. Before shipping: audit ZipFoundation + libsqlite3 for `getattrlist` / `statfs` calls; add `NSPrivacyAccessedAPICategoryDiskSpace` only if found.

### `project.yml`

No new targets, schemes, or entitlements. Import is pure in-process.

---

## Open Items (resolve during implementation)

1. **ZipFoundation exact version** — confirm `0.9.19` is current stable; check release notes for iOS 26 compatibility.
2. **`.anki21b` zstd decompression** — confirm iOS 26 / `libcompression` supports zstd natively or if ZipFoundation handles it. If neither, flag to user that Anki 2.1.55+ packages may fail (show actionable error: "Export from Anki as .apkg (legacy format)").
3. **Real-export smoke fixture** — source a small public Basic-only deck from AnkiWeb; commit as `Tests/Fixtures/real-export.apkg`.
4. **`findBySourceSpan` perf** — if the store grows large, this is called once per imported card. Add an index on `sourceSpan` in the SwiftData `@Model` if it isn't already present (it isn't in V3).
