import Foundation
import NaturalLanguage
import os

public enum AIModelLifecycleState: String, Sendable {
    case dormant = "Dormant (0 MB RAM)"
    case active = "Active (Processing)"
    case idle = "Standby (Ready)"
}

public final class StandaloneAIEngine: Sendable {
    public static let shared = StandaloneAIEngine()
    private static let logger = Logger(subsystem: "com.macguard", category: "StandaloneAIEngine")

    private init() {}

    /// Executes maintenance intent analysis locally on Apple Silicon without requiring external Ollama
    public func analyzeQuery(_ query: String) async -> AIExecutionResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .messageOnly("Please enter a maintenance request or question regarding your MacBook.")
        }

        let lower = trimmed.lowercased()

        // 1. Check for domain boundaries: non-maintenance requests
        if isOutOfScope(lower) {
            return .messageOnly(
                "I am MACGUARD, your specialized Mac maintenance assistant. I am strictly calibrated for macOS storage optimization, duplicate detection, file organization, and cache cleaning. I do not answer general knowledge or unrelated requests."
            )
        }

        // 2. Identify target directory
        let targetDirectory = resolveTargetDirectory(from: lower)

        // 3. Dispatch specialized maintenance action
        if lower.contains("organize") || lower.contains("sort") || lower.contains("clean up downloads") || lower.contains("group files") {
            let proposals = (try? FileOrganizer.shared.planOrganization(for: targetDirectory)) ?? []
            let msg = "Analyzed \(targetDirectory.lastPathComponent) and identified \(proposals.count) files ready for structured categorization."
            return .organizationPlan(message: msg, proposals: proposals)
        }

        if lower.contains("duplicate") || lower.contains("identical") || lower.contains("copies") {
            let dups = (try? SystemScanner.shared.findDuplicates(in: targetDirectory, minFileSize: 512)) ?? []
            let totalWasted = dups.reduce(0) { $0 + $1.totalWastedSpace }
            let formatted = ByteCountFormatter.string(fromByteCount: totalWasted, countStyle: .file)
            let msg = "Scanned \(targetDirectory.lastPathComponent) with SHA-256 and discovered \(dups.count) duplicate clusters (\(formatted) reclaimable)."
            return .duplicatePlan(message: msg, duplicates: dups)
        }

        if lower.contains("clean") || lower.contains("cache") || lower.contains("installer") || lower.contains("deriveddata") || lower.contains("junk") || lower.contains("temporary") {
            let candidates = CleanupEngine.shared.discoverCleanupCandidates()
            let total = candidates.reduce(0) { $0 + $1.size }
            let formatted = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            let msg = "Discovered \(candidates.count) disposable system targets totaling \(formatted) eligible for safe relocation to Trash."
            return .cleanupPlan(message: msg, candidates: candidates)
        }

        if lower.contains("storage") || lower.contains("disk") || lower.contains("space") || lower.contains("drive") || lower.contains("large file") || lower.contains("analyze") {
            let overview = StorageAnalyzer.shared.analyzeStorage()
            let msg = "APFS Macintosh HD: \(overview.formattedAvailable) available out of \(overview.formattedTotal) total capacity. Top usage: \(overview.largestFiles.count) largest files indexed."
            return .storageAnalysis(message: msg, overview: overview)
        }

        // Default intelligent assistance summary
        return .messageOnly(
            "I can optimize your Mac by organizing your \(targetDirectory.lastPathComponent) folder, finding exact duplicate files with SHA-256, safely cleaning developer caches, or analyzing APFS storage consumption. What would you like to run?"
        )
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
