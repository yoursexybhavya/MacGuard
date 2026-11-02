# Installation & Setup Guide: Project MACGUARD

---

## 1. System Requirements

* **Operating System**: macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later.
* **Architecture**: Apple Silicon (M1, M2, M3, M4, M5, Pro, Max, Ultra).
* **Memory**: Minimum 8 GB Unified Memory (16 GB or 24 GB recommended).
* **Storage**: ~2.5 GB free storage (1.9 GB for model weights, ~150 MB for app).
* **Developer Tools**: Swift 6.0+ toolchain (`xcode-select --install`).

---

## 2. Fast Automated Installation

Run the automated build and install pipeline:

```bash
# 1. Clone repository (private)
cd hopeful-tesla

# 2. Build release bundle (.app)
./Scripts/build_app.sh

# 3. Install to /Applications
./Scripts/install.sh

# 4. Open MacGuard
open /Applications/MacGuard.app
```

---

## 3. macOS Permissions (TCC)

MacGuard operates under standard macOS user permissions. When you first analyze specific folders (such as `Downloads` or `Documents`), macOS will prompt:

> *"MacGuard would like to access files in your Downloads folder."*
> **[ Don't Allow ]  [ OK ]**

Click **[ OK ]** to allow MacGuard to inspect and organize files in that directory.

You can verify or update permissions anytime in:
**System Settings > Privacy & Security > Files and Folders > MacGuard**

---

## 4. Optional Background Monitoring (LaunchAgent)

If you would like MacGuard to run a lightweight storage check periodically in the background:

### To Enable:
```bash
cp MacGuard/Resources/com.macguard.monitor.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.macguard.monitor.plist
```

### To Disable:
```bash
launchctl unload ~/Library/LaunchAgents/com.macguard.monitor.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.macguard.monitor.plist
```

---

## 5. Uninstallation

To cleanly remove MacGuard:

```bash
# 1. Terminate running process
pkill MacGuard || true

# 2. Remove application from /Applications
rm -rf /Applications/MacGuard.app

# 3. Remove application support and history ledger
rm -rf ~/Library/Application\ Support/MacGuard

# 4. Remove optional background monitor
rm -f ~/Library/LaunchAgents/com.macguard.monitor.plist
```
