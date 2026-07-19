# Contributing

Thanks for helping improve Codex Control Center.

## Before starting

- Search existing issues and pull requests.
- For a substantial feature or UI redesign, open an issue first so behavior and scope can be agreed on.
- Keep the app local-first. New network services, telemetry, credential access, or broader filesystem access require explicit design and privacy review.
- Avoid copying implementation code or assets from reference projects unless their license, attribution, and compatibility have been verified.

## Development setup

Requirements: macOS 14+, Xcode 16+, and a local Codex installation for live testing.

```bash
./scripts/check.sh
./scripts/build-app.sh
```

Unit tests must not depend on a real account or modify the user's Codex data. Add focused tests for parser, storage, calculation, or title-normalization changes.

## Pull requests

- Keep each pull request focused.
- Describe user-visible behavior and privacy implications.
- Include before/after screenshots for menu or widget changes.
- Confirm `./scripts/check.sh` passes.
- Update `CHANGELOG.md` under **Unreleased** for user-visible changes.

By contributing, you agree that your contribution is licensed under this repository's MIT License.
