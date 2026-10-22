# FRAME Implementation Plan

> **For agentic workers:** Execute inline with executing-plans, test-driven-development and verification-before-completion. Preserve the Windows V3 and its credentials.

**Goal:** Build the native iOS client, authenticated API, PostgreSQL synchronisation and moderated community, then validate every locally executable component and prepare macOS CI.

**Architecture:** Supabase supplies PostgreSQL and email OTP authentication. The Node API proxies TMDB and forwards database requests with the user's verified bearer token, preserving RLS. SwiftUI uses Foundation networking and Keychain, with an account-scoped offline library and mutation queue.

**Tech Stack:** Node 22+, PostgreSQL PL/pgSQL, Supabase Auth/PostgREST, SwiftUI iOS 17+, dependency-free Xcode project generator, GitHub Actions macOS.

## 1. Database contract and isolation
- [x] Create `backend/tests/database.test.mjs`: initialise PGlite with Supabase auth role fixtures; exercise migration, idempotent mutations, revision conflicts, account isolation, premoderation, report and block visibility, deletion cascades and moderator permissions.
- [x] Run `npm test`: verify missing migration failure before adding `supabase/migrations/202610220001_frame.sql`.
- [x] Implement SQL functions with explicit grants, RLS and fixed search paths. Anonymous users receive no database privileges.
- [x] Re-run database tests with authenticated non-owner roles; verify all assertions pass.

## 2. HTTP API and catalogue
- [x] Write `backend/tests/api.test.mjs` with real local HTTP auth/database fixtures: missing and invalid tokens, server-side user identity, body size, origin policy, upstream failures, moderation permission, account deletion confirmation, rate limiting and public catalogue.
- [x] Verify failures before creating `backend/src/app.mjs`, `gateway.mjs`, `server.mjs` and extracting the existing TMDB mapping into `catalogue.mjs`.
- [x] Disable legacy anonymous community writes; production startup requires complete HTTPS configuration and community remains disabled by default.
- [x] Run `npm test`, `npm run check`, and dependency audit.

## 3. Native iOS client
- [x] Write `ios/FRAMETests/LibraryTests.swift` for persistence, account isolation, pending mutations and reconciliation, and authentication model decoding tests.
- [x] Implement Codable models, URLSession API, Keychain session, refresh serialization and atomic library persistence under `ios/FRAME/Core`.
- [x] Build browse/search/detail/season/library/profile/community and email OTP screens under `ios/FRAME/Features`, with loading, error, retry, offline and accessibility states.
- [x] Supply Xcode project and shared scheme, app icon from V3, privacy manifest and configuration examples. No TMDB or service-role key in the application.
- [ ] Compile and run XCTest in GitHub Actions on a dynamically selected available iPhone simulator; report CI separately from local checks.

## 4. Operations and delivery
- [x] Add Dockerfile, environment example, health check and deployment guide. Document backups and a restoration exercise without claiming it has been run on a hosted database.
- [x] Add moderator interface, submission checklist, legal drafting requirements and actual data inventory. Final privacy/terms require the operator’s identity and retention choices and are not fabricated.
- [x] Create a feature branch commit with no secrets and publish to the user-provided empty repository if authentication permits.
- [ ] Track external prerequisites explicitly: Supabase project, production host/domain, legal operator/contact, Apple signing and TestFlight credentials. Do not describe the app as released or App Store ready before those checks.
