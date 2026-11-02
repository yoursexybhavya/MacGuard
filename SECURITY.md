# Security & Privacy Policy: Project MACGUARD

---

## 1. Security Architecture Principles

Because MacGuard manages personal user files, security and privacy strictly supersede convenience and automation.

### Ten Core Invariants
1. **Approval Gate Before Execution**: No file is ever deleted, trashed, or moved without explicit user confirmation via an approval dialog displaying exact source and destination paths.
2. **Reversibility as Default**: Deletions are mapped strictly to macOS Trash (`FileManager.default.trashItem(at:resultingItemURL:)`). Permanent unlinking (`unlink` / `rm -rf`) is architecturally prohibited in the codebase.
3. **Protected System Whitelist**: Hardcoded blacklists prohibit access to `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/etc`, `/private`, `/Volumes`, and sensitive user directories (`.ssh`, `.gnupg`, `Keychains`, `Accounts`).
4. **Path Traversal Defense**: All paths are checked for traversal patterns (`../`, `/..`) and verified using `.standardized.resolvingSymlinksInPath()`.
5. **No Arbitrary Shell Execution**: The AI engine has zero shell execution primitives. It cannot spawn `bash`, `zsh`, `sh`, or `posix_spawn`. Tool invocations are strongly typed Swift enum structures.
6. **Zero Cloud Telemetry**: 100% of reasoning, metadata extraction, and scanning operations run locally on your device.
7. **Collision-Safe Moves**: If a destination file exists during an organization operation, the organizer automatically appends a collision-free suffix (`(1)`) rather than overwriting existing data.
8. **Audit Trail Persistence**: Every operation records an immutable record in `RollbackLedger` with unique UUID, timestamp, original path, destination path, and reason.
9. **No Plaintext Credential Storage**: MacGuard never asks for, captures, or stores administrator passwords.
10. **TCC Permission Compliance**: File access relies exclusively on standard Apple Transparency, Consent, and Control (TCC) frameworks.

---

## 2. Threat Modeling & Mitigations

| Threat | Attack Vector | MacGuard Mitigation |
| :--- | :--- | :--- |
| **Path Traversal** | AI or user supplies `../../System/Library` | Blocked by `SecurityGuard.validatePath()`. Rejects any path with `..` or leading out of permitted user bounds. |
| **Symlink Exploit** | Symlink pointing from `~/Downloads/link` to `/etc` | `resolvingSymlinksInPath()` evaluates the true target before permission checking. Target matches `/etc` and is blocked. |
| **System Deletion** | Model hallucinates cleanup of `/usr/local` | Hardcoded system prefix check throws `SecurityError.protectedPath`. |
| **Credential Thefts** | Model attempts to inspect `~/.ssh/id_rsa` | Explicit check in `SecurityGuard` blocks access to sensitive credential components (`.ssh`, `.gnupg`, `Keychains`). |
| **Accidental Overwrite** | File with same name exists at destination | `FileOrganizer` checks `FileManager.fileExists` and increments counter (`name (1).ext`) before moving. |
| **Irreversible Loss** | User regrets a cleanup operation | All deletions use macOS Trash and can be restored with one click from the `ApprovalCenterView` Rollback Ledger. |

---

## 3. Reporting a Security Issue

If you discover a security vulnerability in MacGuard, please report it privately:
* **Repository**: Private GitHub repository.
* **Response SLA**: Security issues are triaged within 24 hours.
