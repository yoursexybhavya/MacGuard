# Technical Architecture Specification: Project MACGUARD

---

## 1. Architectural Philosophy: The Hybrid Model

MacGuard operates under a strict **Hybrid Architecture**:

```
┌──────────────────────────────────────────────────────────┐
│              User Input (UI or Natural Language)         │
└────────────────────────────┬─────────────────────────────┘
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
   Deterministic Engine                AI Decision Layer
 (High-Speed Swift Native)          (Local Qwen 2.5 3B Metal)
 - APFS Metadata Crawl               - Intent Parsing
 - SHA-256 Crypto Hashing            - Folder Structure Design
 - Trash Integration                 - Ambiguity Resolution
 - Rollback Ledger Storage           - Transparent Reasoning
            │                                 │
            └────────────────┬────────────────┘
                             │
                             ▼
                Security & Permission Guard
                 - System Path Blacklist
                 - Path Traversal Block
                 - Mandatory User Approval
                             │
                             ▼
                 Atomic Filesystem Execution
```

### Why a Hybrid Model?
1. **Determinism for File Integrity**: Calculating file sizes, finding duplicates with cryptographic hashes, querying APFS volume allocations, and invoking `FileManager.trashItem` must be 100% bug-free, deterministic, and instant. Delegating basic filesystem arithmetic or shell syntax to an LLM introduces hallucination risk.
2. **LLM for Discretionary Judgment**: The local LLM excels where rigid regex rules fail—understanding natural language instructions, clustering semantically related files, generating clear explanations, and suggesting contextual reorganization trees.

---

## 2. Component Design & Layering

### 2.1 Core AI Layer (`MacGuard.Core.AI`)
* **`OllamaService`**: Communicates with the local Ollama instance over HTTP loopback (`http://127.0.0.1:11434`). Uses standard `URLSession` with structured JSON format flags.
* **`MacGuardAIEngine`**: Enforces system prompt constraints, formats JSON payloads into Swift types (`MacGuardResponse`), and routes tool calls to the system utilities.
* **Fallback Heuristic Parser**: If the Ollama daemon is offline or restarting, the query is seamlessly parsed by a local deterministic keyword router, guaranteeing the user experience never breaks.

### 2.2 Security & Sandbox Layer (`MacGuard.Core.Security`)
* **`SecurityGuard`**:
  - Implements the system blacklist:
    ```swift
    let protectedSystemPrefixes = [
        "/System", "/Library", "/usr", "/bin", "/sbin",
        "/etc", "/private/etc", "/private/var/db",
        "/private/var/root", "/private/var/audit",
        "/Volumes", "/Network"
    ]
    ```
  - Resolves symlinks using `.resolvingSymlinksInPath()`.
  - Blocks path traversal sequences (`..`).
  - Guards sensitive user directories (`.ssh`, `.gnupg`, `Keychains`, `Accounts`).

### 2.3 Scanner & Storage Layer (`MacGuard.Core.Scanner`)
* **`SystemScanner`**: Crawls user directories using `FileManager.DirectoryEnumerator` with specific resource keys (`.fileSizeKey`, `.contentModificationDateKey`, `.isDirectoryKey`).
* **Multi-Pass Duplicate Detection**:
  - Pass 1: Group files by exact byte size.
  - Pass 2: Stream 64 KB chunked SHA-256 hashes via Apple `CryptoKit.SHA256` for size collisions.

### 2.4 File Organizer (`MacGuard.Core.Organizer`)
* Proposes categorized directory hierarchies:
  - `.dmg`, `.pkg` → `Installers`
  - `.zip`, `.tar.gz` → `Archives`
  - `.pdf`, `.docx`, `.pages` → `Documents`
  - `.png`, `.jpg`, `.heic` → `Images`
  - `.mov`, `.mp4` → `Media`
  - `.swift`, `.py`, `.json` → `Code`
* Enforces **Zero Overwrite**: Inspects destination paths and automatically increments numeric suffixes (`file (1).ext`) if collisions exist.

### 2.5 Cleaning & History Layer (`MacGuard.Core.Cleaner` & `History`)
* **`CleanupEngine`**: Scans user-level caches (e.g. Xcode `DerivedData`, crash logs, old download installers).
* **`RollbackLedger`**: Stores an append-only JSON audit log in `~/Library/Application Support/MacGuard/operations_ledger.json`. Rollbacks safely invert operations (moves items back to their exact original location).

---

## 3. Concurrency & Memory Model

* **Swift 6 Data-Race Safety**: All shared engine singletons (`SecurityGuard`, `SystemScanner`, `RollbackLedger`, `MacGuardAIEngine`) are marked `final class ... : Sendable`.
* **Approachable Concurrency**: Concurrency is kept structured (`Task`, `async/await`, `DispatchQueue.global`).
* **MainActor View Isolation**: All SwiftUI views and observable state mutations reside on the `@MainActor`.
* **Memory Optimization**: The background monitoring daemon and idle app consume < 150 MB. Ollama model weights dynamically unload when idle.
