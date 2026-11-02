import Foundation
import os

public enum AIExecutionResult: Sendable {
    case messageOnly(String)
    case organizationPlan(message: String, proposals: [OrganizationProposal])
    case cleanupPlan(message: String, candidates: [CleanupTarget])
    case duplicatePlan(message: String, duplicates: [DuplicateGroup])
    case storageAnalysis(message: String, overview: StorageOverview)
}

public final class MacGuardAIEngine: Sendable {
    public static let shared = MacGuardAIEngine()
    private static let logger = Logger(subsystem: "com.macguard", category: "MacGuardAIEngine")

    private let systemPrompt = """
    You are MACGUARD AI, a specialized, privacy-first local assistant for macOS system maintenance, file organization, and storage optimization.
    You run locally on Apple Silicon.

    RULES:
    1. Your responsibility is STRICTLY limited to:
       - Organizing files (Downloads, Documents, Desktop, Media).
       - Finding storage bottlenecks, large files, and duplicates.
       - Recommending safe cache and installer cleanups.
    2. If the user asks general questions unrelated to macOS maintenance, politely decline and state your specialization.
    3. You must NEVER output shell commands or code to execute.
    4. You MUST always output a single valid JSON object conforming to:
       {
         "message": "Human-friendly explanation of what was found or what action is proposed.",
         "confidence": 1.0,
         "toolCall": {
           "action": "organize_folder" | "cleanup_caches" | "find_duplicates" | "analyze_storage" | "scan_directory",
           "targetPath": "optional path e.g. ~/Downloads or ~/Documents",
           "reasoning": "Why this operation is recommended"
         }
       }
       If no tool is needed, set "toolCall": null.
    """

    private init() {}

    /// Processes a user natural language query and dispatches appropriate maintenance operations
    public func processUserQuery(_ query: String) async -> AIExecutionResult {
        // 1. Primary: Run Standalone Offline Engine (0 MB idle RAM, no Ollama required)
        let standaloneResult = await StandaloneAIEngine.shared.analyzeQuery(query)
        
        // 2. If a local Ollama daemon is optionally running, we can check for deep reasoning,
        // but Ollama is NEVER required for offline maintenance or execution.
        let ollama = OllamaService.shared
        if await ollama.isServiceAvailable() {
            do {
                let jsonString = try await ollama.generateJSON(prompt: query, systemPrompt: systemPrompt)
                if let data = jsonString.data(using: .utf8),
                   let response = try? JSONDecoder().decode(MacGuardResponse.self, from: data) {
                    return executeDispatchedTool(response: response, originalQuery: query)
                }
            } catch {
                Self.logger.debug("Optional Ollama call returned error, using standalone offline engine result: \(error.localizedDescription, privacy: .public)")
            }
        }

        return standaloneResult
    }

    private func executeDispatchedTool(response: MacGuardResponse, originalQuery: String) -> AIExecutionResult {
        guard let tool = response.toolCall else {
            return .messageOnly(response.message)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let targetURL: URL
        if let path = tool.targetPath {
            targetURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            targetURL = home.appendingPathComponent("Downloads")
        }

        switch tool.action {
        case .organizeFolder:
            let proposals = (try? FileOrganizer.shared.planOrganization(for: targetURL)) ?? []
            return .organizationPlan(message: response.message, proposals: proposals)

        case .cleanupCaches:
            let targets = CleanupEngine.shared.discoverCleanupCandidates()
            return .cleanupPlan(message: response.message, candidates: targets)

        case .findDuplicates:
            let dups = (try? SystemScanner.shared.findDuplicates(in: targetURL)) ?? []
            return .duplicatePlan(message: response.message, duplicates: dups)

        case .analyzeStorage, .scanDirectory:
            let overview = StorageAnalyzer.shared.analyzeStorage()
            return .storageAnalysis(message: response.message, overview: overview)
        }
    }

    private func executeHeuristicFallback(query: String) -> AIExecutionResult {
        let lower = query.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser

        if lower.contains("organize") || lower.contains("sort") {
            let target = lower.contains("document") ? home.appendingPathComponent("Documents") : home.appendingPathComponent("Downloads")
            let proposals = (try? FileOrganizer.shared.planOrganization(for: target)) ?? []
            return .organizationPlan(
                message: "I analyzed '\(target.lastPathComponent)' and formulated a tidy organization structure grouping files by category.",
                proposals: proposals
            )
        } else if lower.contains("clean") || lower.contains("cache") || lower.contains("free up") || lower.contains("temp") {
            let candidates = CleanupEngine.shared.discoverCleanupCandidates()
            return .cleanupPlan(
                message: "I discovered safe cleanup candidates across your user caches, logs, and downloads.",
                candidates: candidates
            )
        } else if lower.contains("duplicate") || lower.contains("same file") {
            let target = home.appendingPathComponent("Downloads")
            let dups = (try? SystemScanner.shared.findDuplicates(in: target)) ?? []
            return .duplicatePlan(
                message: "I ran a multi-pass cryptographic scan and identified duplicate files.",
                duplicates: dups
            )
        } else if lower.contains("storage") || lower.contains("large") || lower.contains("space") || lower.contains("disk") {
            let overview = StorageAnalyzer.shared.analyzeStorage()
            return .storageAnalysis(
                message: "Here is the comprehensive storage breakdown for your Mac.",
                overview: overview
            )
        } else {
            return .messageOnly("I am MacGuard, specialized for macOS storage maintenance, file organization, and system optimization. You can ask me to organize your Downloads, clean system caches, find duplicate files, or analyze your disk space.")
        }
    }
}
