# Clockodo Menubar

A native macOS menubar client for the Clockodo stop clock.

## Current Scope

- Store the Clockodo email and API key in the macOS Keychain.
- Load active customers, projects, and services from the current Clockodo API routes.
- Start a Clockodo timer with a customer, optional project, service, and note.
- Stop the currently running timer.
- Show live elapsed time in the menubar.
- Test credentials before storing them and show actionable connection states.
- Offer retry and refresh actions for offline, permission, and rate-limit errors.
- Optionally start automatically at login.
- Show today's tracked total from `/v2/entries`.
- Start the last valid customer, project, and service setup with one click.
- Refresh the running timer approximately once per minute and today's total every five minutes.

## API Research

Clockodo's base URL is `https://my.clockodo.com/api`. Every request uses the per-user `X-ClockodoApiUser` and `X-ClockodoApiKey` headers plus `X-Clockodo-External-Application`.

The stop clock uses `/v2/clock`:

- `GET /v2/clock` reads the current running entry.
- `POST /v2/clock` starts a timer. `customers_id` and `services_id` are required.
- `DELETE /v2/clock/{entry_id}` stops a timer.

Catalog requests use the current routes after Clockodo's May 1, 2026 legacy endpoint removal:

- `/v3/customers`
- `/v4/projects`
- `/v4/services`

Clockodo applies per-endpoint rate limits but does not publish a numeric limit. The app avoids per-second API polling and handles HTTP 429 responses as regular API errors.

Sources:

- [Clockodo API documentation](https://docs.clockodo.com/)
- [Clockodo API deprecation notice](https://www.clockodo.com/en/blog/deprecation-of-legacy-api-endpoints-on-may-1-2026/)
- [Clockodo stop clock API](https://www.clockodo.com/en/api/clock/)
- [Clockodo API rate-limit help](https://support.clockodo.com/en/help-center/too-many-requests-please-try-again-later)
- [Apple MenuBarExtra documentation](https://developer.apple.com/documentation/swiftui/menubarextra)

## Build

Requirements: macOS 13 or newer and Xcode 15 or newer.

```sh
swift test
swift build
./scripts/build-app.sh
open "dist/Clockodo Menubar.app"
```

The app is intentionally packaged as an `LSUIElement`, so it appears in the menubar and not in the Dock. The ad-hoc signature is suitable for local use; a distributable build will need a Developer ID signature and notarization.

## Releases

The manual `Release` workflow on GitHub creates a macOS ZIP release. Select `patch`, `minor`, or `major`; the workflow increments the latest `vMAJOR.MINOR.PATCH` tag, runs the tests, builds the app, and publishes the archive. The first patch release is `v0.0.1`. Automatic in-app updates are intentionally not included.

## Next Milestones

1. Add recent entries using `/v2/entries`.
2. Add SwiftUI UI tests and broader state-transition coverage.
3. Add an app icon, universal build, Developer ID signing, and notarization.
