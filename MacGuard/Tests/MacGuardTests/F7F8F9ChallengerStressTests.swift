import Foundation
import Testing
import CryptoKit
import UniformTypeIdentifiers
@testable import MacGuard

// MARK: - Test Concurrency Lock & Sandbox

private let f789LedgerLock = NSLock()

private struct F789TestSandbox {
    let rootURL: URL

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacGuard_F789_\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.rootURL = tempDir
    }

    func fileURL(_ relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath()
    }

    @discardableResult
    func createFile(at relativePath: String, content: Data, posixPermissions: Int? = nil) throws -> URL {
        let url = fileURL(relativePath)
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try content.write(to: url)
        if let perms = posixPermissions {
            try FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: url.path)
        }
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

// MARK: - Suite: Feature F7, F8, F9 Challenger: Empirical Stress & Hardening Tests

@Suite("Feature F7, F8, F9 Challenger: Empirical Stress & Hardening Tests", .serialized)
struct F7F8F9ChallengerStressTests {

    // =========================================================================
    // SECTION 1: CategoryDetailView Live Search Filter Stress Tests
    // =========================================================================

    @Test("F7 Search: Special characters and regex metacharacters literal matching without crash")
    func testSearchSpecialCharactersAndRegexMetacharacters() {
        let items = [
            ScannedItem(url: URL(fileURLWithPath: "/tmp/File [v1.0] (Final).zip"), size: 1000, modificationDate: Date(), category: .archives, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/tmp/Data+Report*2026?.pdf"), size: 2000, modificationDate: Date(), category: .documents, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/tmp/Price$100^2.doc"), size: 3000, modificationDate: Date(), category: .documents, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/tmp/Path.with.many.dots.tar.gz"), size: 4000, modificationDate: Date(), category: .archives, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/tmp/Regex(test|sample)+special.dmg"), size: 5000, modificationDate: Date(), category: .installers, isDirectory: false)
        ]

        let searchFilter = { (query: String, list: [ScannedItem]) -> [ScannedItem] in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return list }
            return list.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.path.localizedCaseInsensitiveContains(trimmed)
            }
        }

        // Test regex and special symbols
        #expect(searchFilter("[", items).count == 1)
        #expect(searchFilter("]", items).count == 1)
        #expect(searchFilter("[v1.0]", items).count == 1)
        #expect(searchFilter("(", items).count == 2)
        #expect(searchFilter(")", items).count == 2)
        #expect(searchFilter("+", items).count == 2)
        #expect(searchFilter("*", items).count == 1)
        #expect(searchFilter("?", items).count == 1)
        #expect(searchFilter("$", items).count == 1)
        #expect(searchFilter("^", items).count == 1)
        #expect(searchFilter(".", items).count == 5) // Matches literal dot in all extensions
        #expect(searchFilter(".tar.gz", items).count == 1)
        #expect(searchFilter("|", items).count == 1)
        #expect(searchFilter("+special", items).count == 1)
    }

    @Test("F7 Search: Empty, whitespace-only, tab, and newline queries return all items")
    func testSearchEmptyAndWhitespaceOnlyQueries() {
        let items = [
            ScannedItem(url: URL(fileURLWithPath: "/tmp/a.dmg"), size: 100, modificationDate: Date(), category: .installers, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/tmp/b.dmg"), size: 200, modificationDate: Date(), category: .installers, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/tmp/c.dmg"), size: 300, modificationDate: Date(), category: .installers, isDirectory: false)
        ]

        let searchFilter = { (query: String, list: [ScannedItem]) -> [ScannedItem] in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return list }
            return list.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.path.localizedCaseInsensitiveContains(trimmed)
            }
        }

        #expect(searchFilter("", items).count == 3)
        #expect(searchFilter("   ", items).count == 3)
        #expect(searchFilter("\t", items).count == 3)
        #expect(searchFilter("\n\n  \t", items).count == 3)
        #expect(searchFilter(" \r\n\t ", items).count == 3)
    }

    @Test("F7 Search: Case insensitivity across uppercase, lowercase, and mixed casing")
    func testSearchCasingAndDiacriticMatching() {
        let items = [
            ScannedItem(url: URL(fileURLWithPath: "/tmp/UPPERCASE_ALPHA.DAT"), size: 10, modificationDate: Date(), category: .other, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/tmp/lowercase_beta.dat"), size: 20, modificationDate: Date(), category: .other, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/tmp/MixedCase_Gamma.Dat"), size: 30, modificationDate: Date(), category: .other, isDirectory: false)
        ]

        let searchFilter = { (query: String, list: [ScannedItem]) -> [ScannedItem] in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return list }
            return list.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.path.localizedCaseInsensitiveContains(trimmed)
            }
        }

        #expect(searchFilter("uppercase", items).count == 1)
        #expect(searchFilter("UPPERCASE", items).count == 1)
        #expect(searchFilter("LOWERCASE", items).count == 1)
        #expect(searchFilter("lowercase", items).count == 1)
        #expect(searchFilter("mixedcase", items).count == 1)
        #expect(searchFilter("MIXEDCASE", items).count == 1)
        #expect(searchFilter(".dat", items).count == 3)
        #expect(searchFilter(".DAT", items).count == 3)
    }

    @Test("F7 Search: Subpath matching against directory components")
    func testSearchPathMatching() {
        let items = [
            ScannedItem(url: URL(fileURLWithPath: "/Volumes/Archive/Engineering/2026/DesignDoc.pdf"), size: 100, modificationDate: Date(), category: .documents, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/Volumes/Backup/Marketing/Campaign.png"), size: 200, modificationDate: Date(), category: .images, isDirectory: false),
            ScannedItem(url: URL(fileURLWithPath: "/Users/demo/Developer/Source/Main.swift"), size: 300, modificationDate: Date(), category: .code, isDirectory: false)
        ]

        let searchFilter = { (query: String, list: [ScannedItem]) -> [ScannedItem] in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return list }
            return list.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.path.localizedCaseInsensitiveContains(trimmed)
            }
        }

        #expect(searchFilter("Engineering", items).count == 1)
        #expect(searchFilter("Marketing", items).count == 1)
        #expect(searchFilter("Developer", items).count == 1)
        #expect(searchFilter("Volumes", items).count == 2)
        #expect(searchFilter("NonExistentDirectory", items).isEmpty)
    }

    @Test("F7 Search: High-volume performance on 10,000 items")
    func testSearchWith10000ItemsPerformance() {
        var items: [ScannedItem] = []
        items.reserveCapacity(10_000)
        for i in 0..<10_000 {
            items.append(ScannedItem(
                url: URL(fileURLWithPath: "/Users/test/Category/file_\(i).dat"),
                size: Int64(i * 10),
                modificationDate: Date(),
                category: .other,
                isDirectory: false
            ))
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let trimmed = "file_99"
        let filtered = items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.path.localizedCaseInsensitiveContains(trimmed)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        #expect(!filtered.isEmpty)
        // High-volume filtering across 10,000 items must finish in < 0.25 seconds
        #expect(elapsed < 0.25)
    }

    @Test("F7 Search: Extremely long query string (5,000 characters) handles gracefully")
    func testSearchExtremelyLongQuery() {
        let items = [
            ScannedItem(url: URL(fileURLWithPath: "/tmp/sample.dmg"), size: 100, modificationDate: Date(), category: .installers, isDirectory: false)
        ]

        let longQuery = String(repeating: "A", count: 5_000)
        let trimmed = longQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.path.localizedCaseInsensitiveContains(trimmed)
        }

        #expect(filtered.isEmpty)
    }

    // =========================================================================
    // SECTION 2: 6-Way Sorting Stress & Invariant Tests
    // =========================================================================

    @Test("F7 Sorting: Invariants and exact ordering across all 6 SortOptions")
    func testAllSixSortOptionsInvariants() {
        let date1 = Date(timeIntervalSince1970: 1_000_000)
        let date2 = Date(timeIntervalSince1970: 2_000_000)
        let date3 = Date(timeIntervalSince1970: 3_000_000)

        let a = ScannedItem(url: URL(fileURLWithPath: "/tmp/A.dmg"), size: 100, modificationDate: date3, category: .installers, isDirectory: false)
        let b = ScannedItem(url: URL(fileURLWithPath: "/tmp/B.dmg"), size: 500, modificationDate: date1, category: .installers, isDirectory: false)
        let c = ScannedItem(url: URL(fileURLWithPath: "/tmp/C.dmg"), size: 300, modificationDate: date2, category: .installers, isDirectory: false)
        let items = [a, b, c]

        // 1. sizeDesc
        let sDesc = items.sorted { x, y in
            if x.size != y.size { return x.size > y.size }
            return x.name.localizedStandardCompare(y.name) == .orderedAscending
        }
        #expect(sDesc.map(\.name) == ["B.dmg", "C.dmg", "A.dmg"])

        // 2. sizeAsc
        let sAsc = items.sorted { x, y in
            if x.size != y.size { return x.size < y.size }
            return x.name.localizedStandardCompare(y.name) == .orderedAscending
        }
        #expect(sAsc.map(\.name) == ["A.dmg", "C.dmg", "B.dmg"])

        // 3. nameAsc
        let nAsc = items.sorted { x, y in
            let comp = x.name.localizedStandardCompare(y.name)
            if comp != .orderedSame { return comp == .orderedAscending }
            return x.path < y.path
        }
        #expect(nAsc.map(\.name) == ["A.dmg", "B.dmg", "C.dmg"])

        // 4. nameDesc
        let nDesc = items.sorted { x, y in
            let comp = x.name.localizedStandardCompare(y.name)
            if comp != .orderedSame { return comp == .orderedDescending }
            return x.path > y.path
        }
        #expect(nDesc.map(\.name) == ["C.dmg", "B.dmg", "A.dmg"])

        // 5. dateDesc
        let dDesc = items.sorted { x, y in
            if x.modificationDate != y.modificationDate { return x.modificationDate > y.modificationDate }
            return x.name.localizedStandardCompare(y.name) == .orderedAscending
        }
        #expect(dDesc.map(\.name) == ["A.dmg", "C.dmg", "B.dmg"])

        // 6. dateAsc
        let dAsc = items.sorted { x, y in
            if x.modificationDate != y.modificationDate { return x.modificationDate < y.modificationDate }
            return x.name.localizedStandardCompare(y.name) == .orderedAscending
        }
        #expect(dAsc.map(\.name) == ["B.dmg", "C.dmg", "A.dmg"])
    }

    @Test("F7 Sorting: Tie-breaking stability for identical sizes, names, and modification dates")
    func testTieBreakingStability() {
        let sameDate = Date(timeIntervalSince1970: 500_000)

        // Case A: Identical size tie-break by name
        let itemSize1 = ScannedItem(url: URL(fileURLWithPath: "/tmp/Zeta.bin"), size: 1024, modificationDate: sameDate, category: .other, isDirectory: false)
        let itemSize2 = ScannedItem(url: URL(fileURLWithPath: "/tmp/Alpha.bin"), size: 1024, modificationDate: sameDate, category: .other, isDirectory: false)

        let sortedBySize = [itemSize1, itemSize2].sorted { x, y in
            if x.size != y.size { return x.size > y.size }
            return x.name.localizedStandardCompare(y.name) == .orderedAscending
        }
        #expect(sortedBySize.map(\.name) == ["Alpha.bin", "Zeta.bin"])

        // Case B: Identical name tie-break by path
        let itemPath1 = ScannedItem(url: URL(fileURLWithPath: "/Volumes/B/file.txt"), size: 100, modificationDate: sameDate, category: .documents, isDirectory: false)
        let itemPath2 = ScannedItem(url: URL(fileURLWithPath: "/Volumes/A/file.txt"), size: 100, modificationDate: sameDate, category: .documents, isDirectory: false)

        let sortedByNameAsc = [itemPath1, itemPath2].sorted { x, y in
            let comp = x.name.localizedStandardCompare(y.name)
            if comp != .orderedSame { return comp == .orderedAscending }
            return x.path < y.path
        }
        #expect(sortedByNameAsc.map(\.path) == ["/Volumes/A/file.txt", "/Volumes/B/file.txt"])

        let sortedByNameDesc = [itemPath1, itemPath2].sorted { x, y in
            let comp = x.name.localizedStandardCompare(y.name)
            if comp != .orderedSame { return comp == .orderedDescending }
            return x.path > y.path
        }
        #expect(sortedByNameDesc.map(\.path) == ["/Volumes/B/file.txt", "/Volumes/A/file.txt"])

        // Case C: Identical date tie-break by name
        let sortedByDate = [itemSize1, itemSize2].sorted { x, y in
            if x.modificationDate != y.modificationDate { return x.modificationDate > y.modificationDate }
            return x.name.localizedStandardCompare(y.name) == .orderedAscending
        }
        #expect(sortedByDate.map(\.name) == ["Alpha.bin", "Zeta.bin"])
    }

    @Test("F7 Sorting: Finder natural numeric ordering via localizedStandardCompare")
    func testNaturalNumericSortOrder() {
        let names = ["item1.txt", "item2.txt", "item9.txt", "item10.txt", "item20.txt", "item100.txt"]
        let items = names.shuffled().map {
            ScannedItem(url: URL(fileURLWithPath: "/tmp/\($0)"), size: 100, modificationDate: Date(), category: .documents, isDirectory: false)
        }

        let sortedAsc = items.sorted { x, y in
            let comp = x.name.localizedStandardCompare(y.name)
            if comp != .orderedSame { return comp == .orderedAscending }
            return x.path < y.path
        }

        // Must sort natural numerically: item1, item2, item9, item10, item20, item100
        #expect(sortedAsc.map(\.name) == ["item1.txt", "item2.txt", "item9.txt", "item10.txt", "item20.txt", "item100.txt"])

        let sortedDesc = items.sorted { x, y in
            let comp = x.name.localizedStandardCompare(y.name)
            if comp != .orderedSame { return comp == .orderedDescending }
            return x.path > y.path
        }

        #expect(sortedDesc.map(\.name) == ["item100.txt", "item20.txt", "item10.txt", "item9.txt", "item2.txt", "item1.txt"])
    }

    @Test("F7 Sorting: Strict weak ordering holds across duplicate items (irreflexivity)")
    func testStrictWeakOrderingProperty() {
        let item = ScannedItem(url: URL(fileURLWithPath: "/tmp/same.txt"), size: 100, modificationDate: Date(), category: .documents, isDirectory: false)

        // For all comparators, x < x must NEVER be true
        let sizeDescLess = { (a: ScannedItem, b: ScannedItem) -> Bool in
            if a.size != b.size { return a.size > b.size }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        #expect(sizeDescLess(item, item) == false)

        let sizeAscLess = { (a: ScannedItem, b: ScannedItem) -> Bool in
            if a.size != b.size { return a.size < b.size }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        #expect(sizeAscLess(item, item) == false)

        let nameAscLess = { (a: ScannedItem, b: ScannedItem) -> Bool in
            let comp = a.name.localizedStandardCompare(b.name)
            if comp != .orderedSame { return comp == .orderedAscending }
            return a.path < b.path
        }
        #expect(nameAscLess(item, item) == false)

        let nameDescLess = { (a: ScannedItem, b: ScannedItem) -> Bool in
            let comp = a.name.localizedStandardCompare(b.name)
            if comp != .orderedSame { return comp == .orderedDescending }
            return a.path > b.path
        }
        #expect(nameDescLess(item, item) == false)

        let dateDescLess = { (a: ScannedItem, b: ScannedItem) -> Bool in
            if a.modificationDate != b.modificationDate { return a.modificationDate > b.modificationDate }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        #expect(dateDescLess(item, item) == false)

        let dateAscLess = { (a: ScannedItem, b: ScannedItem) -> Bool in
            if a.modificationDate != b.modificationDate { return a.modificationDate < b.modificationDate }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        #expect(dateAscLess(item, item) == false)
    }

    @Test("F7 Sorting: 10,000 items sorting completes in < 0.5s")
    func testSort10000ItemsPerformance() {
        var items: [ScannedItem] = []
        items.reserveCapacity(10_000)
        let refDate = Date()
        for i in 0..<10_000 {
            items.append(ScannedItem(
                url: URL(fileURLWithPath: "/tmp/file_\(i).dat"),
                size: Int64(10_000 - i),
                modificationDate: refDate.addingTimeInterval(TimeInterval(i)),
                category: .other,
                isDirectory: false
            ))
        }

        let start = CFAbsoluteTimeGetCurrent()
        _ = items.sorted { x, y in
            if x.size != y.size { return x.size > y.size }
            return x.name.localizedStandardCompare(y.name) == .orderedAscending
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(elapsed < 0.5)
    }

    // =========================================================================
    // SECTION 3: Multi-Select Batch Trashing Real Disk Tests
    // =========================================================================

    @Test("F7 Batch Trashing: Multi-select state transitions (select all, deselect all, partial)")
    func testMultiSelectStateTransitions() {
        let item1 = ScannedItem(url: URL(fileURLWithPath: "/tmp/1"), size: 10, modificationDate: Date(), category: .code, isDirectory: false)
        let item2 = ScannedItem(url: URL(fileURLWithPath: "/tmp/2"), size: 20, modificationDate: Date(), category: .code, isDirectory: false)
        let item3 = ScannedItem(url: URL(fileURLWithPath: "/tmp/3"), size: 30, modificationDate: Date(), category: .code, isDirectory: false)
        let items = [item1, item2, item3]

        var selectedIDs: Set<String> = []

        // Partial selection: select item1 and item3
        selectedIDs.insert(item1.id)
        selectedIDs.insert(item3.id)
        #expect(selectedIDs.count == 2)
        let partialBytes = items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
        #expect(partialBytes == 40)

        // Select all
        selectedIDs = Set(items.map(\.id))
        #expect(selectedIDs.count == 3)
        let totalBytes = items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
        #expect(totalBytes == 60)

        // Deselect all
        selectedIDs.removeAll()
        #expect(selectedIDs.isEmpty)
    }

    @Test("F7 & F8 Batch Trashing: Real disk trashing, destination capture, and batch rollback")
    func testBatchTrashingExecutionAndLedgerRecording() throws {
        let sandbox = try F789TestSandbox()
        defer { sandbox.cleanup() }

        let payloadA = Data("Payload A for batch trashing verification".utf8)
        let payloadB = Data("Payload B for batch trashing verification".utf8)
        let payloadC = Data("Payload C for batch trashing verification".utf8)
        let payloadUntouched = Data("Payload Untouched MUST NOT BE TRASHED".utf8)

        let fileA = try sandbox.createFile(at: "batch_target_A.dmg", content: payloadA)
        let fileB = try sandbox.createFile(at: "batch_target_B.dmg", content: payloadB)
        let fileC = try sandbox.createFile(at: "batch_target_C.dmg", content: payloadC)
        let fileUntouched = try sandbox.createFile(at: "batch_keep_untouched.dmg", content: payloadUntouched)

        let targetsToTrash = [
            ScannedItem(url: fileA, size: Int64(payloadA.count), modificationDate: Date(), category: .installers, isDirectory: false),
            ScannedItem(url: fileB, size: Int64(payloadB.count), modificationDate: Date(), category: .installers, isDirectory: false),
            ScannedItem(url: fileC, size: Int64(payloadC.count), modificationDate: Date(), category: .installers, isDirectory: false)
        ]

        f789LedgerLock.lock()
        defer { f789LedgerLock.unlock() }

        var operationIDs: [UUID] = []

        // Execute batch trashing through SecurityGuard
        for item in targetsToTrash {
            let trashURL = try SecurityGuard.shared.safelyMoveToTrash(
                at: item.url,
                reason: "Empirical challenger batch trashing test"
            )
            let opID = UUID()
            let record = OperationRecord(
                id: opID,
                actionType: .moveToTrash,
                sourcePath: item.path,
                destinationPath: trashURL.path,
                fileSize: item.size,
                reason: "Empirical challenger batch trashing test"
            )
            RollbackLedger.shared.recordOperation(record)
            operationIDs.append(opID)

            // Verify original file removed and trash file exists
            #expect(!FileManager.default.fileExists(atPath: item.path))
            #expect(FileManager.default.fileExists(atPath: trashURL.path))
        }

        // Verify untouched file was NOT affected
        #expect(FileManager.default.fileExists(atPath: fileUntouched.path))
        #expect(try Data(contentsOf: fileUntouched) == payloadUntouched)

        // Verify ledger recorded all 3 operations
        let history = RollbackLedger.shared.loadHistory()
        for opID in operationIDs {
            let found = history.first { $0.id == opID }
            #expect(found != nil)
            #expect(found?.isReversible == true)
            #expect(found?.actionType == .moveToTrash)
        }

        // Execute batch rollback
        let rollbackCount = try RollbackLedger.shared.rollbackAll(recordIds: operationIDs)
        #expect(rollbackCount == 3)

        // Verify all 3 files restored to original locations with identical bytes
        #expect(FileManager.default.fileExists(atPath: fileA.path))
        #expect(FileManager.default.fileExists(atPath: fileB.path))
        #expect(FileManager.default.fileExists(atPath: fileC.path))
        #expect(try Data(contentsOf: fileA) == payloadA)
        #expect(try Data(contentsOf: fileB) == payloadB)
        #expect(try Data(contentsOf: fileC) == payloadC)
    }

    @Test("F7 Batch Trashing: Handles partial failures gracefully without corrupting valid items")
    func testBatchTrashingPartialFailureHandling() throws {
        let sandbox = try F789TestSandbox()
        defer { sandbox.cleanup() }

        let validContent = Data("Valid payload to be trashed".utf8)
        let validFile = try sandbox.createFile(at: "valid_item.zip", content: validContent)
        let missingFile = sandbox.fileURL("non_existent_item.zip")

        let validItem = ScannedItem(url: validFile, size: Int64(validContent.count), modificationDate: Date(), category: .archives, isDirectory: false)
        let missingItem = ScannedItem(url: missingFile, size: 500, modificationDate: Date(), category: .archives, isDirectory: false)

        f789LedgerLock.lock()
        defer { f789LedgerLock.unlock() }

        var trashedIDs: Set<String> = []
        var failures: [String] = []

        for item in [validItem, missingItem] {
            do {
                let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(
                    at: item.url,
                    reason: "Partial failure test"
                )
                let record = OperationRecord(
                    actionType: .moveToTrash,
                    sourcePath: item.path,
                    destinationPath: trashedURL.path,
                    fileSize: item.size,
                    reason: "Partial failure test"
                )
                RollbackLedger.shared.recordOperation(record)
                trashedIDs.insert(item.id)
            } catch {
                failures.append(item.name)
            }
        }

        #expect(trashedIDs.count == 1)
        #expect(trashedIDs.contains(validItem.id))
        #expect(failures.count == 1)
        #expect(failures.first == missingItem.name)
        #expect(!FileManager.default.fileExists(atPath: validFile.path))
    }

    // =========================================================================
    // SECTION 4: FileMetadataViewModel CryptoKit SHA-256 & POSIX Permissions
    // =========================================================================

    @Test("F8 Metadata: Empty (0-byte) file computes standard SHA-256 digest")
    func testEmptyFileSHA256Hash() async throws {
        let sandbox = try F789TestSandbox()
        defer { sandbox.cleanup() }

        let emptyFile = try sandbox.createFile(at: "empty_file.dat", content: Data())
        let item = ScannedItem(url: emptyFile, size: 0, modificationDate: Date(), category: .other, isDirectory: false)

        let vm = await MainActor.run {
            FileMetadataViewModel(file: item)
        }

        await MainActor.run {
            vm.startAsyncHashComputation()
        }

        // Wait for async task
        try await Task.sleep(nanoseconds: 50_000_000)

        let hash = await MainActor.run { vm.sha256 }
        // Standard SHA-256 of empty input is e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let isComputing = await MainActor.run { vm.isComputingHash }
        #expect(isComputing == false)
    }

    @Test("F8 Metadata: Small file known cryptographic SHA-256 hash")
    func testSmallFileKnownSHA256Hash() async throws {
        let sandbox = try F789TestSandbox()
        defer { sandbox.cleanup() }

        let payload = "Hello, MacGuard!".data(using: .utf8)!
        let file = try sandbox.createFile(at: "hello.txt", content: payload)
        let item = ScannedItem(url: file, size: Int64(payload.count), modificationDate: Date(), category: .documents, isDirectory: false)

        let expectedHash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

        let vm = await MainActor.run {
            FileMetadataViewModel(file: item)
        }

        await MainActor.run {
            vm.startAsyncHashComputation()
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        let computedHash = await MainActor.run { vm.sha256 }
        #expect(computedHash == expectedHash)
    }

    @Test("F8 Metadata: Multi-megabyte file chunked streaming SHA-256 matches one-shot digest")
    func testLargeFileChunkedStreamingSHA256() async throws {
        let sandbox = try F789TestSandbox()
        defer { sandbox.cleanup() }

        // Create 2.5 MB file to verify chunking crossing 1 MB boundaries
        let largeData = Data(repeating: 0x5A, count: 2_621_440)
        let largeFile = try sandbox.createFile(at: "large_binary.bin", content: largeData)
        let item = ScannedItem(url: largeFile, size: Int64(largeData.count), modificationDate: Date(), category: .other, isDirectory: false)

        let expectedHash = SHA256.hash(data: largeData).map { String(format: "%02x", $0) }.joined()

        let vm = await MainActor.run {
            FileMetadataViewModel(file: item)
        }

        await MainActor.run {
            vm.startAsyncHashComputation()
        }

        // Wait for streaming completion
        for _ in 0..<20 {
            let done = await MainActor.run { vm.sha256 != nil }
            if done { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let computedHash = await MainActor.run { vm.sha256 }
        #expect(computedHash == expectedHash)
    }

    @Test("F8 Metadata: Hash computation cancellation halts task safely")
    func testHashComputationCancellation() async throws {
        let sandbox = try F789TestSandbox()
        defer { sandbox.cleanup() }

        let largeData = Data(repeating: 0x77, count: 5_000_000)
        let largeFile = try sandbox.createFile(at: "cancel_test.bin", content: largeData)
        let item = ScannedItem(url: largeFile, size: Int64(largeData.count), modificationDate: Date(), category: .other, isDirectory: false)

        let vm = await MainActor.run {
            FileMetadataViewModel(file: item)
        }

        await MainActor.run {
            vm.startAsyncHashComputation()
            vm.cancelHashComputation()
        }

        let isComputing = await MainActor.run { vm.isComputingHash }
        #expect(isComputing == false)
    }

    @Test("F8 Metadata: Non-existent file reports hash error without crashing")
    func testNonExistentFileHashError() async throws {
        let missingURL = URL(fileURLWithPath: "/tmp/non_existent_hash_target_\(UUID().uuidString).dat")
        let item = ScannedItem(url: missingURL, size: 100, modificationDate: Date(), category: .other, isDirectory: false)

        let vm = await MainActor.run {
            FileMetadataViewModel(file: item)
        }

        await MainActor.run {
            vm.startAsyncHashComputation()
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        await MainActor.run {
            #expect(vm.hashError != nil)
            #expect(vm.isComputingHash == false)
            #expect(vm.sha256 == nil)
        }
    }

    @Test("F8 Metadata: Correct POSIX permissions formatting (octal and symbolic)")
    @MainActor
    func testPOSIXPermissionsOctalAndSymbolicFormatting() throws {
        let sandbox = try F789TestSandbox()
        defer { sandbox.cleanup() }

        // Test 0o644 (rw-r--r--)
        let file644 = try sandbox.createFile(at: "perm644.txt", content: Data("644".utf8), posixPermissions: 0o644)
        let item644 = ScannedItem(url: file644, size: 3, modificationDate: Date(), category: .documents, isDirectory: false)
        let vm644 = FileMetadataViewModel(file: item644)
        #expect(vm644.posixPermissionsOctal == "0644")
        #expect(vm644.posixPermissionsSymbolic == "rw-r--r--")

        // Test 0o755 (rwxr-xr-x)
        let file755 = try sandbox.createFile(at: "perm755.sh", content: Data("755".utf8), posixPermissions: 0o755)
        let item755 = ScannedItem(url: file755, size: 3, modificationDate: Date(), category: .code, isDirectory: false)
        let vm755 = FileMetadataViewModel(file: item755)
        #expect(vm755.posixPermissionsOctal == "0755")
        #expect(vm755.posixPermissionsSymbolic == "rwxr-xr-x")

        // Test 0o700 (rwx------)
        let file700 = try sandbox.createFile(at: "perm700.key", content: Data("700".utf8), posixPermissions: 0o700)
        let item700 = ScannedItem(url: file700, size: 3, modificationDate: Date(), category: .other, isDirectory: false)
        let vm700 = FileMetadataViewModel(file: item700)
        #expect(vm700.posixPermissionsOctal == "0700")
        #expect(vm700.posixPermissionsSymbolic == "rwx------")
    }

    @Test("F8 Metadata: Uniform Type Identifier (UTType) extraction across file types")
    @MainActor
    func testUTTypeIdentification() throws {
        let sandbox = try F789TestSandbox()
        defer { sandbox.cleanup() }

        let pdf = try sandbox.createFile(at: "test.pdf", content: Data("%PDF-1.4".utf8))
        let vmPDF = FileMetadataViewModel(file: ScannedItem(url: pdf, size: 8, modificationDate: Date(), category: .documents, isDirectory: false))
        #expect(vmPDF.utTypeIdentifier.contains("pdf"))

        let png = try sandbox.createFile(at: "test.png", content: Data(repeating: 0, count: 10))
        let vmPNG = FileMetadataViewModel(file: ScannedItem(url: png, size: 10, modificationDate: Date(), category: .images, isDirectory: false))
        #expect(vmPNG.utTypeIdentifier.contains("png"))

        let swift = try sandbox.createFile(at: "test.swift", content: Data("let x = 1".utf8))
        let vmSwift = FileMetadataViewModel(file: ScannedItem(url: swift, size: 9, modificationDate: Date(), category: .code, isDirectory: false))
        #expect(vmSwift.utTypeIdentifier.contains("swift"))
    }

    // =========================================================================
    // SECTION 5: Quick Look Preview & Row Integration Tests
    // =========================================================================

    @Test("F9 Quick Look: ScannedFileRowView callback invocation on quick look trigger")
    @MainActor
    func testScannedFileRowViewQuickLookActionCallback() {
        let targetURL = URL(fileURLWithPath: "/Users/test/Documents/Demo.pdf")
        let item = ScannedItem(url: targetURL, size: 1024, modificationDate: Date(), category: .documents, isDirectory: false)

        var triggeredURL: URL? = nil
        let row = ScannedFileRowView(
            file: item,
            onQuickLook: { url in
                triggeredURL = url
            }
        )

        // Invoke quick look callback
        row.onQuickLook?(item.url)
        #expect(triggeredURL == targetURL)
    }

    @Test("F8 & F9: ScannedFileRowView reveal and trash action callbacks")
    @MainActor
    func testScannedFileRowViewRevealAndTrashCallbacks() {
        let targetURL = URL(fileURLWithPath: "/Users/test/Downloads/Setup.dmg")
        let item = ScannedItem(url: targetURL, size: 50_000, modificationDate: Date(), category: .installers, isDirectory: false)

        var revealedURL: URL? = nil
        var trashedItem: ScannedItem? = nil

        let row = ScannedFileRowView(
            file: item,
            onReveal: { url in revealedURL = url },
            onTrash: { it in trashedItem = it }
        )

        row.onReveal?(item.url)
        #expect(revealedURL == targetURL)

        row.onTrash?(item)
        #expect(trashedItem?.id == item.id)
    }

    @Test("F7 & F8: CategoryDetailView initialization with initialItems and overview")
    @MainActor
    func testCategoryDetailViewInitializationAndDefaults() {
        let itemA = ScannedItem(url: URL(fileURLWithPath: "/tmp/a.dmg"), size: 100, modificationDate: Date(), category: .installers, isDirectory: false)
        let itemB = ScannedItem(url: URL(fileURLWithPath: "/tmp/b.dmg"), size: 500, modificationDate: Date(), category: .installers, isDirectory: false)

        let detailView = CategoryDetailView(
            category: .installers,
            initialItems: [itemA, itemB],
            onDismiss: {}
        )

        // Default sort option is .sizeDesc: itemB (500) before itemA (100)
        let sorted = detailView.sortedAndFilteredItems
        #expect(sorted.count == 2)
        #expect(sorted.first?.id == itemB.id)
        #expect(sorted.last?.id == itemA.id)

        // Test convenience init with StorageOverview
        let overview = StorageOverview(
            totalCapacity: 1_000_000,
            availableCapacity: 500_000,
            usedCapacity: 500_000,
            categoryFiles: [.installers: [itemA, itemB]]
        )
        let overviewDetail = CategoryDetailView(
            category: .installers,
            overview: overview,
            onDismiss: {}
        )
        #expect(overviewDetail.sortedAndFilteredItems.count == 2)
    }
}
