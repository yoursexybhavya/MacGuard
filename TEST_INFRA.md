# MacGuard Test Infrastructure Specification (TEST_INFRA)

## 1. Test Philosophy: Opaque-Box & Requirement-Driven

The MacGuard test infrastructure is designed around the principles of **opaque-box, requirement-driven verification**:

1. **Behavioral Correctness over Implementation Details**:
   - Tests assert observable system contracts, public API behaviors, filesystem states, and security invariants rather than private internal implementation details.
   - All assertions are derived directly from the authoritative specifications in `ORIGINAL_REQUEST.md` and `PROJECT.md`.
2. **Deterministic & Isolated Execution**:
   - Tests run in self-contained sandboxes using unique temporary directories under `FileManager.default.temporaryDirectory`.
   - Each test sets up its own fixtures, executes its scenarios independently of execution order, and ensures cleanup upon completion.
3. **Safety & Zero Destructive Mutation**:
   - Destructive operations are strictly barred from touching real user directories or protected macOS paths.
   - All trashing operations in test harnesses use isolated sandboxes, verify destination URLs, and validate full reversibility through `RollbackLedger`.
4. **Strict Conformance to Swift Testing**:
   - Written using modern Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), integrating seamlessly with Swift Package Manager (`swift test`).
   - Full concurrency safety (`Sendable` compliance and approachable concurrency) without test flakiness or race conditions.

---

## 2. Feature Inventory Mapping Across Tiers 1–4

MacGuard's 20 core features (F1 through F20) are comprehensively covered across four progressive testing tiers:

| Feature ID | Feature Description | Primary Tier | Secondary Tiers | Validation Target |
|------------|---------------------|--------------|-----------------|-------------------|
| **F1** | Storage Category Retention | Tier 1 | Tier 3, Tier 4 | 12-category classification, item retention, and breakdown grouping |
| **F2** | Universal Safe Trashing | Tier 1 | Tier 2, Tier 3, Tier 4 | `SecurityGuard.safelyMoveToTrash`, non-destructive trashing, resulting URL capture |
| **F3** | Zero Permanent Deletion | Tier 1 | Tier 2, Tier 4 | Complete elimination of direct unrecoverable file deletions; empty folder pruning |
| **F4** | Enhanced RollbackLedger | Tier 1 | Tier 2, Tier 3, Tier 4 | Operation logging, action types, reversibility state, destination tracking, and rollback |
| **F5** | Storage Category Cards Interactivity | Tier 1 | Tier 4 | All 12 categories enumerated with system icons, labels, and drill-down metadata |
| **F6** | Dynamic Segmented Storage Bar | Tier 1 | Tier 2 | Capacity proportions, usage percentage, free space, and formatted byte representations |
| **F7** | Category Drill-Down View | Tier 1 | Tier 3, Tier 4 | Category file filtering, size/name/date sorting, search query matching |
| **F8** | Largest Files Action Controls | Tier 1 | Tier 4 | Top file discovery, size sorting, metadata attributes, and actionable URLs |
| **F9** | App-Wide Quick Look Integration | Tier 1 | Tier 4 | Preview URL contracts and file existence verification |
| **F10** | Centralized NavigationCoordinator | Tier 1 | Tier 3 | Observable navigation sections, parameterized routing contracts |
| **F11** | Dynamic Shell Status & Hardware Bar | Tier 1 | — | Metal device detection via `MTLCopyAllDevices()`, physical memory, and CPU metrics |
| **F12** | Dashboard Live Gauge & Action Context | Tier 1 | Tier 3 | Live disk usage calculation, gauge metrics, and recent action context integration |
| **F13** | Duplicate Finder Folder Picker & Keeper | Tier 1 | Tier 2, Tier 3, Tier 4 | Min-size filtering, duplicate discovery, and interactive keeper switching logic |
| **F14** | Organizer Folder Consolidation & Checkboxes | Tier 1 | Tier 3, Tier 4 | Redundant sibling folder detection (`planFolderConsolidation`), merge execution |
| **F15** | Assistant Persistent State & Interactive Chips | Tier 1 | Tier 4 | Conversational routing, category chip metadata, and query dispatch |
| **F16** | Cleanup Center Select-All & Drill-Down | Tier 1 | Tier 2, Tier 3, Tier 4 | Discovery of cache/log targets, safety tier classification, and selection state toggling |
| **F17** | Approvals & History Rich View & Batch Undo | Tier 1 | Tier 2, Tier 3, Tier 4 | OperationRecord file sizes, search/filter by action type, rollback status transitions |
| **F18** | Settings Real Ollama & Background Persistence | Tier 1 | — | Background monitoring preferences, hardware specs retrieval |
| **F19** | Comprehensive Automated Test Suite | Tier 1 | Tiers 2, 3, 4 | Seamless execution of all suites via `swift test`, 0 failures, preserving all 20 baseline tests |
| **F20** | Adversarial Coverage Hardening | Tier 2 | Tier 1, Tier 3 | Boundary validation, path traversal attacks, system protection, size collisions |

