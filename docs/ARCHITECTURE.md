# Architecture

Codex Control Center is a native Swift application composed of a menu bar host, a reusable core library, and a WidgetKit extension. It has no third-party package dependencies.

## Components

### Core (`Sources/CodexControlCenter`)

- `UsageProvider`: normalized provider boundary for quota sources
- `CodexProvider`: starts `codex app-server --stdio` and requests rate-limit metadata
- `CodexResponseParser`: converts the app-server response into provider-neutral models
- `CodexTaskUsageReader`: reads local Codex task/session metadata and aggregates token usage
- `HistoryStore`: appends quota-only JSONL history and creates day/cycle summaries
- `WidgetSnapshotStore`: writes the compact snapshot consumed by WidgetKit
- `Models`: quota, health, history, and task usage calculations

Future Claude, Cursor, or Gemini support should be implemented behind `UsageProvider`; shared UI and history code should not depend on a provider-specific response format.

### Menu bar app (`Sources/CodexControlCenterApp`)

- `AppController`: owns the status item, system menu, refresh cycle, history, widget updates, and alerts
- `DashboardModel`: observable UI state
- `ControlCenterView`: SwiftUI content embedded in the native menu
- `AlertManager`: low-quota notification and per-cycle deduplication

The app uses a tracked native `NSMenu`. macOS therefore dismisses it when focus moves elsewhere and prevents duplicate popovers from stacking.

### Widget extension (`WidgetExtension`)

The extension reads `widget-snapshot.json` from the host user's Application Support folder. It does not start Codex or query the state database itself. Widget families are small, medium, and large; tapping any widget activates the host app.

## Data flow

```text
local codex app-server ----> CodexProvider -----------+
                                                     |
~/.codex state/session files -> TaskUsageReader -----+--> DashboardModel
                                                     |        |
                                                     |        +--> native menu
                                                     |        +--> notifications
                                                     |        +--> history.jsonl
                                                     +-------> widget-snapshot.json
                                                                  |
                                                                  +--> WidgetKit extension
```

## Period calculations

- **Today** uses the user's local calendar day.
- **Current cycle** starts at `weekly reset time - window duration`; it is not a calendar week.
- **All time** includes every locally discoverable task record.
- Each task bar is `task tokens / total tokens in the selected period`.
- Task sorting is descending by tokens within the selected period.

## Security boundaries

- Authentication remains owned by the locally installed Codex executable.
- The app does not parse or persist credentials.
- Live quota fetching happens only in the host application.
- Widget filesystem access is limited to the application's support directory.
- New providers must document credentials, network behavior, and local files before integration.
