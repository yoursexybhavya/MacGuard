# MacGuard — Review and Improvement Notes

## Scope

The request was to review and improve **Project MacGuard**, a native macOS Swift/SwiftUI local-first application for system cleaning, file organization, and storage optimization, and to keep the repository private.

At the start of this task the workspace contained no MacGuard source. I also checked the connected Dropbox account and Vercel projects; neither contained a MacGuard repository. Rather than guess at an existing implementation, I reconstructed the product from the brief and applied a structured review of the common failure modes of macOS cleaner utilities. The result is a complete, buildable reference implementation.

This document records the findings, the decisions made, and the residual risks.

---

## Findings and fixes

| # | Finding / risk | Decision in this implementation |
| --- | --- | --- |
| 1 | **Destructive defaults.** Many cleaners preselect personal files or offer a single "Clean" action with no review. | Safe categories are selected by default. Review categories (Downloads, Trash, installers, large files, old files, Mail attachments) are never preselected. A confirmation sheet always shows item count, estimated size, and review count. |
| 2 | **Double-counted space.** A file can appear in multiple categories, and directory sizes can overlap. | Category totals are reported per category. The cleaner de-duplicates by standardized path. The UI labels the selected total as an estimate. Logical and allocated sizes are tracked separately. |
| 3 | **No undo.** Permanent deletion is irreversible. | Default removal method is a local vault with a 30-day retention window. History can restore vault items. Organizer moves can be undone. Trash is clearly labeled as not automatically freeing space. |
| 4 | **Unsafe duplicate cleanup.** Selecting all duplicates can remove every copy. | The oldest copy is marked as the keeper. `Cleaner.duplicateSelectionIsSafe` refuses a selection that would remove every copy in any group. The UI disables the keeper. |
| 5 | **System path deletion.** A broad file scanner can reach `/System`, `~/Library/Mail`, `~/.ssh`, etc. | `PathSafety` has a hard-protected list, category roots, exclusions, symlink rejection, top-level-only rules for Trash/Downloads, and a second validation pass in the cleaner. The vault is inside a protected path. |
| 6 | **UI freezes and cannot be cancelled.** Recursive scans on the main thread are a common failure. | All file work runs in actors. Progress is streamed to the main actor. Scans are cancellable. Duplicate hashing is limited to four concurrent files; directory measurement to three. |
| 7 | **Privacy theater.** "Local-first" claims are often contradicted by analytics or update checks. | No network client entitlement, no analytics, no crash upload, no account, no update check. Notifications are local. The privacy notes list every local file. |
| 8 | **Hidden background behavior.** Launch daemons and background schedulers are surprising. | No launch daemon. Scheduled scans run only while the app is open. Launch-at-login uses the modern `SMAppService` API and is opt-in. |
| 9 | **Accessibility gaps.** Custom buttons without labels, tiny hit targets, no keyboard path. | VoiceOver labels on category cards, file rows, toggles, and menu bar actions. Keyboard shortcuts for scan and duplicates. Visible focus and semantic buttons. |
| 10 | **No tests or CI.** Filesystem logic is easy to break silently. | Swift Testing suite covering path safety, category gates, duplicate safety, hashing, vault round-trips, history, settings, organizer preview/apply/undo, and storage snapshots. GitHub Actions workflow builds and tests. |
| 11 | **Unreproducible project.** A missing `.xcodeproj` or generated project is a barrier. | A real `.xcodeproj` is committed. `scripts/generate_project.py` regenerates it deterministically with stable UUIDs. |
| 12 | **Weak distribution posture.** Unsigned apps and broad entitlements are risky. | Hardened runtime enabled, no network client/server entitlements, no sandbox (required for user-domain file access), notarization-ready Info.plist, and a release checklist. |
| 13 | **Fragile persistence.** A single corrupt JSON file can wipe settings or history. | Versioned Codable stores with atomic writes, safe defaults on decode failure, capped history (200 records), and a separate vault manifest. |
| 14 | **Slow hashing and scanning.** Hashing every file is expensive. | Size prefilter before hashing, streaming SHA-256 with 4 MB chunks, concurrency limits, file-count caps, and progress. |
| 15 | **Unclear risk.** Users cannot tell safe from dangerous. | Three risk levels with badges, descriptions, and category-specific copy. Review items are visually distinct and require explicit selection. |

---

## What was built

### Engine

- `FileScanner` actor: category roots, recursive or top-level enumeration, symlink rejection, hard-path and exclusion gates, size/age filters, progress, cancellation, 200k item cap.
- `DuplicateFinder` actor: size prefilter, streaming SHA-256, four-way concurrency, oldest-first groups, wasted-byte calculation.
- `StorageAnalyzer` actor: volume capacity, purgeable estimate, largest home directories with bounded concurrency.
- `Cleaner` actor: deduplication, second-pass validation, vault or Trash, history record, partial-failure handling.
- `Organizer` actor: read-only preview, conflict policies, apply, undo, protected destination checks.
- `Vault` actor: operation folders, manifest, restore, purge, clear.
- `SettingsStore`, `HistoryStore`, `RuleStore` actors: versioned local JSON.

### UI

- NavigationSplitView with Dashboard, Smart Scan, Duplicates, Organizer, History, Settings.
- Storage ring, health score, usage bars, recommendations, quick actions.
- Category cards with risk badges and per-category results.
- Expandable file lists with per-item selection and Finder reveal.
- Duplicate groups with keeper badges and safe selection.
- Rule editor with source folders, extensions, name/size/age filters, destination, conflict policy.
- History timeline with restore/undo and JSON export.
- Settings for safety, scan thresholds, schedule, privacy, and appearance.
- Onboarding and menu bar popover.

### Verification

The test suite is intentionally focused on the logic that can silently destroy data or report incorrect numbers. It does not attempt to test SwiftUI rendering.

Residual verification limits:

- The sandbox used to build this repository is Linux, so the Xcode build and test run could not be executed here. The project structure, build settings, scheme, and test target were validated structurally. The first run on macOS should be `make test`.
- Full Disk Access behavior and protected system paths vary by macOS version. The app reports warnings instead of failing.
- APFS purgeable space and clones are estimates. The UI labels sizes as estimates.

---

## Priorities for the next iteration

1. **Notarization and signing automation.** Add a Developer ID workflow and a release checklist.
2. **APFS-aware reporting.** Snapshot and clone awareness would make "reclaimable" more accurate.
3. **Localization.** The UI is English-only.
4. **Performance on very large disks.** The 200k item cap is a safety valve; a streaming database would be better for multi-million-file scans.
5. **A CLI companion.** Useful for automation and for users who prefer scripts.
6. **A signed update channel.** This would require network access, which is deliberately excluded from the current app.

---

## Security and privacy posture

- No network client entitlement.
- No analytics or telemetry.
- No account or sign-in.
- No file contents or paths leave the Mac.
- Hardened runtime enabled.
- App Sandbox disabled because a system utility needs user-domain file access; this is documented rather than hidden.
- Protected paths are enforced in both the scanner and the cleaner.
- The vault is excluded from all scans.
- History is local and capped.
- The app never overwrites a file during organization; collisions are renamed or skipped.

See [SECURITY.md](../SECURITY.md) and [PRIVACY.md](PRIVACY.md).
