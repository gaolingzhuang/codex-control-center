# Releasing

## 1. Prepare the version

1. Choose a semantic version.
2. Update `VERSION`.
3. Update `MARKETING_VERSION` for both the app and widget in `CodexControlCenter.xcodeproj/project.pbxproj`.
4. Increment `CURRENT_PROJECT_VERSION` for both targets.
5. Move relevant entries from **Unreleased** into a dated section in `CHANGELOG.md`.

Check that the version is consistent:

```bash
./scripts/check-version.sh
```

## 2. Verify

```bash
./scripts/check.sh
./scripts/build-app.sh
codesign --verify --deep --strict "outputs/Codex Control Center.app"
```

Install and manually verify:

- menu opens once and dismisses when focus changes
- manual refresh succeeds
- Today / Current cycle / All time task lists are correct
- low-usage group expands and collapses
- small, medium, and large widgets render current data
- widget tap activates the same host app
- notification permission and low-quota behavior remain correct

## 3. Publish

1. Commit the release changes.
2. Tag the commit as `v<VERSION>`.
3. Create a GitHub Release using the matching changelog section.
4. Attach `outputs/Codex-Control-Center-macOS.zip`.
5. State clearly whether the archive is ad-hoc signed, Developer ID signed, and/or Apple-notarized.

The default build script produces an ad-hoc signed archive. Apple notarization requires a maintainer-controlled Developer ID certificate and credentials and is intentionally not automated in this public repository.
