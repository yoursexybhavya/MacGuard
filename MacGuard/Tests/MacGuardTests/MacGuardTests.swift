import Foundation
import Testing
@testable import MacGuard

@Suite("Security & Boundary Guard Tests")
struct SecurityGuardTests {
    let guardInstance = SecurityGuard.shared

    @Test("Blocks protected system root paths")
    func testProtectedSystemPaths() throws {
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.validatePath("/System", forModification: true)
        }
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.validatePath("/System/Library", forModification: true)
        }
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.validatePath("/Library", forModification: true)
        }
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.validatePath("/usr/bin", forModification: true)
        }
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.validatePath("/bin/zsh", forModification: true)
        }
        #expect(throws: SecurityGuard.SecurityError.self) {
            _ = try guardInstance.validatePath("/private/etc/hosts", forModification: true)
        }
    }

    @Test("Blocks path traversal exploits")
    func testPathTraversalAttacks() throws {
        let maliciousPaths = [
            "../../etc/passwd",
            "/Users/krishnajangid/Downloads/../../System",
            "../Documents"
        ]

        for path in maliciousPaths {
            #expect(throws: SecurityGuard.SecurityError.self) {
                _ = try guardInstance.validatePath(path, forModification: false)
            }
        }
    }

    @Test("Blocks modification of sensitive user directories")
    func testSensitiveUserDirectories() throws {
        let sensitive = [
            "/Users/krishnajangid/.ssh/id_ed25519",
            "/Users/krishnajangid/.gnupg/secring.gpg"
        ]

        for path in sensitive {
            #expect(throws: SecurityGuard.SecurityError.self) {
                _ = try guardInstance.validatePath(path, forModification: true)
            }
        }
    }
}

@Suite("System Scanner & Duplicate Detection Tests")
struct SystemScannerTests {
    let scanner = SystemScanner.shared

    @Test("Categorizes files accurately according to extension")
    func testFileCategorization() {
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/app.dmg")) == .installers)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/bundle.pkg")) == .installers)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/archive.zip")) == .archives)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/data.tar.gz")) == .archives)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/thesis.pdf")) == .documents)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/photo.heic")) == .images)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/script.swift")) == .code)
        #expect(scanner.categorize(url: URL(fileURLWithPath: "/tmp/system.log")) == .caches)
    }

    @Test("Detects identical duplicate files using cryptographic SHA-256")
    func testDuplicateDetection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let contentA = "MacGuard Test File Content - Identical Duplicate Alpha".data(using: .utf8)!
        let contentB = "MacGuard Different Content - Beta Unique".data(using: .utf8)!

        let file1 = tempDir.appendingPathComponent("doc1.txt")
        let file2 = tempDir.appendingPathComponent("doc2.txt")
        let file3 = tempDir.appendingPathComponent("unique.txt")

        try contentA.write(to: file1)
        try contentA.write(to: file2)
        try contentB.write(to: file3)

        let duplicates = try scanner.findDuplicates(in: tempDir, minFileSize: 1)
        #expect(duplicates.count == 1)
        #expect(duplicates.first?.files.count == 2)
        #expect(duplicates.first?.totalWastedSpace == Int64(contentA.count))
    }
}

@Suite("File Organizer & Collision Prevention Tests")
struct FileOrganizerTests {
    let organizer = FileOrganizer.shared

    @Test("Proposes clean categorization without overwriting")
    func testOrganizationPlanning() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleDoc = tempDir.appendingPathComponent("notes.pdf")
        let sampleImg = tempDir.appendingPathComponent("chart.png")
        let sampleInstaller = tempDir.appendingPathComponent("setup.dmg")

        try "Dummy Doc".data(using: .utf8)?.write(to: sampleDoc)
        try "Dummy Img".data(using: .utf8)?.write(to: sampleImg)
        try "Dummy Installer".data(using: .utf8)?.write(to: sampleInstaller)

        let proposals = try organizer.planOrganization(for: tempDir)
        #expect(proposals.count == 3)

        let docProposal = proposals.first(where: { $0.fileName == "notes.pdf" })
        #expect(docProposal != nil)
        #expect(docProposal?.proposedDestinationURL.path.contains("Documents") == true)

        let installerProposal = proposals.first(where: { $0.fileName == "setup.dmg" })
        #expect(installerProposal != nil)
        #expect(installerProposal?.proposedDestinationURL.path.contains("Installers") == true)
    }

    @Test("Detects and proposes consolidation for redundant sibling folders")
    func testFolderConsolidation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let docsDir = tempDir.appendingPathComponent("Documents")
        let docsNotesDir = tempDir.appendingPathComponent("Documents & Notes")
        let mediaDir = tempDir.appendingPathComponent("Media")
        let mediaEntDir = tempDir.appendingPathComponent("Media & Entertainment")

        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsNotesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaEntDir, withIntermediateDirectories: true)

        let file1 = docsDir.appendingPathComponent("report.pdf")
        let file2 = mediaDir.appendingPathComponent("clip.mp4")
        try "test".write(to: file1, atomically: true, encoding: .utf8)
        try "test".write(to: file2, atomically: true, encoding: .utf8)

        let organizer = FileOrganizer.shared
        let merges = organizer.planFolderConsolidation(for: tempDir)
        #expect(merges.count >= 2)
        #expect(merges.contains { $0.sourceName == "Documents" && $0.destinationName == "Documents & Notes" })
        #expect(merges.contains { $0.sourceName == "Media" && $0.destinationName == "Media & Entertainment" })
    }
}

