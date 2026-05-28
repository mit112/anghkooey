# Architecture

> This is a living document. Sections will be filled in as milestones are completed.

## Modules

> See implementation plan for details.

## Concurrency

> See implementation plan for details.

## Logging

Each package owns its `*Log.swift` with a `static var subsystem: String` injected by the app
composition root at `AnghkooeyApp.init()` via `Bundle.main.bundleIdentifier`. The Share Extension
(M3) sets its own subsystem to the *app's* bundle ID so logs unify under one subsystem in Console.app.

Categories: CoreLog (Scheduling, Persistence, CaptureInbox) · IntelligenceLog (AI, OCR) · UILog (Review, Library, Capture)

## Errors

> See implementation plan for details.

## v1.5 — Anki .apkg Import (2026-05-28)

One-way import from Anki `.apkg` files. Basic (Front/Back) notes only; HTML stripped via `HTMLSanitizer`; Anki due dates preserved; deck names split on `::` into tags.

**New in AnghkooeyCore:**
- `AnghkooeySchemaV4` — lightweight migration anchor from V3; `makeInMemoryContainer` now passes `cloudKitDatabase: .none` explicitly (iOS 26 auto-enables CloudKit when entitlements present).
- `CardStoreProtocol.findBySourceSpan(_:)` + `createImported(...)` — dedup check and date-preserving create.
- `Import/` subdirectory: `AnkiImportError` (Equatable), `SQLiteReader` (libsqlite3 wrapper), `AnkiPackageParser` (ZIPFoundation + SQL), `AnkiNoteMapper` (Basic filter + due-date conversion), `HTMLSanitizer` (entity decode → audio strip → tag strip), `LiveAnkiImporter` (two-phase scan/import, `AsyncThrowingStream`), `MockAnkiImporter`.

**New in AnghkooeyUI:**
- `AnkiImportView` — 5-state sheet (Idle → Scanning → Confirm → Importing → Done/Error).
- `LibraryView` — Import toolbar button + sheet wiring.

**App changes:**
- `AnghkooeyApp.onOpenURL` — handles `.apkg` open-in from Files/Share Sheet; `URL: Identifiable` retroactive conformance.
- `Info.plist` (via xcodegen `info.path`) — `UTImportedTypeDeclarations` + `CFBundleDocumentTypes` for `com.ankimobile.apkg`.
- `scripts/patch_privacy_info.py` — idempotent Python patch that re-applies the 12 PrivacyInfo.xcprivacy pbxproj entries after every `make generate`.

**New dependency:** ZIPFoundation 0.9.20 (exact pin, MIT).

**Tests added:** 35 new tests across SchemaMigrationV4, CardStoreImport, HTMLSanitizer (8 parameterized), AnkiPackageParser, AnkiNoteMapper (10), AnkiImporter (8). Total suite: 63 tests.
