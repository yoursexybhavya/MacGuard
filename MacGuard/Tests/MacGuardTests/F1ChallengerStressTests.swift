import Foundation
import Testing
@testable import MacGuard

@Suite("Feature F1 Challenger: Empirical Stress & Invariant Tests", .serialized)
struct F1ChallengerStressTests {

    // MARK: - Test Sandbox Helper

    private struct TestSandbox {
        let rootURL: URL

        init() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacGuard_Challenger_\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            self.rootURL = tempDir
        }

        func fileURL(_ relativePath: String) -> URL {
            rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath()
        }

        @discardableResult
        func createFile(at relativePath: String, content: Data) throws -> URL {
            let url = fileURL(relativePath)
            let parent = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try content.write(to: url)
            return url
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    // MARK: - 1. Edge Case: 0 Files

    @Test("F1 Edge Case: 0 files in StorageOverview and StorageAnalyzer scan")
    func testEdgeCaseZeroFiles() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        // Empirical scan of an empty directory
        let overview = StorageAnalyzer.shared.scanSystemStorage(customTargets: [sandbox.rootURL])

        #expect(overview.totalScannedFileCount == 0)
        #expect(overview.scannedTotalBytes == 0)
        #expect(overview.largestFiles.isEmpty)

        // Verify all 12 categories return empty arrays and 0 counts
        for category in FileCategory.allCases {
            #expect(overview.files(for: category).isEmpty)
            #expect(overview.fileCount(for: category) == 0)
            #expect(overview.categorySizes[category] == 0)
            #expect(overview.categoryFiles[category]?.isEmpty == true)
        }

        // When scannedTotalBytes is 0, systemAndOtherBytes must equal usedCapacity
        #expect(overview.systemAndOtherBytes == overview.usedCapacity)

        // String formatters should produce valid strings without crashing
        #expect(!overview.formattedTotal.isEmpty)
        #expect(!overview.formattedAvailable.isEmpty)
        #expect(!overview.formattedUsed.isEmpty)
        #expect(!overview.formattedScannedTotal.isEmpty)
        #expect(!overview.formattedSystemAndOther.isEmpty)
        #expect(!overview.formattedReclaimable.isEmpty)
    }

    // MARK: - 2. Edge Case: 1 File

    @Test("F1 Edge Case: Exactly 1 file in StorageOverview and StorageAnalyzer scan")
    func testEdgeCaseOneFile() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let testFileSize: Int64 = 65_536
        let testData = Data(repeating: 0xAB, count: Int(testFileSize))
        try sandbox.createFile(at: "single_package.pkg", content: testData)

        let overview = StorageAnalyzer.shared.scanSystemStorage(customTargets: [sandbox.rootURL])

        #expect(overview.totalScannedFileCount == 1)
        #expect(overview.scannedTotalBytes == testFileSize)
        #expect(overview.largestFiles.count == 1)
        #expect(overview.largestFiles.first?.name == "single_package.pkg")
        #expect(overview.largestFiles.first?.size == testFileSize)

        // Exactly one category (.installers) should contain the file
        let installerFiles = overview.files(for: .installers)
        #expect(installerFiles.count == 1)
        #expect(overview.fileCount(for: .installers) == 1)
        #expect(installerFiles.first?.name == "single_package.pkg")
        #expect(installerFiles.first?.category == .installers)