@Suite("Rollback Ledger & Reversibility Tests")
struct RollbackLedgerTests {
    let ledger = RollbackLedger.shared

    @Test("Records and executes reversible file rollback")
    func testRollbackOperation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source = tempDir.appendingPathComponent("original.txt")
        let destination = tempDir.appendingPathComponent("subfolder/moved.txt")
        try "Reversibility Test Data".data(using: .utf8)?.write(to: source)

        let fileManager = FileManager.default
        let subfolder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try fileManager.moveItem(at: source, to: destination)

        let recordId = UUID()
        let record = OperationRecord(
            id: recordId,
            actionType: .moveFile,
            sourcePath: source.path,
            destinationPath: destination.path,
            fileSize: 22,
            reason: "Unit test rollback"
        )
        ledger.recordOperation(record)

        #expect(!fileManager.fileExists(atPath: source.path))
        #expect(fileManager.fileExists(atPath: destination.path))

        // Trigger rollback
        try ledger.rollback(operationId: recordId)

        #expect(fileManager.fileExists(atPath: source.path))
        #expect(!fileManager.fileExists(atPath: destination.path))
    }
}

@Suite("AI Maintenance Intelligence & Boundaries Tests")
struct AIEngineTests {
    let aiEngine = MacGuardAIEngine.shared

    @Test("Specialized MacGuard boundaries politely decline non-maintenance queries")
    func testBoundaryRefusal() async {
        let result = await aiEngine.processUserQuery("Write me a poem about golden retrievers")
        switch result {
        case .messageOnly(let text):
            #expect(!text.isEmpty)
        default:
            Issue.record("Expected messageOnly refusal for non-maintenance query")
        }
    }

    @Test("Correctly routes maintenance query to organization engine")
    func testOrganizeRouting() async {
        let result = await aiEngine.processUserQuery("Organize my Downloads folder")
        switch result {
        case .organizationPlan(let message, _, _):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected organizationPlan for organization query")
        }
    }

    @Test("Correctly routes cleanup query to cleanup engine")
    func testCleanupRouting() async {
        let result = await aiEngine.processUserQuery("Clean up temporary caches and old logs")
        switch result {
        case .cleanupPlan(let message, _):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected cleanupPlan for cache cleaning query")
        }
    }

    @Test("Correctly routes unnecessary space query to cleanup engine")
    func testUnnecessaryFilesRouting() async {
        let result = await aiEngine.processUserQuery("Find unnecessary files taking up space")
        switch result {
        case .cleanupPlan(let message, _):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected cleanupPlan for 'Find unnecessary files taking up space'")
        }
    }

    @Test("Correctly routes largest files query to storage analysis")
    func testLargestFilesRouting() async {
        let result = await aiEngine.processUserQuery("Show me the largest files on my Mac")
        switch result {
        case .storageAnalysis(let message, let overview):
            #expect(!message.isEmpty)
            #expect(overview.totalCapacity > 0)
        default:
            Issue.record("Expected storageAnalysis for 'Show me the largest files on my Mac'")
        }
    }

    @Test("Correctly routes 'full' query to comprehensive system audit")
    func testFullAuditRouting() async {
        let result = await aiEngine.processUserQuery("full")
        switch result {
        case .fullAudit(let message, let summary):
            #expect(!message.isEmpty)
            #expect(summary.storage.totalCapacity > 0)
        default:
            Issue.record("Expected fullAudit for 'full' command")
        }
    }

    @Test("Conversational greeting responds naturally without repetitive fallback")
    func testGreeting() async {
        let result = await StandaloneAIEngine.shared.analyzeQuery("hi")
        switch result {
        case .messageOnly(let text):
            #expect(text.contains("Hello") || text.contains("Ready"))
            #expect(!text.contains("I can optimize your Mac by organizing your Downloads folder, finding exact duplicate files with SHA-256"))
        default:
            Issue.record("Expected messageOnly for greeting")
        }
    }

    @Test("Conversational help explains specific capabilities clearly")
    func testHelp() async {
        let result = await StandaloneAIEngine.shared.analyzeQuery("what can you do")
        switch result {
        case .messageOnly(let text):
            #expect(text.contains("Organizer") || text.contains("File"))
            #expect(text.contains("Cleanup") || text.contains("Duplicate"))
        default:
            Issue.record("Expected messageOnly for help query")
        }
    }

    @Test("Security query explains macOS native protections")
    func testSecurityQuery() async {
        let result = await StandaloneAIEngine.shared.analyzeQuery("scan my pc for viruses")
        switch result {
        case .messageOnly(let text):
            #expect(text.contains("XProtect") || text.contains("Gatekeeper") || text.contains("macOS"))
        default:
            Issue.record("Expected messageOnly for virus query")
        }
    }

    @Test("Creator query recognizes audio narration and project assets")
    func testAudioCreatorQuery() async {
        let result = await StandaloneAIEngine.shared.analyzeQuery("What is that audio narration file in Downloads?")
        switch result {
        case .messageOnly(let text):
            #expect(text.contains("audio") || text.contains("Long Pier") || text.contains("narration") || text.contains("voice"))
        default:
            Issue.record("Expected messageOnly for audio creator query")
        }
    }
}

