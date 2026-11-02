import Foundation
import os

public struct OllamaModelInfo: Codable, Sendable {
    public let name: String
    public let size: Int64?
    public let modifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case modifiedAt = "modified_at"
    }
}

public struct OllamaTagsResponse: Codable, Sendable {
    public let models: [OllamaModelInfo]
}

public final class OllamaService: Sendable {
    public static let shared = OllamaService()
    private static let logger = Logger(subsystem: "com.macguard", category: "OllamaService")

    public let baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
    }

    /// Checks if local Ollama daemon is reachable
    public func isServiceAvailable() async -> Bool {
        let tagsURL = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        } catch {
            Self.logger.debug("Ollama service check failed: \(error.localizedDescription, privacy: .public)")
        }
        return false
    }

    /// Fetches the list of locally installed models
    public func fetchLocalModels() async throws -> [OllamaModelInfo] {
        let tagsURL = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await URLSession.shared.data(from: tagsURL)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "OllamaService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to Ollama"])
        }

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models
    }

    /// Sends a prompt with strict JSON output formatting for tool calling
    public func generateJSON(prompt: String, systemPrompt: String, model: String = "qwen2.5:3b") async throws -> String {
        let generateURL = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25.0

        let payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "system": systemPrompt,
            "stream": false,
            "format": "json",
            "options": [
                "temperature": 0.1,
                "top_p": 0.9,
                "num_predict": 512
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "OllamaService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Ollama generation failed"])
        }

        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let textResponse = jsonObject["response"] as? String else {
            throw NSError(domain: "OllamaService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Malformed response from Ollama"])
        }

        return textResponse
    }
}
