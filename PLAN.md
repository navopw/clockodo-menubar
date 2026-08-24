# Clockodo Menubar Plan

## Goal

Provide a small, native macOS menubar utility that makes the Clockodo stop clock available without opening a browser.

## Architecture

- **UI:** SwiftUI `MenuBarExtra` with the `.window` style.
- **Minimum OS:** macOS 13, the first release with `MenuBarExtra`.
- **Networking:** Foundation `URLSession`, using the Clockodo REST API directly.
- **Secrets:** macOS Keychain Services for the Clockodo email and API key.
- **Local state:** `UserDefaults` for the last customer, project, and service selection only. No time-entry data or API keys are persisted there.
- **Packaging:** A universal (arm64 and x86_64) `.app` with `LSUIElement=true`; packaging uses an ad-hoc signature.
- **Releases:** Every push to `main` publishes a `v1.0.<run number>` GitHub release with a universal ZIP archive and its SHA-256 checksum.

## API Contract

| App operation | Clockodo request |
| --- | --- |
| Read running timer | `GET /api/v2/clock` |
| Read authenticated user | `GET /api/v4/users/me` |
| Start timer | `POST /api/v2/clock` |
| Stop timer | `DELETE /api/v2/clock/{entry_id}` |
| Load customers | `GET /api/v3/customers` |
| Load projects | `GET /api/v4/projects` |
| Load services | `GET /api/v4/services` |
| Load today's entries | `GET /api/v2/entries` with `time_since`, `time_until`, and `filter[users_id]` |

Every request includes `X-ClockodoApiUser`, `X-ClockodoApiKey`, and `X-Clockodo-External-Application`.

## Delivery Phases

### Phase 1: Working MVP

- Connect with Clockodo credentials.
- Load active customer, project, and service choices.
- Start and stop the current Clockodo timer.
- Display live elapsed time in the menubar.
- Refresh the remote running state every 60 seconds.
- Validate credentials before storing them.
- Show connection state and retry actions.
- Support launch-at-login.
- Show today's tracked total.
- Start the last valid selection with one click.

### Phase 2: Daily Workflow

- Show the last few entries and allow opening the matching Clockodo page.

### Phase 3: Release Quality

- Add SwiftUI UI tests and broader state-transition coverage; decoding and HTTP error-response tests are covered by the MVP test suite.
- Add an app icon and accessibility labels.
- Add a release build signed with Developer ID and notarized by Apple.
- Automatic in-app updates are intentionally not planned; GitHub releases are used instead.

## Deliberate Non-Goals

- No webhook relay. Clockodo webhooks need a public HTTPS endpoint, which is unnecessary for a local menubar app.
- No offline queue for start/stop actions. A queued stop/start could create incorrect billable time; failures remain visible instead.
- No editing of historical entries in the MVP. That adds permissions, edit-lock, and duration semantics that are not needed for the core workflow.

## Risks

- Clockodo's API rate limit is per endpoint, and no numeric limit is public. Polling is therefore deliberately limited to once per minute.
- The external application header must include a contact email and is limited to 50 characters in the current SDK documentation. The MVP derives it from the configured Clockodo email and rejects an overlong value before making a request.
- API access is subject to the configured Clockodo user's permissions. An empty catalog or a 403 response can be a permission issue rather than a client bug.
