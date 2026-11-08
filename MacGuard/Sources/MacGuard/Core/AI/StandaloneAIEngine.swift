import Foundation
import NaturalLanguage
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
                "I am MACGUARD, your specialized Mac maintenance assistant. I am strictly calibrated for macOS storage optimization, duplicate detection, file organization, and cache cleaning. I do not answer general knowledge or unrelated requests."
            )
        }

        // 2. Identify target directory
        let targetDirectory = resolveTargetDirectory(from: lower)

        // 3. Full system audit / comprehensive optimization request
        if isFullAuditQuery(lower) {
            let summary = MacGuardAIEngine.shared.buildFullAuditSummary()
            let msg = "Comprehensive Mac audit complete. Discovered \(summary.formattedReclaimable) in reclaimable storage across system caches, installers, and duplicate files."
            return .fullAudit(message: msg, summary: summary)
        }

        // 4. Safe cache, junk, temporary files, and unnecessary space cleanup
        if isCleanupQuery(lower) {
            let candidates = CleanupEngine.shared.discoverCleanupCandidates()
            let total = candidates.reduce(0) { $0 + $1.size }
            let formatted = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            let msg = "Discovered \(candidates.count) disposable targets totaling \(formatted) eligible for safe relocation to Trash."
            return .cleanupPlan(message: msg, candidates: candidates)
        }

        // 5. Large files & storage consumption analysis
        if isStorageOrLargeFilesQuery(lower) {
            let overview = StorageAnalyzer.shared.analyzeStorage()
            let msg = "APFS Macintosh HD: \(overview.formattedAvailable) available out of \(overview.formattedTotal) total capacity. Top usage: \(overview.largestFiles.count) largest files indexed."
            return .storageAnalysis(message: msg, overview: overview)
        }

        // 6. Cryptographic duplicate detection
        if isDuplicateQuery(lower) {
            let dups = (try? SystemScanner.shared.findDuplicates(in: targetDirectory, minFileSize: 512)) ?? []
            let totalWasted = dups.reduce(0) { $0 + $1.totalWastedSpace }
            let formatted = ByteCountFormatter.string(fromByteCount: totalWasted, countStyle: .file)
            let msg = "Scanned \(targetDirectory.lastPathComponent) with SHA-256 and discovered \(dups.count) duplicate clusters (\(formatted) reclaimable)."
            return .duplicatePlan(message: msg, duplicates: dups)
        }

        // 7. Structured file organization
        if isOrganizationQuery(lower) {
            let proposals = (try? FileOrganizer.shared.planOrganization(for: targetDirectory)) ?? []
            let msg = "Analyzed \(targetDirectory.lastPathComponent) and identified \(proposals.count) files ready for structured categorization."
            return .organizationPlan(message: msg, proposals: proposals)
        }

        // 8. Helpful fallback with specific capabilities
        return .messageOnly(
            "I can optimize your Mac by organizing your \(targetDirectory.lastPathComponent) folder, finding exact duplicate files with SHA-256, safely cleaning developer caches, or analyzing APFS storage consumption. Try asking 'Show largest files', 'Find unnecessary files', or 'full audit'."
        )
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
            "tidy", "categorize", "arrange", "structure"
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
