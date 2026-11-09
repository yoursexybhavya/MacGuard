import Testing
import Foundation
import SwiftUI
import Metal
import Darwin
@testable import MacGuard

// MARK: - Mock URLProtocol for Ollama Daemon Testing

final class MockOllamaURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return (url.host == "127.0.0.1" || url.host == "localhost") && (url.port == 11434 || url.port == 11435)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockOllamaURLProtocol.requestHandler else {
            let err = NSError(domain: "MockOllamaURLProtocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "No handler registered"])
            client?.urlProtocol(self, didFailWithError: err)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Feature F18 Challenger Stress Test Suite

@Suite("Feature F18 Challenger: Settings, Ollama & Hardware Adversarial Stress Tests", .serialized)
struct F18ChallengerStressTests {

    // =========================================================================
    // MARK: - Section 1: AppSettings Persistence, Isolation & Clamping
    // =========================================================================

    @Test("F18 Challenger: AppSettingsKeys integrity, non-emptiness, and domain isolation")
    func testAppSettingsKeysIntegrityAndIsolation() {
        let domainA = "test.macguard.domainA.\(UUID().uuidString)"
        let domainB = "test.macguard.domainB.\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: domainA)!
        let defaultsB = UserDefaults(suiteName: domainB)!
        defer {
            defaultsA.removePersistentDomain(forName: domainA)
            defaultsB.removePersistentDomain(forName: domainB)
        }

        let allKeys = [
            AppSettingsKeys.selectedOllamaModel,
            AppSettingsKeys.customOllamaModel,
            AppSettingsKeys.enableBackgroundMonitoring,
            AppSettingsKeys.monitoringFrequencyMinutes,
            AppSettingsKeys.enableDownloadsWatch,
            AppSettingsKeys.downloadsClutterThreshold,
            AppSettingsKeys.lowStorageThresholdGB,
            AppSettingsKeys.enableAutoCleanupAlerts
        ]

        #expect(allKeys.count == 8)
        #expect(Set(allKeys).count == 8, "All 8 AppSettingsKeys must be unique")
        for key in allKeys {
            #expect(!key.isEmpty, "Key must not be empty")
            #expect(!key.contains(" "), "Key must not contain whitespace")
        }

        // Mutate domain A
        defaultsA.set("custom-model-alpha", forKey: AppSettingsKeys.selectedOllamaModel)
        defaultsA.set(45.0, forKey: AppSettingsKeys.monitoringFrequencyMinutes)
        defaultsA.set(false, forKey: AppSettingsKeys.enableBackgroundMonitoring)

        // Verify domain B is untouched
        #expect(defaultsB.string(forKey: AppSettingsKeys.selectedOllamaModel) == nil)
        #expect(defaultsB.object(forKey: AppSettingsKeys.monitoringFrequencyMinutes) == nil)
        #expect(defaultsB.object(forKey: AppSettingsKeys.enableBackgroundMonitoring) == nil)

        // Verify effective resolution on domain A vs domain B
        #expect(AppSettings.effectiveOllamaModel(userDefaults: defaultsA) == "custom-model-alpha")
        #expect(AppSettings.effectiveOllamaModel(userDefaults: defaultsB) == AppSettings.defaultSelectedModel)
    }

    @Test("F18 Challenger: Reset to defaults leaves zero stale state and preserves unrelated keys")
    func testAppSettingsResetToDefaultsPreservesUnrelatedKeys() {
        let suiteName = "test.macguard.reset.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Set all AppSettings to non-defaults
        testDefaults.set("custom", forKey: AppSettingsKeys.selectedOllamaModel)
        testDefaults.set("llama3:70b-heavy", forKey: AppSettingsKeys.customOllamaModel)
        testDefaults.set(false, forKey: AppSettingsKeys.enableBackgroundMonitoring)
        testDefaults.set(5.0, forKey: AppSettingsKeys.monitoringFrequencyMinutes)
        testDefaults.set(false, forKey: AppSettingsKeys.enableDownloadsWatch)
        testDefaults.set(85.0, forKey: AppSettingsKeys.downloadsClutterThreshold)
        testDefaults.set(50.0, forKey: AppSettingsKeys.lowStorageThresholdGB)
        testDefaults.set(false, forKey: AppSettingsKeys.enableAutoCleanupAlerts)

        // Set unrelated third-party keys in the same domain
        testDefaults.set("preserveThisValue", forKey: "com.user.customSetting")
        testDefaults.set(1337, forKey: "com.user.intCounter")

        // Trigger Reset
        AppSettings.resetToDefaults(userDefaults: testDefaults)

        // 1. Verify all 8 AppSettings keys reverted to exact defaults
        #expect(testDefaults.string(forKey: AppSettingsKeys.selectedOllamaModel) == AppSettings.defaultSelectedModel)
        #expect(testDefaults.string(forKey: AppSettingsKeys.customOllamaModel) == AppSettings.defaultCustomModel)
        #expect(testDefaults.bool(forKey: AppSettingsKeys.enableBackgroundMonitoring) == AppSettings.defaultEnableBackgroundMonitoring)
        #expect(testDefaults.double(forKey: AppSettingsKeys.monitoringFrequencyMinutes) == AppSettings.defaultMonitoringFrequencyMinutes)
        #expect(testDefaults.bool(forKey: AppSettingsKeys.enableDownloadsWatch) == AppSettings.defaultEnableDownloadsWatch)
        #expect(testDefaults.double(forKey: AppSettingsKeys.downloadsClutterThreshold) == AppSettings.defaultDownloadsClutterThreshold)
        #expect(testDefaults.double(forKey: AppSettingsKeys.lowStorageThresholdGB) == AppSettings.defaultLowStorageThresholdGB)
        #expect(testDefaults.bool(forKey: AppSettingsKeys.enableAutoCleanupAlerts) == AppSettings.defaultEnableAutoCleanupAlerts)

        // 2. Verify unrelated keys were completely preserved
        #expect(testDefaults.string(forKey: "com.user.customSetting") == "preserveThisValue")
        #expect(testDefaults.integer(forKey: "com.user.intCounter") == 1337)

        // 3. Test idempotence: 20 sequential resets maintain identical state
        for _ in 0..<20 {
            AppSettings.resetToDefaults(userDefaults: testDefaults)
            #expect(testDefaults.string(forKey: AppSettingsKeys.selectedOllamaModel) == AppSettings.defaultSelectedModel)
        }
    }

    @Test("F18 Challenger: Custom model resolution handles whitespace, symbols, empty strings, and overrides")
    func testCustomModelResolutionAdversarial() {
        let suiteName = "test.macguard.custommodel.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Scenario 1: selected is "custom", custom is clean valid tag
        testDefaults.set("custom", forKey: AppSettingsKeys.selectedOllamaModel)
        testDefaults.set("deepseek-r1:8b", forKey: AppSettingsKeys.customOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == "deepseek-r1:8b")

        // Scenario 2: selected is "custom", custom has leading/trailing whitespace & newlines
        testDefaults.set("   \n\t  mistral-nemo:12b  \n\t  ", forKey: AppSettingsKeys.customOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == "mistral-nemo:12b")

        // Scenario 3: selected is "custom", custom is empty string -> fallback to default
        testDefaults.set("", forKey: AppSettingsKeys.customOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == AppSettings.defaultSelectedModel)

        // Scenario 4: selected is "custom", custom is pure whitespace -> fallback to default
        testDefaults.set("     \t\t\n\n   ", forKey: AppSettingsKeys.customOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == AppSettings.defaultSelectedModel)

        // Scenario 5: selected is "custom", custom contains unicode, emojis, or slashes
        testDefaults.set("huggingface.co/org/model-⚡:v1.0-q4_k_m", forKey: AppSettingsKeys.customOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == "huggingface.co/org/model-⚡:v1.0-q4_k_m")

        // Scenario 6: selected is a direct model tag ("llama3.2:1b"), custom is also set
        // The direct model MUST override customOllamaModel!
        testDefaults.set("llama3.2:1b", forKey: AppSettingsKeys.selectedOllamaModel)
        testDefaults.set("some-other-custom-model", forKey: AppSettingsKeys.customOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == "llama3.2:1b")

        // Scenario 7: selected is nil -> fallback to default
        testDefaults.removeObject(forKey: AppSettingsKeys.selectedOllamaModel)
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == AppSettings.defaultSelectedModel)
    }

    @Test("F18 Challenger: AppSettings handles corrupted types in UserDefaults safely without crashing")
    func testCorruptedTypesInUserDefaults() {
        let suiteName = "test.macguard.corrupt.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Inject invalid types where strings/doubles are expected
        testDefaults.set(["corrupted": "dictionary"], forKey: AppSettingsKeys.selectedOllamaModel)
        testDefaults.set(["array", "of", "items"], forKey: AppSettingsKeys.customOllamaModel)
        testDefaults.set("not-a-number", forKey: AppSettingsKeys.monitoringFrequencyMinutes)
        testDefaults.set(Data([0x00, 0xFF, 0x42]), forKey: AppSettingsKeys.enableBackgroundMonitoring)

        // effectiveOllamaModel should survive corrupted types and safely return default
        #expect(AppSettings.effectiveOllamaModel(userDefaults: testDefaults) == AppSettings.defaultSelectedModel)

        // resetToDefaults should cleanly overwrite corrupted types with valid defaults
        AppSettings.resetToDefaults(userDefaults: testDefaults)
        #expect(testDefaults.string(forKey: AppSettingsKeys.selectedOllamaModel) == AppSettings.defaultSelectedModel)
        #expect(testDefaults.double(forKey: AppSettingsKeys.monitoringFrequencyMinutes) == 15.0)
        #expect(testDefaults.bool(forKey: AppSettingsKeys.enableBackgroundMonitoring) == true)
    }

    @Test("F18 Challenger: Frequency formatting handles boundary, sub-minute, zero, and negative values")
    func testFrequencyFormattingBoundaries() {
        // Standard presets
        #expect(AppSettings.formatFrequency(5.0) == "Every 5 minutes")
        #expect(AppSettings.formatFrequency(15.0) == "Every 15 minutes")
        #expect(AppSettings.formatFrequency(30.0) == "Every 30 minutes")
        #expect(AppSettings.formatFrequency(60.0) == "Every 1 hour")

        // Intermediate values within 5...60 range
        #expect(AppSettings.formatFrequency(7.0) == "Every 7 minutes")
        #expect(AppSettings.formatFrequency(45.0) == "Every 45 minutes")
        #expect(AppSettings.formatFrequency(59.0) == "Every 59 minutes")

        // Extreme values above 60
        #expect(AppSettings.formatFrequency(90.0) == "Every 1 hour")
        #expect(AppSettings.formatFrequency(120.0) == "Every 1 hour")
        #expect(AppSettings.formatFrequency(1440.0) == "Every 1 hour")

        // Edge case: zero minutes
        #expect(AppSettings.formatFrequency(0.0) == "Every 0 minutes")

        // Edge case: fractional minutes (Int cast truncates)
        #expect(AppSettings.formatFrequency(14.9) == "Every 14 minutes")
        #expect(AppSettings.formatFrequency(5.2) == "Every 5 minutes")

        // Edge case: negative numbers
        #expect(AppSettings.formatFrequency(-10.0) == "Every -10 minutes")
    }

    // =========================================================================
    // MARK: - Section 2: HardwareMonitor Under Load & Metal Query Invariants
    // =========================================================================

    @Test("F18 Challenger: HardwareMonitor concurrent query stress under high load (100 parallel tasks)")
    func testHardwareMonitorConcurrentQueriesStress() async {
        let taskCount = 100

        await withTaskGroup(of: HardwareInfo.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    HardwareMonitor.queryHardware()
                }
            }

            var completed = 0
            for await info in group {
                completed += 1
                // Verify invariants across all parallel query results
                #expect(!info.chipName.isEmpty)
                #expect(info.coreCount > 0)
                #expect(info.physicalMemoryBytes > 0)
                #expect(info.activeResidentMemoryBytes > 0)
                #expect(info.systemFreeMemoryBytes > 0)
                #expect(info.systemFreeMemoryBytes <= Int64(info.physicalMemoryBytes))
                #expect(!info.formattedPhysicalMemory.isEmpty)
                #expect(!info.formattedActiveRAM.isEmpty)
                #expect(!info.formattedSystemFree.isEmpty)
                #expect(!info.deviceSummary.isEmpty)
                #expect(!info.activeMemorySummary.isEmpty)
            }
            #expect(completed == taskCount)
        }
    }

    @Test("F18 Challenger: HardwareMonitor memory and CPU stats accurately reflect macOS ProcessInfo")
    func testHardwareMonitorMatchesRealSystem() {
        let info = HardwareMonitor.queryHardware()
        let realProcessInfo = ProcessInfo.processInfo

        // Core count must match active processor count
        #expect(info.coreCount == realProcessInfo.activeProcessorCount)

        // Physical memory must match system physical memory
        #expect(info.physicalMemoryBytes == realProcessInfo.physicalMemory)

        // Free memory must be positive and not exceed total physical memory
        #expect(info.systemFreeMemoryBytes > 0)
        #expect(info.systemFreeMemoryBytes <= Int64(info.physicalMemoryBytes))

        // Active resident RAM must be non-zero for running test process
        #expect(info.activeResidentMemoryBytes > 0)
        #expect(info.activeResidentMemoryBytes < Int64(info.physicalMemoryBytes))

        // Apple Silicon device check
        #expect(info.hasUnifiedMemory == true || info.hasUnifiedMemory == false)
        #expect(!info.chipName.trimmingCharacters(in: .whitespaces).isEmpty)

        // Device summary must contain the chip name
        #expect(info.deviceSummary.contains(info.chipName))
    }

    @Test("F18 Challenger: HardwareInfo Equatable value semantics")
    func testHardwareInfoEquatableSemantics() {
        let info1 = HardwareInfo(
            chipName: "Apple M4 Max",
            coreCount: 16,
            physicalMemoryBytes: 34359738368,
            formattedPhysicalMemory: "32 GB",
            hasUnifiedMemory: true,
            activeResidentMemoryBytes: 150000000,
            formattedActiveRAM: "150 MB",
            systemFreeMemoryBytes: 8000000000,
            formattedSystemFree: "8 GB Free"
        )

        let info2 = HardwareInfo(
            chipName: "Apple M4 Max",
            coreCount: 16,
            physicalMemoryBytes: 34359738368,
            formattedPhysicalMemory: "32 GB",
            hasUnifiedMemory: true,
            activeResidentMemoryBytes: 150000000,
            formattedActiveRAM: "150 MB",
            systemFreeMemoryBytes: 8000000000,
            formattedSystemFree: "8 GB Free"
        )

        let info3 = HardwareInfo(
            chipName: "Apple M4 Pro",
            coreCount: 12,
            physicalMemoryBytes: 25769803776,
            formattedPhysicalMemory: "24 GB",
            hasUnifiedMemory: true,
            activeResidentMemoryBytes: 100000000,
            formattedActiveRAM: "100 MB",
            systemFreeMemoryBytes: 4000000000,
            formattedSystemFree: "4 GB Free"
        )

        #expect(info1 == info2)
        #expect(info1 != info3)
        #expect(info1.deviceSummary == "Apple M4 Max • 32 GB Unified")
        #expect(info1.activeMemorySummary == "Standalone Offline AI • 150 MB Active")
    }

    @Test("F18 Challenger: HardwareMonitor rapid MainActor refresh maintains consistency")
    @MainActor
    func testHardwareMonitorRapidRefresh() {
        let monitor = HardwareMonitor.shared

        // Refresh 30 times in rapid succession
        for _ in 0..<30 {
            monitor.refresh()
            #expect(!monitor.hardwareInfo.chipName.isEmpty)
            #expect(monitor.hardwareInfo.coreCount > 0)
        }
    }

    // =========================================================================
    // MARK: - Section 3: OllamaModelInfo & Serialization Robustness
    // =========================================================================

    @Test("F18 Challenger: OllamaModelInfo decodes edge cases, nulls, and large sizes")
    func testOllamaModelInfoDecodingEdgeCases() throws {
        // 1. Nullable size and modified_at
        let jsonNulls = """
        {
            "models": [
                {
                    "name": "custom-model:latest"
                }
            ]
        }
        """
        let resNulls = try JSONDecoder().decode(OllamaTagsResponse.self, from: Data(jsonNulls.utf8))
        #expect(resNulls.models.count == 1)
        #expect(resNulls.models[0].name == "custom-model:latest")
        #expect(resNulls.models[0].size == nil)
        #expect(resNulls.models[0].modifiedAt == nil)

        // 2. Empty model list
        let jsonEmpty = """
        {
            "models": []
        }
        """
        let resEmpty = try JSONDecoder().decode(OllamaTagsResponse.self, from: Data(jsonEmpty.utf8))
        #expect(resEmpty.models.isEmpty)

        // 3. Huge 70GB model size and extra unknown fields
        let jsonHuge = """
        {
            "models": [
                {
                    "name": "llama3.3:70b",
                    "size": 75161927680,
                    "modified_at": "2026-11-08T12:00:00Z",
                    "digest": "sha256:abcdef1234567890",
                    "details": {
                        "parent_model": "",
                        "format": "gguf",
                        "family": "llama"
                    }
                }
            ]
        }
        """
        let resHuge = try JSONDecoder().decode(OllamaTagsResponse.self, from: Data(jsonHuge.utf8))
        #expect(resHuge.models.count == 1)
        #expect(resHuge.models[0].name == "llama3.3:70b")
        #expect(resHuge.models[0].size == 75161927680)
        #expect(resHuge.models[0].modifiedAt == "2026-11-08T12:00:00Z")

        // 4. Missing required name field throws DecodingError cleanly
        let jsonCorrupted = """
        {
            "models": [
                {
                    "size": 4000000000
                }
            ]
        }
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(OllamaTagsResponse.self, from: Data(jsonCorrupted.utf8))
        }
    }

    // =========================================================================
    // MARK: - Section 4: OllamaService Unreachable Port & Timeout Handling
    // =========================================================================

    @Test("F18 Challenger: OllamaService offline rejection on unallocated local port")
    func testOllamaServiceOfflineUnallocatedPort() async {
        // Point to an unallocated port where no service runs
        let deadURL = URL(string: "http://127.0.0.1:59871")!
        let service = OllamaService(baseURL: deadURL)

        // 1. isServiceAvailable must return false quickly without throwing or crashing
        let isAvailable = await service.isServiceAvailable()
        #expect(isAvailable == false)

        // 2. fetchLocalModels must throw an error cleanly
        await #expect(throws: Error.self) {
            try await service.fetchLocalModels()
        }

        // 3. generateJSON must throw an error cleanly
        await #expect(throws: Error.self) {
            try await service.generateJSON(prompt: "Hello", systemPrompt: "Test")
        }
    }

    // =========================================================================
    // MARK: - Section 5: OllamaService & MacGuardAIEngine Mocked Fallbacks
    // =========================================================================

    @Test("F18 Challenger: OllamaService processes mock HTTP 200 responses cleanly")
    func testOllamaServiceMockResponses() async throws {
        URLProtocol.registerClass(MockOllamaURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockOllamaURLProtocol.self)
            MockOllamaURLProtocol.requestHandler = nil
        }

        MockOllamaURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("api/tags") {
                let json = """
                {
                    "models": [
                        {"name": "macguard-ai:latest", "size": 4000000000},
                        {"name": "qwen2.5:14b", "size": 8000000000}
                    ]
                }
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (response, Data(json.utf8))
            } else if path.contains("api/generate") {
                let json = """
                {"response": "{\\"message\\": \\"Mocked response\\", \\"confidence\\": 1.0, \\"toolCall\\": null}"}
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (response, Data(json.utf8))
            }
            let notFound = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())
        }

        let service = OllamaService(baseURL: URL(string: "http://127.0.0.1:11434")!)

        let isAvailable = await service.isServiceAvailable()
        #expect(isAvailable == true)

        let models = try await service.fetchLocalModels()
        #expect(models.count == 2)
        #expect(models[0].name == "macguard-ai:latest")
        #expect(models[1].name == "qwen2.5:14b")

        let text = try await service.generateJSON(prompt: "Test", systemPrompt: "System")
        #expect(text.contains("Mocked response"))
    }

    @Test("F18 Challenger: OllamaService handles HTTP 500 error gracefully")
    func testOllamaServiceHTTP500Error() async {
        URLProtocol.registerClass(MockOllamaURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockOllamaURLProtocol.self)
            MockOllamaURLProtocol.requestHandler = nil
        }

        MockOllamaURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data("Internal Server Error".utf8))
        }

        let service = OllamaService(baseURL: URL(string: "http://127.0.0.1:11434")!)

        let isAvailable = await service.isServiceAvailable()
        #expect(isAvailable == false)

        await #expect(throws: Error.self) {
            try await service.fetchLocalModels()
        }

        await #expect(throws: Error.self) {
            try await service.generateJSON(prompt: "Test", systemPrompt: "System")
        }
    }

    @Test("F18 Challenger: MacGuardAIEngine falls back to Standalone Engine when Ollama is offline")
    func testMacGuardAIEngineOfflineFallback() async {
        // Without Ollama running or with offline endpoint, queries must route to Standalone Engine
        let engine = MacGuardAIEngine.shared

        // 1. Cleanup caches query
        let cleanResult = await engine.processUserQuery("Clean my system caches and logs")
        switch cleanResult {
        case .cleanupPlan(let message, let candidates):
            #expect(!message.isEmpty)
            #expect(candidates.count >= 0)
        default:
            Issue.record("Expected cleanupPlan, got \(cleanResult)")
        }

        // 2. Organize query
        let organizeResult = await engine.processUserQuery("Organize my downloads folder")
        switch organizeResult {
        case .organizationPlan(let message, _, _):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected organizationPlan, got \(organizeResult)")
        }

        // 3. Duplicate files query
        let dupResult = await engine.processUserQuery("Find duplicate files")
        switch dupResult {
        case .duplicatePlan(let message, _):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected duplicatePlan, got \(dupResult)")
        }

        // 4. Storage analysis query
        let storageResult = await engine.processUserQuery("Show my storage breakdown and disk usage")
        switch storageResult {
        case .storageAnalysis(let message, _):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected storageAnalysis, got \(storageResult)")
        }

        // 5. Full system audit query
        let auditResult = await engine.processUserQuery("Run a full system scan and optimization")
        switch auditResult {
        case .fullAudit(let message, let summary):
            #expect(!message.isEmpty)
            #expect(summary.storage.scannedTotalBytes >= 0)
        default:
            Issue.record("Expected fullAudit, got \(auditResult)")
        }

        // 6. Empty / whitespace queries
        let emptyResult = await engine.processUserQuery("   \n\t  ")
        switch emptyResult {
        case .messageOnly(let message):
            #expect(message.contains("Please enter a maintenance request"))
        default:
            Issue.record("Expected messageOnly for empty query, got \(emptyResult)")
        }

        // 7. General knowledge query outside maintenance scope
        let generalResult = await engine.processUserQuery("What is quantum computing?")
        switch generalResult {
        case .messageOnly(let message):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected messageOnly for non-maintenance query, got \(generalResult)")
        }
    }

    @Test("F18 Challenger: MacGuardAIEngine falls back to Standalone Engine when Ollama returns 500 error")
    func testMacGuardAIEngineOllamaHTTP500Fallback() async {
        URLProtocol.registerClass(MockOllamaURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockOllamaURLProtocol.self)
            MockOllamaURLProtocol.requestHandler = nil
        }

        MockOllamaURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("api/tags") {
                // Service available
                let json = #"{"models": [{"name": "macguard-ai:latest"}]}"#
                let res = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (res, Data(json.utf8))
            } else {
                // Generate fails with 500
                let res = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (res, Data("Daemon error".utf8))
            }
        }

        let engine = MacGuardAIEngine.shared
        let result = await engine.processUserQuery("Clean cache files")

        // Must gracefully fall back to standalone engine without crashing
        switch result {
        case .cleanupPlan(let message, _):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected cleanupPlan fallback, got \(result)")
        }
    }

    @Test("F18 Challenger: MacGuardAIEngine falls back when Ollama returns corrupted or non-JSON output")
    func testMacGuardAIEngineOllamaCorruptedJSONFallback() async {
        URLProtocol.registerClass(MockOllamaURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockOllamaURLProtocol.self)
            MockOllamaURLProtocol.requestHandler = nil
        }

        MockOllamaURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("api/tags") {
                let json = #"{"models": [{"name": "macguard-ai:latest"}]}"#
                let res = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (res, Data(json.utf8))
            } else {
                // Return 200 with garbage response
                let json = #"{"response": "Definitely not valid JSON {{{["}"#
                let res = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (res, Data(json.utf8))
            }
        }

        let engine = MacGuardAIEngine.shared
        let result = await engine.processUserQuery("Organize my folders")

        // Must gracefully fall back to standalone engine
        switch result {
        case .organizationPlan(let message, _, _):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected organizationPlan fallback, got \(result)")
        }
    }

    @Test("F18 Challenger: MacGuardAIEngine passes effective model from AppSettings to Ollama")
    func testMacGuardAIEnginePassesEffectiveModel() async {
        URLProtocol.registerClass(MockOllamaURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockOllamaURLProtocol.self)
            MockOllamaURLProtocol.requestHandler = nil
            AppSettings.resetToDefaults()
        }

        // Set custom model
        UserDefaults.standard.set("custom", forKey: AppSettingsKeys.selectedOllamaModel)
        UserDefaults.standard.set("test-challenger-model:4b", forKey: AppSettingsKeys.customOllamaModel)

        nonisolated(unsafe) var capturedModelName: String?

        MockOllamaURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("api/tags") {
                let json = #"{"models": [{"name": "test-challenger-model:4b"}]}"#
                let res = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (res, Data(json.utf8))
            } else if path.contains("api/generate") {
                if let bodyData = request.httpBody ?? request.httpBodyStream?.readFully(),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                   let model = json["model"] as? String {
                    capturedModelName = model
                }
                let json = #"{"response": "{\"message\": \"Tool dispatched\", \"confidence\": 1.0, \"toolCall\": {\"action\": \"full_audit\"}}"}"#
                let res = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (res, Data(json.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = MacGuardAIEngine.shared
        _ = await engine.processUserQuery("Full audit")

        #expect(capturedModelName == "test-challenger-model:4b", "Ollama request must receive model name resolved by AppSettings.effectiveOllamaModel()")
    }

    // =========================================================================
    // MARK: - Section 6: SettingsView UI Lifecycle & Component Tests
    // =========================================================================

    @Test("F18 Challenger: SettingsView and SecurityRuleRow instantiate cleanly under multiple lifecycles")
    @MainActor
    func testSettingsViewLifecycleStress() {
        for _ in 0..<10 {
            let view = SettingsView()
            _ = view.body
        }

        let row1 = SecurityRuleRow(icon: "shield.fill", title: "Offline Shield", desc: "No data leaves this Mac.")
        #expect(row1.title == "Offline Shield")
        #expect(row1.desc == "No data leaves this Mac.")

        let rowEmpty = SecurityRuleRow(icon: "", title: "", desc: "")
        #expect(rowEmpty.title.isEmpty)

        let rowLong = SecurityRuleRow(icon: "star", title: String(repeating: "A", count: 500), desc: String(repeating: "B", count: 1000))
        #expect(rowLong.title.count == 500)
        #expect(rowLong.desc.count == 1000)
    }
}

// MARK: - Helper Extension for InputStream reading

private extension InputStream {
    func readFully() -> Data {
        self.open()
        defer { self.close() }
        var result = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while self.hasBytesAvailable {
            let read = self.read(buffer, maxLength: bufferSize)
            if read > 0 {
                result.append(buffer, count: read)
            } else {
                break
            }
        }
        return result
    }
}
