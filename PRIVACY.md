# Privacy

Codex Control Center is local-first and has no analytics SDK, advertising SDK, telemetry endpoint, account system, or cloud backend.

## Data read

- Quota metadata returned by the already authenticated local `codex app-server`, including usage percentages, reset times, plan name, and available reset credits
- Codex's local state database and session metadata under `~/.codex`, used to aggregate task title, working directory, token count, and timestamps

The app does not request or persist browser cookies, OAuth tokens, API keys, prompt bodies, assistant replies, or attachment contents.

Task titles originate from local Codex task metadata. A shortened title and aggregate token counts may be copied into the widget snapshot so the WidgetKit extension can display them on the desktop.

## Data written

The app writes only to:

```text
~/Library/Application Support/CodexControlCenter/
```

- `history.jsonl`: quota snapshots and reset metadata; no task or conversation content
- `widget-snapshot.json`: current quota data plus shortened task titles and aggregate token counts required by the desktop widget

Notification deduplication and refresh preferences are stored in macOS user defaults.

## Network access

The application itself does not send usage data to a project-operated server. It communicates with the local Codex executable; that executable remains governed by its own product settings and privacy terms.

## Removing local data

Quit the app, then delete the `CodexControlCenter` folder shown above. Removing the application alone does not automatically delete this history.
