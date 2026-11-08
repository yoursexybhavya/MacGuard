import Foundation

public enum ToolAction: String, Codable, Sendable {
    case scanDirectory = "scan_directory"
    case organizeFolder = "organize_folder"
    case cleanupCaches = "cleanup_caches"
    case findDuplicates = "find_duplicates"
    case analyzeStorage = "analyze_storage"
    case fullAudit = "full_audit"
}

public struct ToolCallPayload: Codable, Sendable {
    public let action: ToolAction
    public let targetPath: String?
    public let parameters: [String: String]?
    public let reasoning: String?

    public init(action: ToolAction, targetPath: String? = nil, parameters: [String: String]? = nil, reasoning: String? = nil) {
        self.action = action
        self.targetPath = targetPath
        self.parameters = parameters
        self.reasoning = reasoning
    }
}

public struct MacGuardResponse: Codable, Sendable {
    public let message: String
    public let toolCall: ToolCallPayload?
    public let confidence: Double?

    public init(message: String, toolCall: ToolCallPayload? = nil, confidence: Double? = 1.0) {
        self.message = message
        self.toolCall = toolCall
        self.confidence = confidence
    }
}
