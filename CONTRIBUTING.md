# Contributing

Contributions are welcome. Open an issue before starting a large change so the
approach can be discussed first.

## Development setup

Requirements:

- macOS 13 or newer
- Xcode 16 or newer, including a Swift 6 toolchain
- A Clockodo account is only needed for manual API testing

Clone the repository, then run the checks used by CI:

```sh
swift test
swift build
```

To build and open the local menu bar app:

```sh
./scripts/build-app.sh
open "dist/Clockodo Menubar.app"
```

The local app is ad-hoc signed and is not a distributable, notarized build.

## Changes

- Keep changes focused and follow the existing Swift style.
- Add or update tests for API encoding, decoding, and state behavior.
- Do not include Clockodo credentials, API keys, customer data, or other secrets in commits, logs, screenshots, or issues.
- Update the README when user-facing behavior, requirements, or release steps change.
- Confirm `swift test` passes before opening a pull request.

Pull requests should explain the user-visible result and include any relevant
limitations or manual testing steps.