        // The remaining 11 categories must be completely empty
        for category in FileCategory.allCases where category != .installers {
            #expect(overview.files(for: category).isEmpty)
            #expect(overview.fileCount(for: category) == 0)
            #expect(overview.categorySizes[category] == 0)
        }
    }

    // MARK: - 3. Stress Test: 10,000 Files Across All 12 Categories

    @Test("F1 Stress Test: 10,000 files distributed across all 12 categories")
    func testStress10000FilesAcrossAllCategories() {
        let startTime = CFAbsoluteTimeGetCurrent()
        let totalFileCount = 10_000
        let categories = FileCategory.allCases
        var categoryFilesMap: [FileCategory: [ScannedItem]] = [:]
        for cat in categories {
            categoryFilesMap[cat] = []
        }

        var expectedTotalBytes: Int64 = 0
        var allItems: [ScannedItem] = []
        allItems.reserveCapacity(totalFileCount)

        // Distribute 10,000 files across all 12 categories
        for i in 0..<totalFileCount {
            let cat = categories[i % categories.count]
            let size: Int64 = Int64((i % 500 + 1) * 1024) // 1 KB to 512 KB
            expectedTotalBytes += size
            let item = ScannedItem(
                url: URL(fileURLWithPath: "/virtual/\(cat.rawValue)/file_\(i).dat"),
                size: size,
                modificationDate: Date(timeIntervalSince1970: TimeInterval(1700000000 + i)),
                category: cat,
                isDirectory: false
            )
            categoryFilesMap[cat]?.append(item)
            allItems.append(item)
        }

        // Sort items per category descending by size as StorageAnalyzer does
        for cat in categories {
            categoryFilesMap[cat]?.sort(by: { $0.size > $1.size })
        }

        let largest25 = Array(allItems.sorted(by: { $0.size > $1.size }).prefix(25))

        let totalCapacity: Int64 = 2_000_000_000_000 // 2 TB
        let availableCapacity: Int64 = 800_000_000_000 // 800 GB
        let usedCapacity: Int64 = 1_200_000_000_000 // 1.2 TB

        // Initialize StorageOverview with 10,000 files
        let overview = StorageOverview(
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            usedCapacity: usedCapacity,
            categoryFiles: categoryFilesMap,
            largestFiles: largest25
        )

        let initElapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Invariant Verifications
        #expect(overview.totalScannedFileCount == totalFileCount)
        #expect(overview.scannedTotalBytes == expectedTotalBytes)
        #expect(overview.largestFiles.count == 25)

        // Verify per-category files and counts
        var accumulatedCount = 0
        var accumulatedBytes: Int64 = 0

        for cat in categories {
            let files = overview.files(for: cat)
            let count = overview.fileCount(for: cat)
            #expect(files.count == count)
            accumulatedCount += count

            let catBytes = files.reduce(0) { $0 + $1.size }
            #expect(overview.categorySizes[cat] == catBytes)
            accumulatedBytes += catBytes

            // Verify descending sort order
            for j in 0..<(files.count - 1) {
                #expect(files[j].size >= files[j + 1].size)
            }
        }

        #expect(accumulatedCount == totalFileCount)
        #expect(accumulatedBytes == expectedTotalBytes)

        // Verify arithmetic with systemAndOtherBytes
        let expectedSystemAndOther = max(0, usedCapacity - expectedTotalBytes)
        #expect(overview.systemAndOtherBytes == expectedSystemAndOther)
        #expect(overview.scannedTotalBytes + overview.systemAndOtherBytes == usedCapacity)

        let totalElapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Performance assertion: 10,000 items processing and validation must complete in < 1.0 second
        #expect(initElapsed < 1.0)
        #expect(totalElapsed < 1.5)
    }

    // MARK: - 4. Arithmetic Invariants Under Extreme Capacity Values

    @Test("F1 Arithmetic Invariants: Extreme capacity scales and edge values")
    func testArithmeticInvariantsExtremeCapacityValues() {
        // Scenario A: Standard typical APFS drive (500 GB used, 200 GB scanned)
        do {
            let overview = StorageOverview(
                totalCapacity: 1_000_000_000_000,
                availableCapacity: 500_000_000_000,
                usedCapacity: 500_000_000_000,
                categorySizes: [.documents: 200_000_000_000]
            )
            #expect(overview.scannedTotalBytes == 200_000_000_000)
            #expect(overview.systemAndOtherBytes == 300_000_000_000)
            #expect(overview.scannedTotalBytes + overview.systemAndOtherBytes == overview.usedCapacity)
            #expect(overview.usagePercentage == 0.5)
        }

        // Scenario B: Exact match (scannedTotalBytes == usedCapacity)
        do {
            let overview = StorageOverview(
                totalCapacity: 1_000_000_000_000,
                availableCapacity: 600_000_000_000,
                usedCapacity: 400_000_000_000,
                categorySizes: [.media: 400_000_000_000]
            )
            #expect(overview.scannedTotalBytes == 400_000_000_000)
            #expect(overview.systemAndOtherBytes == 0)
            #expect(overview.scannedTotalBytes + overview.systemAndOtherBytes == overview.usedCapacity)
        }

        // Scenario C: APFS Compression / Sparse files / Clones (scannedTotalBytes > usedCapacity)
        do {
            let overview = StorageOverview(
                totalCapacity: 500_000_000_000,
                availableCapacity: 400_000_000_000,
                usedCapacity: 100_000_000_000,
                categorySizes: [.code: 150_000_000_000]
            )
            #expect(overview.scannedTotalBytes == 150_000_000_000)
            // systemAndOtherBytes must clamp to 0 via max(0, usedCapacity - scannedTotalBytes)
            #expect(overview.systemAndOtherBytes == 0)
            #expect(overview.systemAndOtherBytes >= 0)
        }

        // Scenario D: Zero Capacity drive (unmounted / empty mount / error telemetry)
        do {
            let overview = StorageOverview(
                totalCapacity: 0,
                availableCapacity: 0,
                usedCapacity: 0,
                categorySizes: [:]
            )
            #expect(overview.totalCapacity == 0)
            #expect(overview.usagePercentage == 0.0)
            #expect(overview.scannedTotalBytes == 0)
            #expect(overview.systemAndOtherBytes == 0)
            #expect(!overview.formattedTotal.isEmpty)
            #expect(!overview.formattedScannedTotal.isEmpty)
        }

        // Scenario E: Multi-Petabyte Enterprise Storage Array (16 PB)
        do {
            let petabyte: Int64 = 1_000_000_000_000_000
            let totalCap: Int64 = 16 * petabyte
            let usedCap: Int64 = 10 * petabyte
            let scannedDoc: Int64 = 4 * petabyte
            let scannedMedia: Int64 = 3 * petabyte

            let overview = StorageOverview(
                totalCapacity: totalCap,
                availableCapacity: 6 * petabyte,
                usedCapacity: usedCap,
                categorySizes: [
                    .documents: scannedDoc,
                    .media: scannedMedia
                ]
            )

            #expect(overview.scannedTotalBytes == 7 * petabyte)
            #expect(overview.systemAndOtherBytes == 3 * petabyte)
            #expect(overview.scannedTotalBytes + overview.systemAndOtherBytes == usedCap)
            #expect(overview.usagePercentage == 0.625)
        }

        // Scenario F: Defensive check against negative filesystem capacities
        do {
            let overview = StorageOverview(
                totalCapacity: -100,
                availableCapacity: -50,
                usedCapacity: -50,
                categorySizes: [.other: 1000]
            )
            // guard totalCapacity > 0 should return 0.0 safely
            #expect(overview.usagePercentage == 0.0)
            // max(0, -50 - 1000) should clamp to 0
            #expect(overview.systemAndOtherBytes == 0)
        }
    }

    // MARK: - 5. files(for:) and Unknown Extensions (.other)

    @Test("F1 Category Routing: files(for:) with empty categories, non-empty, and unknown extensions")
    func testFilesForCategoryRoutingAndUnknownExtensions() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        // Create files for specific categories
        try sandbox.createFile(at: "custom_app.dmg", content: Data(repeating: 1, count: 2048))
        try sandbox.createFile(at: "library.zip", content: Data(repeating: 2, count: 4096))
        try sandbox.createFile(at: "script.py", content: Data(repeating: 3, count: 1024))

        // Create files with completely unknown extensions or no extension
        try sandbox.createFile(at: "unknown_payload.xyz", content: Data(repeating: 4, count: 8192))
        try sandbox.createFile(at: "custom_blob.foo_bar_ext", content: Data(repeating: 5, count: 16384))
        try sandbox.createFile(at: "UNNAMED_RAW_BINARY", content: Data(repeating: 6, count: 32768))

        let overview = StorageAnalyzer.shared.scanSystemStorage(customTargets: [sandbox.rootURL])

        // 1. Non-empty known categories
        let installerFiles = overview.files(for: .installers)
        #expect(installerFiles.count == 1)
        #expect(installerFiles.first?.name == "custom_app.dmg")

        let archiveFiles = overview.files(for: .archives)
        #expect(archiveFiles.count == 1)
        #expect(archiveFiles.first?.name == "library.zip")

        let codeFiles = overview.files(for: .code)
        #expect(codeFiles.count == 1)
        #expect(codeFiles.first?.name == "script.py")

        // 2. Unknown extensions routed to .other
        let otherFiles = overview.files(for: .other)
        #expect(otherFiles.count == 3)
        let otherNames = Set(otherFiles.map { $0.name })
        #expect(otherNames.contains("unknown_payload.xyz"))
        #expect(otherNames.contains("custom_blob.foo_bar_ext"))
        #expect(otherNames.contains("UNNAMED_RAW_BINARY"))

        // Verify sorted descending in .other
        #expect(otherFiles[0].size == 32768)
        #expect(otherFiles[1].size == 16384)
        #expect(otherFiles[2].size == 8192)

        // 3. Empty categories must return empty arrays safely
        let emptyCategories: [FileCategory] = [
            .documents, .media, .creative, .skills, .academics, .images, .caches, .junk
        ]
        for emptyCat in emptyCategories {
            let files = overview.files(for: emptyCat)
            #expect(files.isEmpty)
            #expect(overview.fileCount(for: emptyCat) == 0)
        }

        #expect(overview.totalScannedFileCount == 6)
        let expectedTotal = 2048 + 4096 + 1024 + 8192 + 16384 + 32768
        #expect(overview.scannedTotalBytes == Int64(expectedTotal))
    }

    // MARK: - 6. Concurrent Read Invariance

    @Test("F1 Concurrency: Concurrent multi-threaded reads on StorageOverview")
    func testConcurrentReadsOnStorageOverview() async {
        var categoryFiles: [FileCategory: [ScannedItem]] = [:]
        for cat in FileCategory.allCases {
            categoryFiles[cat] = [
                ScannedItem(
                    url: URL(fileURLWithPath: "/tmp/\(cat.rawValue).dat"),
                    size: 1024,
                    modificationDate: Date(),
                    category: cat,
                    isDirectory: false
                )
            ]
        }

        let overview = StorageOverview(
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000,
            usedCapacity: 500_000_000_000,
            categoryFiles: categoryFiles
        )

        // Spawn 100 concurrent async tasks reading all properties simultaneously
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    for cat in FileCategory.allCases {
                        let files = overview.files(for: cat)
                        let count = overview.fileCount(for: cat)
                        _ = overview.scannedTotalBytes
                        _ = overview.systemAndOtherBytes
                        _ = overview.usagePercentage
                        _ = overview.formattedTotal
                        _ = overview.formattedScannedTotal
                        _ = overview.formattedSystemAndOther
                        #expect(files.count == count)
                    }
                }
            }
        }

        #expect(overview.totalScannedFileCount == 12)
        #expect(overview.scannedTotalBytes == 12 * 1024)
    }
}
