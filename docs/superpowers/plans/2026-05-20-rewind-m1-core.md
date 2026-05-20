# Anghkooey M1 — RewindCore: Schema + FSRS-6 Engine

> Detailed plan to be written at M1 session entry. Entry gate: M0 green on `main`.

## Entry Gate Status

- [ ] M0 tagged `m0-complete` on `main`

## M1 Exit Gate (from strategic plan)

- `Card`, `ReviewLog`, `Tag` SwiftData models with v1 migration
- `FSRS6Engine` ported from pinned reference commit
- Parity harness runs on every PR; passes 100% of fixtures
- In-memory `ModelContainer` test container utility for downstream packages
- All public APIs documented with DocC
- `Logger(category: "FSRS")` and `Logger(category: "Persistence")` in place

## Reference

See `docs/superpowers/plans/2026-05-20-rewind-implementation-plan.md` §5 M1 for full entry/exit gates and cut-line.
