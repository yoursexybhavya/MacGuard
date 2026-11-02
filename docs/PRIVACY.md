# Privacy

MacGuard is local-first. It has no account, no cloud sync, no analytics, no crash upload, and no network client entitlement.

## Data that stays on the Mac

| Data | Location | Purpose |
| --- | --- | --- |
| Preferences | `~/Library/Application Support/MacGuard/settings.json` | Appearance, safety, thresholds, schedule, exclusions |
| Operation history | `~/Library/Application Support/MacGuard/history.json` | Local audit trail, restore and undo |
| Organization rules | `~/Library/Application Support/MacGuard/rules.json` | User-defined file rules |
| Vault manifest | `~/Library/Application Support/MacGuard/Vault/manifest.json` | Original paths and sizes of vaulted files |
| Vault files | `~/Library/Application Support/MacGuard/Vault/<operation-id>/` | Cleaned files awaiting restore or purge |
| Logs | macOS unified logging | Diagnostic messages; no file paths are intentionally logged |

## Data that is never collected

- File contents (except when computing a local SHA-256 for duplicate detection)
- File names or paths sent to a server
- Account identifiers
- Device identifiers
- Usage analytics or telemetry
- Crash reports
- Location data
- Keychain contents

## Network access

The app target declares `com.apple.security.network.client = false` and `com.apple.security.network.server = false`. There is no URLSession, no web view, no remote configuration, and no update check. Notifications are local `UNUserNotificationCenter` notifications.

## File access

MacGuard reads the user's home directory to scan caches, logs, downloads, and user-selected folders. It does not request Full Disk Access automatically. Some protected system locations may be unreadable without Full Disk Access; the app reports them as warnings instead of failing.

The App Sandbox is disabled because a system utility needs user-domain file access. This is a deliberate tradeoff and is documented in the README and SECURITY.md. Hardened runtime is enabled.

## Permissions

- **Notifications:** requested only when the user enables notifications or when a scan completes with notifications enabled.
- **Launch at login:** registered only when the user toggles it on, using `SMAppService`.
- **Full Disk Access:** never requested programmatically; the user can grant it in System Settings if they want complete coverage.

## Removing data

Settings → Privacy provides:

- **Clear history** — removes the local audit trail.
- **Clear vault** — permanently removes restorable files.
- **Reset all MacGuard data** — removes settings, history, rules, and the vault.

Files outside the vault are never touched by these controls.

## Security contact

This is a private repository. For security issues, contact the repository owner through the private channel used to share this project. Do not open a public issue.
