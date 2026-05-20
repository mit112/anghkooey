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
