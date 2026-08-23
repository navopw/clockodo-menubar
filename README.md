# Clockodo Menubar

[![CI](https://github.com/navopw/clockodo-menubar/actions/workflows/ci.yml/badge.svg)](https://github.com/navopw/clockodo-menubar/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> A small, native macOS menu bar client for the Clockodo stop clock.

Start and stop timers, choose a customer, project, and service, and see your
running time without opening the Clockodo web app.

## Features

- Store the Clockodo email and API key in the macOS Keychain.
- Load active customers, projects, and services from the current Clockodo API.
- Start and stop the current timer with an optional note.
- Show live elapsed time in the menu bar.
- Show today's tracked total.
- Start the last valid timer setup with one click.
- Refresh the running timer approximately once per minute and today's total every five minutes.
- Offer retry and clear connection states for offline, permission, and rate-limit errors.
- Optionally start automatically at login.

## Requirements

- macOS 13 or newer
- Xcode 16 or newer, including a Swift 6 toolchain
- A Clockodo account with an API key

Prebuilt release archives currently target Apple Silicon. Intel Macs can run
the source build, but a universal release is not available yet.

## Installation

When a release is published, download its ZIP from [GitHub Releases](https://github.com/navopw/clockodo-menubar/releases),
unzip it, and open `Clockodo Menubar.app`. Until then, use [Build From Source](#build-from-source).

Release archives are currently ad-hoc signed. macOS may require you to approve
one in **System Settings > Privacy & Security**. Developer ID signing and
notarization are not configured yet.

## Setup

1. Create or copy a Clockodo API key for your account.
2. Open Clockodo Menubar and enter your Clockodo email address and API key.
3. The app validates the credentials before storing them in the macOS Keychain.
4. Choose a customer and service, optionally choose a project, and start the timer.

Clockodo Menubar is an unofficial client. It has no server component: API
requests go directly from the app to Clockodo. The app stores the email and API
key in the macOS Keychain and keeps the last customer, project, and service
selection in `UserDefaults`. It does not send data to analytics or a separate
service. See [SECURITY.md](SECURITY.md) for the credential-handling policy.

## Build From Source

```sh
git clone https://github.com/navopw/clockodo-menubar.git
cd clockodo-menubar

swift test
swift build
./scripts/build-app.sh
open "dist/Clockodo Menubar.app"
```

The build targets the architecture of the Mac or runner that builds it. The
local package is ad-hoc signed and is intended for development, not
distribution. No third-party Swift packages are required.

## API Notes

The client uses the current Clockodo routes:

- `GET /v2/clock` reads the running timer.
- `GET /v4/users/me` identifies the authenticated user and its timezone.
- `POST /v2/clock` starts a timer. Customer and service are required.
- `DELETE /v2/clock/{entry_id}` stops a timer.
- `GET /v3/customers`, `GET /v4/projects`, and `GET /v4/services` load choices.
- `GET /v2/entries` loads today's total, filtered to the authenticated user.

Every request includes the Clockodo email, API key, and the required external
application identifier. Requests use Clockodo's documented API and rate-limit
behavior; the app deliberately avoids per-second polling.

Read more in [PLAN.md](PLAN.md) and the [Clockodo API documentation](https://docs.clockodo.com/).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and contribution guidance.

The release workflow is manually triggered from GitHub Actions on `main`. It
increments the latest `vMAJOR.MINOR.PATCH` tag, runs the tests, builds the app,
and publishes a ZIP archive. Automatic in-app updates are intentionally not
included.

## Roadmap

- Add recent entries and links to the matching Clockodo pages.
- Add SwiftUI UI tests and broader state-transition coverage.
- Add an app icon, universal builds, Developer ID signing, and notarization.

## Disclaimer

This project is provided as-is, without warranty. Verify that timer actions
and tracked totals match Clockodo before relying on them for billing or payroll.
Clockodo is a trademark of its respective owner. This project is not affiliated
with or endorsed by Clockodo.

## License

[MIT](LICENSE)
