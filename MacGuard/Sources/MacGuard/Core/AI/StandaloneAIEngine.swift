import Foundation
import os

public final class StandaloneAIEngine: Sendable {
    public static let shared = StandaloneAIEngine()
    private static let logger = Logger(subsystem: "com.macguard", category: "StandaloneAIEngine")

    private init() {}

    /// Executes maintenance intent analysis locally on Apple Silicon with 0 MB idle RAM footprint
    public func analyzeQuery(_ query: String) async -> AIExecutionResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .messageOnly("Please enter a maintenance request or question regarding your MacBook.")
        }

        let lower = trimmed.lowercased()

        // 1. Boundary enforcement: Politely decline general non-maintenance questions
        if isOutOfScope(lower) {
            return .messageOnly(
                "I am MACGUARD, your specialized Mac maintenance assistant. I am strictly calibrated for macOS storage optimization, duplicate detection, file organization, and cache cleaning. I do not answer general trivia, poetry, or unrelated queries."
            )
        }

        // 2. Identify target directory
        let targetDirectory = resolveTargetDirectory(from: lower)

        // 3. Greetings
        if isGreeting(lower) {
            return .messageOnly(
                "Hello! I'm MacGuard, your private AI maintenance assistant running locally on Apple Silicon. I can optimize your storage, clean redundant folders in Downloads, remove disposable caches, or find duplicate files. What would you like to do?"
            )
        }

        // 4. Help & Capabilities
        if isHelpQuery(lower) {
            return .messageOnly(
                """
                Here is what I can do for your MacBook:
                • 📁 **Intelligent File Organizer**: Groups loose files (.blend, .drfx, .zxp, .ccx, .skill, .opus) and merges redundant folders into a clean hierarchy.
                • 🧹 **Safe System Cleanup**: Removes gigabytes of Xcode DerivedData, developer caches, diagnostic logs, and disposable installers.
                • 🔍 **Cryptographic Duplicate Finder**: Identifies identical files via SHA-256 with 1-click Finder reveal.
                • 📊 **Storage Analyzer**: Complete APFS disk breakdown with top 25 largest files and instant Quick-Trash.
                • 🛡️ **Full System Audit**: Multi-engine diagnostic health check of your entire storage in one tap.

                All file operations are 100% reversible via the Rollback Ledger.
                """
            )
        }

        // 5. Permissions & Full Disk Access Inquiries
        if isPermissionQuery(lower) {
            let fdaStatus = PermissionManager.isFullDiskAccessGranted
            if fdaStatus {
                return .messageOnly(
                    "Full Disk Access is currently **enabled**! MacGuard has unrestricted access to analyze APFS storage, locate duplicate files, and safely clean developer caches across your Mac without repeated permission prompts."
                )
            } else {
                return .messageOnly(
                    """
                    macOS protects user directories (Documents, Downloads, Music) with individual security prompts.

                    To permanently stop macOS from asking for permission on every folder, you can grant **Full Disk Access**:
                    1. Open **System Settings > Privacy & Security > Full Disk Access**.
                    2. Toggle on **MacGuard** (or drag MacGuard.app from /Applications into the list).

                    Once enabled, MacGuard can analyze disk space, clean developer caches, and find duplicates without any popup dialogs. You can also click **'Grant Full Disk Access'** directly on the Dashboard banner.
                    """
                )
            }
        }

        // 6. Antivirus / Malware / Security inquiries
        if isSecurityOrVirusQuery(lower) {
            return .messageOnly(
                "macOS has built-in kernel-level security (XProtect and Gatekeeper) for malware protection. While MacGuard is not an antivirus signature scanner, I can scan your storage for leftover cache junk, failed downloads (.crdownload), or Windows artifacts ($RECYCLE.BIN, desktop.ini). Would you like to run a Safe Cleanup or Storage Analysis?"
            )
        }

        // 6. Audio / Creator Asset Queries
        if isCreatorOrAudioQuery(lower) {
            return .messageOnly(
                "I specialize in creator workflows! I recognize DaVinci Resolve templates (.drfx), Blender 3D models (.blend), Adobe plugins (.zxp, .ccx), AI skills (.skill), and voice recordings (.opus, .wav like 'The Long Pier' audio tracks). When organizing, I group them neatly into 'Design & 3D Assets' and 'Media & Entertainment'."
            )
        }

        // 7. Mac performance / Speed up
        if isPerformanceQuery(lower) {
            return .messageOnly(
                "To optimize performance and free memory, I can clean developer build caches (Xcode DerivedData, CocoaPods, NPM), system logs, and clear out unneeded installers. Would you like me to run a Safe Cleanup?"
            )
        }

        // 8. Full system audit / comprehensive optimization request
        if isFullAuditQuery(lower) {
            let summary = MacGuardAIEngine.shared.buildFullAuditSummary()
            let msg = "Comprehensive Mac audit complete. Discovered \(summary.formattedReclaimable) in reclaimable storage across system caches, installers, and duplicate files."
            return .fullAudit(message: msg, summary: summary)
        }

        // 9. Safe cache, junk, temporary files, and unnecessary space cleanup
        if isCleanupQuery(lower) {
            let candidates = CleanupEngine.shared.discoverCleanupCandidates()
            let total = candidates.reduce(0) { $0 + $1.size }
            let formatted = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            let msg = "Discovered \(candidates.count) disposable targets totaling \(formatted) eligible for safe relocation to Trash."
            return .cleanupPlan(message: msg, candidates: candidates)
        }

        // 10. Large files & storage consumption analysis
        if isStorageOrLargeFilesQuery(lower) {
            let overview = StorageAnalyzer.shared.analyzeStorage()
            let msg = "APFS Macintosh HD: \(overview.formattedAvailable) available out of \(overview.formattedTotal) total capacity. Top usage: \(overview.largestFiles.count) largest files indexed."
            return .storageAnalysis(message: msg, overview: overview)
        }

        // 11. Cryptographic duplicate detection
        if isDuplicateQuery(lower) {
            let dups = (try? SystemScanner.shared.findDuplicates(in: targetDirectory, minFileSize: 512)) ?? []
            let totalWasted = dups.reduce(0) { $0 + $1.totalWastedSpace }
            let formatted = ByteCountFormatter.string(fromByteCount: totalWasted, countStyle: .file)
            let msg = "Scanned \(targetDirectory.lastPathComponent) with SHA-256 and discovered \(dups.count) duplicate clusters (\(formatted) reclaimable)."
            return .duplicatePlan(message: msg, duplicates: dups)
        }

        // 12. Structured file organization & folder consolidation
        if isOrganizationQuery(lower) {
            let proposals = (try? FileOrganizer.shared.planOrganization(for: targetDirectory)) ?? []
            let folderMerges = FileOrganizer.shared.planFolderConsolidation(for: targetDirectory)

            var msg = "Analyzed \(targetDirectory.lastPathComponent): \(proposals.count) loose files ready for categorization"
            if !folderMerges.isEmpty {
                msg += ", and \(folderMerges.count) redundant subfolders ready for consolidation."
            } else {
                msg += "."
            }
            return .organizationPlan(message: msg, proposals: proposals, folderMerges: folderMerges)
        }

        // 13. Dynamic contextual fallback
        return .messageOnly(
            "I'm ready to maintain your Mac. You can ask me to 'Organize Downloads' (to group files & merge duplicate folders), 'Clean Caches' (to reclaim disk space), 'Find Duplicates' (via SHA-256), or run a 'Full System Audit'."
        )
    }

    private func isGreeting(_ text: String) -> Bool {
        let greetings = ["hi", "hello", "hey", "good morning", "good afternoon", "good evening", "yo", "sup", "greetings"]
        return greetings.contains { text == $0 || text.hasPrefix($0 + " ") || text.hasSuffix(" " + $0) }
    }

    private func isHelpQuery(_ text: String) -> Bool {
        let triggers = ["what can you do", "help", "features", "commands", "how does this work", "options", "what do you do", "capabilities"]
        return triggers.contains { text.contains($0) }
    }

    private func isSecurityOrVirusQuery(_ text: String) -> Bool {
        let triggers = ["virus", "antivirus", "malware", "scan for virus", "scan for viruses", "security check", "infected", "protect"]
        return triggers.contains { text.contains($0) }
    }

    private func isCreatorOrAudioQuery(_ text: String) -> Bool {
        let triggers = ["audio", "voice note", "voice notes", "the long pier", "davinci", "drfx", "blend", "blender", "opus", "whatsapp audio", "dialogue", "narrator"]
        return triggers.contains { text.contains($0) }
    }

    private func isPerformanceQuery(_ text: String) -> Bool {
        let triggers = ["slow", "speed up", "lag", "laggy", "ram", "memory", "performance", "boost"]
        return triggers.contains { text.contains($0) }
    }

    private func isFullAuditQuery(_ text: String) -> Bool {
        let triggers = [
            "full", "audit", "system scan", "scan all", "everything",
            "optimize my mac", "health check", "optimize", "maintenance check",
            "deep scan", "diagnostics", "check everything", "scan my mac", "all"
        ]
        return triggers.contains { trigger in
            text == trigger || text.contains(trigger)
        }
    }

    private func isCleanupQuery(_ text: String) -> Bool {
        let triggers = [
            "unnecessary", "unnecessary file", "clean", "cache", "installer",
            "deriveddata", "junk", "temporary", "temp file", "trash", "free up",
            "reclaim", "wipe junk", "remove installer"
        ]
        return triggers.contains { text.contains($0) }
    }

    private func isStorageOrLargeFilesQuery(_ text: String) -> Bool {
        let triggers = [
            "largest", "large file", "big file", "biggest", "huge file",
            "storage", "disk", "space", "drive", "analyze", "capacity",
            "usage", "top file", "heavy file"
        ]
        return triggers.contains { text.contains($0) }
    }

    private func isDuplicateQuery(_ text: String) -> Bool {
        let triggers = [
            "duplicate", "identical", "copies", "clones", "double file",
            "same file", "hash match", "sha256"
        ]
        return triggers.contains { text.contains($0) }
    }

    private func isOrganizationQuery(_ text: String) -> Bool {
        let triggers = [
            "organize", "sort", "clean up downloads", "group files",
            "tidy", "categorize", "arrange", "structure", "consolidate",
            "too many folders", "merge folders", "duplicate folders", "clean folders"
        ]
        return triggers.contains { text.contains($0) }
    }

    private func isPermissionQuery(_ text: String) -> Bool {
        let triggers = [
            "access", "permission", "permissions", "full disk access", "disk access",
            "full computer access", "asking again and again", "why does it ask", "allow access"
        ]
        return triggers.contains { text.contains($0) }
    }

    private func isOutOfScope(_ text: String) -> Bool {
        let outOfScopeKeywords = [
            "poem", "story", "joke", "recipe", "weather", "capital of", "who is",
            "write code for python", "javascript", "react", "html", "css", "song",
            "lyrics", "translate to french", "translate to spanish", "movie recommendation"
        ]
        return outOfScopeKeywords.contains { text.contains($0) }
    }

    private func resolveTargetDirectory(from text: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if text.contains("document") {
            return home.appendingPathComponent("Documents")
        } else if text.contains("desktop") {
            return home.appendingPathComponent("Desktop")
        } else if text.contains("picture") || text.contains("photo") {
            return home.appendingPathComponent("Pictures")
        } else if text.contains("movie") || text.contains("video") {
            return home.appendingPathComponent("Movies")
        } else {
            return home.appendingPathComponent("Downloads")
        }
    }
}
