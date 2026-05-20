# 0001 — Product Name: Anghkooey

**Date:** 2026-05-20  
**Status:** Accepted

---

## Context

The project started under the working name **Rewind**. That name directly collides with two existing products: Rewind AI (the screen-recording memory tool) and Limitless (formerly Rewind), both of which have App Store presence and brand recognition in the same AI-memory category. Shipping under a colliding name creates confusion for users, makes App Store search traffic useless, and creates potential trademark risk before the product gains any traction.

A new name was needed before any public artifact (TestFlight, landing page, social handle) was created.

---

## Decision

The product name is **Anghkooey**, tagline *"remember everything"*.

- **Bundle ID:** `com.mitsheth.anghkooey`
- **SPM packages:** `AnghkooeyCore` / `AnghkooeyIntelligence` / `AnghkooeyUI`
- **Repo directory** (`/Users/mitsheth/Documents/rewind/`) keeps its current path until a deliberate workspace rename — this is a local hygiene concern, not a product one.

---

## Consequences

- **Positive:** No collision with Rewind AI / Limitless in the AI-memory product category. Unique name aids discoverability.
- **Action required — not yet verified:** App Store name availability, `.com` / `.app` domain availability, and USPTO TESS trademark search must all be completed before the first public artifact is pushed. This ADR records the decision; it does not constitute clearance.
- All code, documentation, and public-facing copy must use "Anghkooey" from this point forward.
