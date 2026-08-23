# Security

Please do not report security vulnerabilities in a public issue.

Use [GitHub private vulnerability reporting](https://github.com/navopw/clockodo-menubar/security/advisories/new)
when it is available. If it is not enabled, contact [navopw](https://github.com/navopw)
through GitHub with enough detail to reproduce the issue.

Include the affected version or commit, macOS version, reproduction steps, and
the potential impact. Do not include Clockodo API keys or other personal data.

## Credential handling

Clockodo credentials are stored in the macOS Keychain. The app sends them
directly to `https://my.clockodo.com/api` and does not use a project server,
analytics service, or remote credential store. Please still treat API keys as
secrets and revoke any key that may have been exposed.

The `main` branch is the only currently supported version.
