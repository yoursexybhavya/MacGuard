# Contributing to Project MACGUARD

Thank you for contributing to Project MACGUARD. This is a private, security-first macOS application.

---

## 1. Confidentiality & Private Repository Rules

* This repository is strictly **PRIVATE**.
* Never push code, branches, tags, or issues to public repositories or paste proprietary logic into public pastes.
* Never commit personal credentials, API keys, sensitive paths, or personal document contents.

---

## 2. Engineering Standards

### Swift 6 Guidelines (`write-swift`)
1. **Value Types First**: Default to `struct` and `enum`. Use `final class` only when reference identity or lifecycle dictates it.
2. **Approachable Concurrency**:
   - UI views and view models are `@MainActor`-isolated.
   - Long-running disk scans and cryptographic hashing must run in background threads (`DispatchQueue.global(qos: .userInitiated)` or `@concurrent`).
   - Shared singletons must conform to `Sendable`.
3. **Apple Design Foundations (`apple-design`)**:
   - Use fluid springs with critically damped responses (`damping: 1.0`, `response: 0.35`).
   - Support dark mode natively with standard Apple semantic colors (`Color(nsColor: .windowBackgroundColor)`, `.secondary`).
   - All interactive controls must respond immediately on pointer-down.

---

## 3. Security Boundary Rules

* **Never Bypass `SecurityGuard`**: Every filesystem operation touching user directories must pass through `SecurityGuard.validatePath()`.
* **Zero Direct Permanent Deletions**: Deletions must use `SecurityGuard.safelyMoveToTrash()`.
* **Always Record Operations**: Relocations and cleanups must be logged to `RollbackLedger`.

---

## 4. Pre-Commit Checklist

Before committing or submitting a pull request, run the verification test suite:

```bash
cd MacGuard
swift test
```

Ensure all tests pass with zero failures and that `swift build -c release` finishes without compiler warnings.
