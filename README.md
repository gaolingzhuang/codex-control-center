# Codex Control Center for macOS

[简体中文](README.zh-CN.md)

An unofficial, local-first macOS menu bar app and WidgetKit desktop widget for monitoring Codex quota and task token usage.

## Features

- Reads live quota through the local Codex `app-server` (`account/rateLimits/read`)
- Shows weekly quota, reset time, reset credits, and pace-aware status
- Ranks task token usage by Today, Current quota cycle, or All time
- Calculates each progress bar as `task tokens / total tokens in the selected period`
- Collapses very small tasks into an expandable “Other low-usage tasks” group
- Supports small, medium, and large native macOS desktop widgets
- Refreshes automatically every 1, 5, 10, or 15 minutes
- Sends one macOS notification per quota cycle when remaining quota reaches 20% or less
- Stores local JSONL quota history
- Uses a provider abstraction ready for Claude, Cursor, Gemini, and other local tools

No analytics, cloud backend, browser cookies, OAuth tokens, or API keys are collected by this app.

## Requirements

- macOS 14 or later
- Codex CLI installed and signed in, or the ChatGPT/Codex desktop app installed and signed in
- Xcode 16 or later when building from source

## Install a release build

1. Download `Codex-Control-Center-macOS.zip` from the repository's Releases page.
2. Unzip it and move **Codex Control Center.app** to `/Applications`.
3. Open the app. It runs in the menu bar and does not add a Dock icon.

Release archives produced by this repository are ad-hoc signed, not Apple-notarized. On first launch, macOS may require you to Control-click the app, choose **Open**, and confirm. Only download builds from a release you trust.

To add a desktop widget, Control-click an empty area of the desktop, choose **Edit Widgets**, search for **Codex**, then select a size.

## Build from source

```bash
git clone <your-repository-url>
cd codex-control-center
./scripts/check.sh
./scripts/build-app.sh
open "outputs/Codex Control Center.app"
```

The build script produces:

- `outputs/Codex Control Center.app`
- `outputs/Codex-Control-Center-macOS.zip`

To install the local build into `/Applications`:

```bash
./scripts/install.sh
```

## How it works

The app launches the already authenticated local `codex app-server --stdio` process and requests rate-limit metadata. Task usage is aggregated locally from Codex state and session files. The selected period determines both the denominator used by progress bars and the ranking.

Local data is written to:

```text
~/Library/Application Support/CodexControlCenter/
```

See [PRIVACY.md](PRIVACY.md) for the exact data read and written, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the implementation layout.

## Development

```bash
./scripts/check.sh
```

This runs the Swift test suite and a no-signing Xcode Release build. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request and [docs/RELEASING.md](docs/RELEASING.md) before publishing a release.

## License and trademark notice

Project source code is licensed under the [MIT License](LICENSE). This is an independent community project and is not affiliated with, sponsored by, or endorsed by OpenAI. OpenAI, ChatGPT, Codex, and related marks belong to their respective owner and are not granted under the MIT License. See [NOTICE.md](NOTICE.md).
