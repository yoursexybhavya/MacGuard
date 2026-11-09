import Foundation
import os

public struct FullAuditSummary: Sendable {
    public let storage: StorageOverview
    public let cleanupCandidates: [CleanupTarget]
    public let duplicates: [DuplicateGroup]
    public let unorganizedFilesCount: Int
    public let folderMergesCount: Int
    public let totalReclaimable: Int64

    public var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimable, countStyle: .file)
    }

    public init(
        storage: StorageOverview,
        cleanupCandidates: [CleanupTarget],
        duplicates: [DuplicateGroup],
        unorganizedFilesCount: Int,
        folderMergesCount: Int = 0
    ) {
        self.storage = storage
        self.cleanupCandidates = cleanupCandidates
        self.duplicates = duplicates
        self.unorganizedFilesCount = unorganizedFilesCount
        self.folderMergesCount = folderMergesCount

        let cleanupTotal = cleanupCandidates.reduce(0) { $0 + $1.size }
        let dupTotal = duplicates.reduce(0) { $0 + $1.totalWastedSpace }
        self.totalReclaimable = cleanupTotal + dupTotal
    }
}

public enum AIExecutionResult: Sendable {
    case messageOnly(String)
    case organizationPlan(message: String, proposals: [OrganizationProposal], folderMerges: [FolderMergeProposal])
    case cleanupPlan(message: String, candidates: [CleanupTarget])
    case duplicatePlan(message: String, duplicates: [DuplicateGroup])
    case storageAnalysis(message: String, overview: StorageOverview)
    case fullAudit(message: String, summary: FullAuditSummary)
}

public final class MacGuardAIEngine: Sendable {
    public static let shared = MacGuardAIEngine()
    private static let logger = Logger(subsystem: "com.macguard", category: "MacGuardAIEngine")

    private let systemPrompt = """
    You are MACGUARD AI, an expert, privacy-first local assistant for macOS system maintenance, file organization, and storage optimization.
    You run locally on Apple Silicon.

    RULES:
    1. Your primary responsibility is:
       - Full system maintenance audits and health checks ("action": "full_audit").
       - Organizing loose files and merging redundant folders ("action": "organize_folder").
       - Finding storage bottlenecks, large files, and APFS usage ("action": "analyze_storage").
       - Cleaning caches, disposable installers, junk, and temporary files ("action": "cleanup_caches").
       - Finding duplicate files ("action": "find_duplicates").
    2. When the user asks general questions, greets you, or asks what you can do, provide an intelligent, friendly conversational answer explaining your capabilities clearly with zero canned repetition. Set "toolCall": null.
    3. If the user asks for "full", "audit", "system scan", "optimize my mac", or "check everything", trigger "action": "full_audit".
    4. If the user asks about "largest files", "space", or "storage", trigger "action": "analyze_storage".
    5. If the user asks for "unnecessary files", "clean", "cache", or "free up space", trigger "action": "cleanup_caches".
    6. If the user asks to organize files or clean up folders, trigger "action": "organize_folder".
    7. Output a single valid JSON object:
       {
         "message": "Human-friendly explanation or conversational answer.",
         "confidence": 1.0,
         "toolCall": {
           "action": "full_audit" | "organize_folder" | "cleanup_caches" | "find_duplicates" | "analyze_storage" | "scan_directory",
           "targetPath": "optional path",
           "reasoning": "Why this action is proposed"
         }
       }
       If no tool is required, set "toolCall": null.
    """

    private init() {}

    /// Processes a user natural language query and dispatches appropriate maintenance operations
    public func processUserQuery(_ query: String) async -> AIExecutionResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .messageOnly("Please enter a maintenance request or question regarding your MacBook.")
        }

        // 1. Check if Ollama daemon is active with macguard-ai
        let ollama = OllamaService.shared
        if await ollama.isServiceAvailable() {
            do {
                let targetModel = AppSettings.effectiveOllamaModel()
                let jsonString = try await ollama.generateJSON(prompt: trimmed, systemPrompt: systemPrompt, model: targetModel)
                if let data = jsonString.data(using: .utf8),
                   let response = try? JSONDecoder().decode(MacGuardResponse.self, from: data) {
                    if let tool = response.toolCall {
                        return executeDispatchedTool(tool: tool, message: response.message)
                    } else if !response.message.isEmpty {
                        // CRITICAL: When the LLM answers a question or greets, return its answer directly!
                        return .messageOnly(response.message)
                    }
                }
            } catch {
                Self.logger.debug("Ollama inference bypassed, falling back to standalone engine: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 2. High-speed, 0 MB idle RAM native Standalone Engine with rich conversational reasoning
        return await StandaloneAIEngine.shared.analyzeQuery(trimmed)
    }

    private func executeDispatchedTool(tool: ToolCallPayload, message: String) -> AIExecutionResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let targetURL: URL
        if let path = tool.targetPath, !path.isEmpty {
            targetURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            targetURL = home.appendingPathComponent("Downloads")
        }

        switch tool.action {
        case .fullAudit:
            let summary = buildFullAuditSummary()
            return .fullAudit(message: message, summary: summary)

        case .organizeFolder:
            let proposals = (try? FileOrganizer.shared.planOrganization(for: targetURL)) ?? []
            let folderMerges = FileOrganizer.shared.planFolderConsolidation(for: targetURL)
            return .organizationPlan(message: message, proposals: proposals, folderMerges: folderMerges)

        case .cleanupCaches:
            let targets = CleanupEngine.shared.discoverCleanupCandidates()
            return .cleanupPlan(message: message, candidates: targets)

        case .findDuplicates:
            let dups = (try? SystemScanner.shared.findDuplicates(in: targetURL, minFileSize: 512)) ?? []
            return .duplicatePlan(message: message, duplicates: dups)

        case .analyzeStorage, .scanDirectory:
            let overview = StorageAnalyzer.shared.analyzeStorage()
            return .storageAnalysis(message: message, overview: overview)
        }
    }

    public func buildFullAuditSummary() -> FullAuditSummary {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let storage = StorageAnalyzer.shared.analyzeStorage()
        let cleanups = CleanupEngine.shared.discoverCleanupCandidates()
        let downloads = home.appendingPathComponent("Downloads")
        let duplicates = (try? SystemScanner.shared.findDuplicates(in: downloads, minFileSize: 512)) ?? []
        let proposals = (try? FileOrganizer.shared.planOrganization(for: downloads)) ?? []
        let folderMerges = FileOrganizer.shared.planFolderConsolidation(for: downloads)

        return FullAuditSummary(
            storage: storage,
            cleanupCandidates: cleanups,
            duplicates: duplicates,
            unorganizedFilesCount: proposals.count,
            folderMergesCount: folderMerges.count
        )
    }
}
