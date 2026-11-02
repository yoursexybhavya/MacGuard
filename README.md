# Project MACGUARD 🛡️
### Private, Local-First AI-Powered macOS Cleaning, File Organization & System Optimization

![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B%20(Apple%20Silicon)-blue)
![Architecture](https://img.shields.io/badge/Architecture-Swift%206%20%2F%20SwiftUI-orange)
![Local AI](https://img.shields.io/badge/AI%20Engine-Qwen%202.5%203B%20(Local%20Metal)-green)
![Privacy](https://img.shields.io/badge/Privacy-Zero%20Cloud%20Telemetry-purple)
![License](https://img.shields.io/badge/License-Private%20Proprietary-red)

---

## 1. Overview

**MACGUARD** is an intelligent, local-first macOS application engineered exclusively for MacBook maintenance, file organization, storage optimization, and duplicate elimination. Built with native Swift 6 and SwiftUI, it integrates a local open-weight language model (**Qwen 2.5 3B Instruct**) running directly on Apple Silicon Metal GPU acceleration.

### Core Philosophy
* **Zero Cloud Telemetry**: All reasoning and metadata analysis happen 100% on-device. No document contents or file paths ever leave your Mac.
* **Strict Approval Gates**: The AI is strictly prohibited from executing arbitrary shell commands or deleting/moving files without your explicit prior approval.
* **100% Reversible Operations**: Cleanup actions move files to the native macOS Trash rather than permanently unlinking them. All operations are logged to an audit ledger with one-click rollback.
* **Lightweight & Battery Efficient**: Under 150 MB app footprint, dynamic local model memory management, and zero continuous disk thrashing.

---

## 2. Key Modules & Features

```
┌────────────────────────────────────────────────────────────────────────┐
│                              MACGUARD UI                               │
├───────────────┬────────────────────────────┬───────────────────────────┤
│   Dashboard   │       AI Assistant         │     Storage Analyzer      │
│  Health Gauge │  Natural Language Actions  │  Visual Category Breakdown│
├───────────────┼────────────────────────────┼───────────────────────────┤
│File Organizer │       Cleanup Center       │    Approvals & History    │
│Smart Grouping │  Safety-Tiered Cache Clean │ One-Click Rollback Ledger │
└───────────────┴────────────────────────────┴───────────────────────────┘
```

### 🧠 Module A: AI Intelligence Engine
* Specialized system identity restricted to macOS storage management and file maintenance.
* Rejects non-maintenance requests (e.g. general conversational chatter) to maintain high precision.
* Outputs strongly-typed JSON tool calls dispatched to deterministic Swift system utilities.

### 🔍 Module B: APFS High-Speed System Scanner
* Recursive, non-blocking APFS metadata crawler (`FileManager` + `UniformTypeIdentifiers`).
* Multi-pass cryptographic duplicate detection:
  1. Size pre-filtering.
  2. Streaming SHA-256 hash comparison via `CryptoKit`.

### 📂 Module C: Intelligent File Organizer
* Automatically categorizes loose files in `~/Downloads`, `~/Documents`, or custom folders into organized subfolders (`Documents`, `Installers`, `Archives`, `Media`, `Code`).
* **Conflict Prevention**: If a destination file exists, automatically generates collision-free numbered suffixes (`filename (1).pdf`) instead of overwriting.

### 🧹 Module D: Intelligent Cleaning Engine
* Classifies cleanable items into strict Safety Tiers:
  * **Safe (Green)**: Xcode `DerivedData`, system crash logs, user temporary files.
  * **Review Recommended (Yellow)**: Old `.dmg` / `.pkg` disk images, duplicate files.
  * **High-Risk (Red)**: Application support leftovers.
  * **Protected (Prohibited)**: System files (`/System`, `/Library`, `/usr`, `/bin`), active applications, user documents, git repositories.
* Relocates approved cleanups to macOS Trash (`FileManager.default.trashItem`).

### 📊 Module E: Storage Analyzer
* Direct APFS volume quota analytics (`volumeTotalCapacityKey`, `volumeAvailableCapacityKey`).
* Stacked visual breakdown across 8 file categories.
* Interactive largest files browser with direct Finder reveal.

### ⏱️ Module F: Approval Center & Rollback Ledger
* Transparent modal displays exact source paths, destination paths, reclaimed bytes, and reasons before execution.
* Audit ledger persisted in `~/Library/Application Support/MacGuard/operations_ledger.json`.
* Instant one-click rollback for file moves and trash relocations.

---

## 3. Hardware & Architecture Baseline

Tested and optimized on **Apple Silicon M5 Pro**:
* **Memory Footprint**: ~140 MB resident (App) + ~2.5 GB unified memory (Ollama local model).
* **Inference Speed**: ~110 tokens/sec on local Metal GPU.
* **Cold Start**: < 0.8 seconds.

---

## 4. Quick Start & Building

### Requirements
* macOS 14.0 or later (macOS Sonoma, Sequoia, or later).
* Apple Silicon Mac (M1, M2, M3, M4, M5 or Pro/Max/Ultra).
* Swift 6.0+ toolchain (included in Xcode 15+ / 16+ / 27+).
* [Ollama](https://ollama.ai) (pre-installed for local model inference).

### Build & Install
Run the automated build script:
```bash
# 1. Compile release bundle and codesign
./Scripts/build_app.sh

# 2. Install to /Applications
./Scripts/install.sh

# 3. Launch MacGuard
open /Applications/MacGuard.app
```

### Running Automated Tests
```bash
cd MacGuard
swift test
```
All 10 tests across Security, Rollback, Scanner, Organizer, and AI Boundaries run and pass in ~2 seconds.

---

## 5. Security & Privacy Guarantees

1. **No Network Access Required**: Once the model (`qwen2.5:3b`) is downloaded locally, MacGuard operates entirely offline.
2. **Protected Paths Enforcement**: The hardcoded security whitelist blocks any operation targeting macOS system directories (`/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/etc`, `/private`) or sensitive user roots (`~/.ssh`, `~/.gnupg`, `~/Library/Keychains`).
3. **No Terminal Shell Access**: The AI has zero shell execution primitives.

---

## 6. Uninstalling

To completely remove MacGuard:
```bash
# 1. Quit the application
pkill MacGuard || true

# 2. Remove application bundle
rm -rf /Applications/MacGuard.app

# 3. (Optional) Remove local history ledger
rm -rf ~/Library/Application\ Support/MacGuard
```