---

## 3. Tier Definitions & Test Architectures

### Tier 1: Feature Coverage (Unit & Subsystem Contracts)
Focuses on individual feature behavior, input-output contracts, and domain models.
- **Coverage**:
  - Verification of all 12 storage categories (`FileCategory.allCases`): Installers, Compressed, Documents, Audio & Video, Design & 3D, AI Skills, Academics, Images, Code, Caches, Junk, Other.
  - Storage bar calculation invariants: total capacity, used capacity, available capacity, and category proportions.
  - Largest files discovery and sorting by descending size.
  - Duplicate detection with folder selection and keeper switching logic.
  - Sibling folder consolidation planning and proposal generation.
  - Cleanup target discovery, safety tier badges (`.safe`, `.reviewRecommended`, `.highRisk`, `.protected`), and selection state toggling.
  - Approvals & History record attributes, including byte-accurate `fileSize` and `isReversible` status.
  - Hardware monitor live queries: Metal GPU query (`MTLCopyAllDevices()`), host memory and active core metrics.
  - Safe trashing and non-destructive folder handling.

### Tier 2: Boundary & Corner Cases (Robustness & Adversarial Hardening)
Validates system resilience against pathological inputs, edge conditions, and adversarial maneuvers.
- **Coverage**:
  - Empty categories with zero files and zero bytes.
  - Scanning completely empty directories.
  - Cryptographic duplicate collisions: files with identical byte sizes but different content and SHA-256 hashes.
  - Rollback failure modes: missing destination files, already rolled back records, and invalid record IDs.
  - Path traversal exploits: `../`, `/..`, and relative traversal injection.
  - Protection of macOS system directories: `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private/etc`.
  - Protection of sensitive user locations: `.ssh`, `.gnupg`, `Keychains`, `Accounts`, `IdentityServices`, `.git`.
  - Single-file candidates (ensuring groups with count < 2 are not reported as duplicates).

### Tier 3: Cross-Feature Combinations & State Transitions
Verifies data flow and state consistency across multiple interconnected features.
- **Coverage**:
  - **Storage Scan & Trash Flow**: Category drill-down discovery -> Safe trashing of item via `SecurityGuard` -> Verify `RollbackLedger` persistence -> Rollback restoration to original location.
  - **Duplicate Resolution Flow**: Duplicate discovery -> Interactive keeper selection -> Trashing non-keeper duplicate -> Verify rollback record -> Reversal to original directory.
  - **Folder Consolidation Flow**: Sibling folder detection -> Merge proposal execution -> Reversible file moves logged in ledger -> Data integrity preserved.
  - **Cleanup Execution Flow**: Candidate discovery -> Safety tier filtering -> Batch execution to Trash -> Ledger audit -> Reversal.

### Tier 4: Real-World Application End-to-End Scenarios
Simulates realistic end-to-end user workflows in a sandboxed APFS hierarchy.
- **Coverage**:
  - Setup of complex user workspace with diverse files (installers, documents, archives, code, caches, identical duplicates, sibling folders).
  - Stage 1: Full system scan and multi-category breakdown.
  - Stage 2: Duplicate detection with keeper switching and safe trashing.
  - Stage 3: Sibling folder consolidation execution.
  - Stage 4: Cache target cleanup execution.
  - Stage 5: Approvals & History comprehensive audit.
  - Stage 6: Rollback and restoration verification.

---

## 4. Minimum Coverage Thresholds Across Tiers 1–4

| Tier | Category | Minimum Target | Verification Metric |
|------|----------|----------------|---------------------|
| **Tier 1** | Feature Coverage | 100% of Features F1–F20 mapped; ≥ 10 test functions | All 12 categories, hardware, storage bar, duplicates, cleanup, history verified |
| **Tier 2** | Boundary & Corner Cases | ≥ 6 test functions | Zero crashes, proper error throws on all protected/invalid paths and collisions |
| **Tier 3** | Cross-Feature Integration | ≥ 3 integration flows | Complete multi-step state transitions with rollback verified |
| **Tier 4** | Real-World End-to-End | ≥ 1 comprehensive lifecycle test | Full multi-stage lifecycle from initial scan to history audit and rollback |
| **Overall**| Entire Test Suite | 100% pass rate; ≥ 40 total tests (20 baseline + 20 new) | `swift test` exits with code 0 in `MacGuard` |

---

## 5. Execution Commands

To execute the entire test suite including baseline and new tests:
```bash
cd MacGuard && swift test
```

To run only the new interactive and storage test suite:
```bash
cd MacGuard && swift test --filter InteractiveAndStorageTests
```

To run with verbose output:
```bash
cd MacGuard && swift test -v
```
