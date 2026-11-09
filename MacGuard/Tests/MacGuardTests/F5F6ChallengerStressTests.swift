import Foundation
import Testing
@testable import MacGuard

@Suite("Feature F5 & F6 Challenger: Dynamic Progress Bar & Category Card Math Invariant Tests", .serialized)
struct F5F6ChallengerStressTests {

    // MARK: - 1. All 12 Categories Non-Zero vs All Zero

    @Test("F6: All 12 categories non-zero maintains order, min width clamping, and sum invariant")
    func testProgressBarAll12CategoriesNonZero() {
        let categories = FileCategory.allCases
        #expect(categories.count == 12)

        // Assign strictly increasing sizes to all 12 categories: 1 KB up to ~500 GB
        var segments: [StorageBarSegmentItem] = []
        var totalBytes: Int64 = 0
        var currentBytes: Int64 = 1_000 // 1 KB

        for cat in categories {
            segments.append(
                StorageBarSegmentItem(
                    id: cat.rawValue,
                    title: cat.rawValue,
                    subtitle: "\(cat.rawValue) files",
                    bytes: currentBytes,
                    color: cat.color,
                    icon: cat.systemIcon,
                    category: cat
                )
            )
            totalBytes += currentBytes
            currentBytes *= 5 // Exponential progression: 1K, 5K, 25K, 125K, 625K, ...
        }

        let availableWidth: CGFloat = 1200.0
        let spacing: CGFloat = 2.0
        let minWidth: CGFloat = 8.0

        let widths = DynamicStorageProgressBar.computeProportionalWidths(
            segments: segments,
            totalBytes: totalBytes,
            availableWidth: availableWidth,
            spacing: spacing,
            minWidth: minWidth
        )

        // 1. All 12 segments must receive an allocated width
        #expect(widths.count == 12)

        // 2. Every single width must satisfy w >= minWidth (8.0 pt)
        for cat in categories {
            let w = widths[cat.rawValue]
            #expect(w != nil)
            #expect(w! >= minWidth, "Category \(cat.rawValue) width \(String(describing: w)) was below minWidth \(minWidth)")
        }

        // 3. Monotonicity: larger categories must have >= width compared to smaller categories
        for i in 0..<(segments.count - 1) {
            let smaller = segments[i]
            let larger = segments[i + 1]
            let wSmaller = widths[smaller.id]!
            let wLarger = widths[larger.id]!
            #expect(wLarger >= wSmaller, "Expected \(larger.id) (\(wLarger) pt) >= \(smaller.id) (\(wSmaller) pt)")
        }

        // 4. Total allocated width (sum + spacing) must match availableWidth within 1.0 pt
        let totalAllocated = widths.values.reduce(0, +) + (CGFloat(segments.count - 1) * spacing)
        #expect(abs(totalAllocated - availableWidth) <= 1.0, "Total allocated \(totalAllocated) deviated from availableWidth \(availableWidth)")
    }

    @Test("F6: All zero categories, zero totalBytes, or zero width return empty dictionary safely without NaN or crash")
    func testProgressBarAllZeroAndDegenerateInputs() {
        let categories = FileCategory.allCases

        // 1. All 12 categories with 0 bytes
        let zeroSegments = categories.map { cat in
            StorageBarSegmentItem(
                id: cat.rawValue,
                title: cat.rawValue,
                subtitle: "",
                bytes: 0,
                color: cat.color,
                icon: cat.systemIcon,
                category: cat
            )
        }

        let widthsAllZero = DynamicStorageProgressBar.computeProportionalWidths(
            segments: zeroSegments,
            totalBytes: 500_000_000_000,
            availableWidth: 1000.0
        )
        #expect(widthsAllZero.isEmpty)

        // 2. Total bytes is 0
        let normalSegments = [
            StorageBarSegmentItem(id: "docs", title: "Docs", subtitle: "", bytes: 500, color: .blue, icon: "doc", category: .documents)
        ]
        let widthsZeroBytes = DynamicStorageProgressBar.computeProportionalWidths(
            segments: normalSegments,
            totalBytes: 0,
            availableWidth: 1000.0
        )
        #expect(widthsZeroBytes.isEmpty)

        // 3. Negative total bytes
        let widthsNegativeBytes = DynamicStorageProgressBar.computeProportionalWidths(
            segments: normalSegments,
            totalBytes: -100,
            availableWidth: 1000.0
        )
        #expect(widthsNegativeBytes.isEmpty)

        // 4. Zero available width
        let widthsZeroWidth = DynamicStorageProgressBar.computeProportionalWidths(
            segments: normalSegments,
            totalBytes: 1000,
            availableWidth: 0.0
        )
        #expect(widthsZeroWidth.isEmpty)

        // 5. Negative available width
        let widthsNegativeWidth = DynamicStorageProgressBar.computeProportionalWidths(
            segments: normalSegments,
            totalBytes: 1000,
            availableWidth: -50.0
        )
        #expect(widthsNegativeWidth.isEmpty)

        // 6. Empty segments list
        let widthsEmptySegments = DynamicStorageProgressBar.computeProportionalWidths(
            segments: [],
            totalBytes: 1000,
            availableWidth: 1000.0
        )
        #expect(widthsEmptySegments.isEmpty)
    }

    // MARK: - 2. Single 1-Byte File on 16 PB Volume

    @Test("F6: Single 1-byte file on a 16 PB volume clamps to minWidth (8.0 pt) without exceeding total width")
    func testProgressBarSingle1ByteFileOn16PBVolume() {
        // 16 Petabytes = 16 * 1024^5 = 18,014,398,509,481,984 bytes
        let sixteenPetabytes: Int64 = 18_014_398_509_481_984
        let singleByte: Int64 = 1
        let freeSpaceBytes: Int64 = sixteenPetabytes - singleByte

        let docSegment = StorageBarSegmentItem(
            id: FileCategory.documents.rawValue,
            title: "Documents",
            subtitle: "1 file",
            bytes: singleByte,
            color: .blue,
            icon: "doc",
            category: .documents
        )

        let freeSegment = StorageBarSegmentItem(
            id: "freeSpace",
            title: "Available Free Space",
            subtitle: "Free",
            bytes: freeSpaceBytes,
            color: .green,
            icon: "circle.dashed",
            category: nil,
            isFreeSpace: true
        )

        let segments = [docSegment, freeSegment]
        let availableWidth: CGFloat = 1000.0
        let spacing: CGFloat = 2.0
        let minWidth: CGFloat = 8.0

        let widths = DynamicStorageProgressBar.computeProportionalWidths(
            segments: segments,
            totalBytes: sixteenPetabytes,
            availableWidth: availableWidth,
            spacing: spacing,
            minWidth: minWidth
        )

        #expect(widths.count == 2)

        let docWidth = widths[docSegment.id]
        let freeWidth = widths[freeSegment.id]

        #expect(docWidth != nil)
        #expect(freeWidth != nil)

        // 1. Clamping invariant: 1-byte file must be clamped to w >= minWidth (8.0 pt)
        #expect(docWidth! >= minWidth, "Single 1-byte file width was \(docWidth!), expected >= \(minWidth)")
        #expect(docWidth! == minWidth, "Single 1-byte file expected exactly minWidth \(minWidth), got \(docWidth!)")

        // 2. Free space must occupy the vast majority of the bar
        #expect(freeWidth! > 980.0, "Free space was \(freeWidth!), expected > 980.0 pt")

        // 3. Exact width invariant: allocated width must NOT exceed availableWidth
        let totalAllocated = docWidth! + freeWidth! + spacing
        #expect(totalAllocated <= availableWidth + 0.001, "Total allocated \(totalAllocated) exceeded availableWidth \(availableWidth)")
        #expect(abs(totalAllocated - availableWidth) <= 0.001, "Total allocated \(totalAllocated) did not match availableWidth \(availableWidth)")
    }

    // MARK: - 3. Scanned Bytes Exceeding Capacity (APFS Clones / Compression)

    @Test("F6: Scanned total bytes exceeding capacity (APFS clones/compression) self-normalizes without overflow")
    func testProgressBarScannedBytesExceedingDriveCapacity() {
        // Physical volume capacity: 500 GB
        let physicalDriveCapacity: Int64 = 500_000_000_000

        // Due to APFS clones and compression, sum of logical sizes = 1,200 GB
        let mediaBytes: Int64 = 600_000_000_000
        let archiveBytes: Int64 = 400_000_000_000
        let imageBytes: Int64 = 200_000_000_000
        let tinyCodeBytes: Int64 = 50 // 50 bytes (tests minWidth clamping alongside clone excess)

        let segments = [
            StorageBarSegmentItem(id: "media", title: "Media", subtitle: "", bytes: mediaBytes, color: .purple, icon: "film", category: .media),
            StorageBarSegmentItem(id: "archives", title: "Archives", subtitle: "", bytes: archiveBytes, color: .yellow, icon: "archivebox", category: .archives),
            StorageBarSegmentItem(id: "images", title: "Images", subtitle: "", bytes: imageBytes, color: .pink, icon: "photo", category: .images),
            StorageBarSegmentItem(id: "code", title: "Code", subtitle: "", bytes: tinyCodeBytes, color: .cyan, icon: "chevron.left.forwardslash.chevron.right", category: .code)
        ]

        let availableWidth: CGFloat = 1000.0
        let spacing: CGFloat = 2.0
        let minWidth: CGFloat = 8.0

        // In fullDisk mode, totalBytes passed is physicalDriveCapacity (500 GB), while segments sum to 1200 GB
        let widths = DynamicStorageProgressBar.computeProportionalWidths(
            segments: segments,
            totalBytes: physicalDriveCapacity,
            availableWidth: availableWidth,
            spacing: spacing,
            minWidth: minWidth
        )

        #expect(widths.count == 4)

        // 1. Verify tiny segment is clamped to at least minWidth
        let codeWidth = widths["code"]!
        #expect(codeWidth >= minWidth)

        // 2. Verify large segments preserve logical proportions: Media > Archives > Images
        let mediaWidth = widths["media"]!
        let archiveWidth = widths["archives"]!
        let imageWidth = widths["images"]!

        #expect(mediaWidth > archiveWidth)
        #expect(archiveWidth > imageWidth)
        #expect(imageWidth > codeWidth)

        // 3. Invariant: Total allocated width must not overflow available width
        let totalAllocated = widths.values.reduce(0, +) + (CGFloat(segments.count - 1) * spacing)
        #expect(totalAllocated <= availableWidth + 0.01, "Allocated width \(totalAllocated) exceeded availableWidth \(availableWidth)")
        #expect(abs(totalAllocated - availableWidth) <= 1.0, "Allocated width \(totalAllocated) deviated from availableWidth \(availableWidth)")
    }

    // MARK: - 4. Extremely Narrow Width (50 pt) and Ultra-Wide Display (3840 pt)

    @Test("F6: Extremely narrow width (50 pt) handles min clamping and does not crash or produce NaN")
    func testProgressBarNarrowWidth50pt() {
        // Case A: 2 segments fitting comfortably within 50 pt
        let segments2 = [
            StorageBarSegmentItem(id: "s1", title: "S1", subtitle: "", bytes: 100, color: .blue, icon: "doc", category: .documents),
            StorageBarSegmentItem(id: "s2", title: "S2", subtitle: "", bytes: 100, color: .orange, icon: "gear", category: .installers)
        ]

        let widths2 = DynamicStorageProgressBar.computeProportionalWidths(
            segments: segments2,
            totalBytes: 200,
            availableWidth: 50.0,
            spacing: 2.0,
            minWidth: 8.0
        )

        #expect(widths2.count == 2)
        #expect(widths2["s1"]! >= 8.0)
        #expect(widths2["s2"]! >= 8.0)
        let totalAllocated2 = widths2.values.reduce(0, +) + 2.0
        #expect(abs(totalAllocated2 - 50.0) <= 0.001)

        // Case B: All 12 categories non-zero on a 50 pt bar
        let categories = FileCategory.allCases
        let segments12 = categories.map { cat in
            StorageBarSegmentItem(
                id: cat.rawValue,
                title: cat.rawValue,
                subtitle: "",
                bytes: 1_000_000,
                color: cat.color,
                icon: cat.systemIcon,
                category: cat
            )
        }

        let widths12 = DynamicStorageProgressBar.computeProportionalWidths(
            segments: segments12,
            totalBytes: 12_000_000,
            availableWidth: 50.0,
            spacing: 2.0,
            minWidth: 8.0
        )

        #expect(widths12.count == 12)
        for (_, width) in widths12 {
            #expect(!width.isNaN, "Width was NaN")
            #expect(!width.isInfinite, "Width was infinite")
            #expect(width > 0, "Width was non-positive")
            #expect(width >= 8.0, "Width was less than minWidth")
        }

        // Case C: availableWidth less than spacing (10 pt available, 22 pt spacing)
        let widthsDegenerate = DynamicStorageProgressBar.computeProportionalWidths(
            segments: segments12,
            totalBytes: 12_000_000,
            availableWidth: 10.0,
            spacing: 2.0,
            minWidth: 8.0
        )

        #expect(widthsDegenerate.count == 12)
        for (_, width) in widthsDegenerate {
            #expect(!width.isNaN)
            #expect(!width.isInfinite)
            #expect(width >= 8.0)
        }
    }

    @Test("F6: Ultra-wide display (3840 pt) scales smoothly with high precision floating point accuracy")
    func testProgressBarUltraWideDisplay3840pt() {
        let categories = FileCategory.allCases
        let mockSizes: [FileCategory: Int64] = [
            .installers: 45_000_000_000,
            .archives: 15_000_000_000,
            .documents: 12_000_000_000,
            .media: 150_000_000_000,
            .creative: 80_000_000_000,
            .skills: 2_000_000_000,
            .academics: 5_000_000_000,
            .images: 60_000_000_000,
            .code: 8_000_000_000,
            .caches: 30_000_000_000,
            .junk: 4_000_000_000,
            .other: 10_000_000_000
        ]

        let totalScanned = mockSizes.values.reduce(0, +)
        let segments = categories.map { cat in
            StorageBarSegmentItem(
                id: cat.rawValue,
                title: cat.rawValue,
                subtitle: "",
                bytes: mockSizes[cat]!,
                color: cat.color,
                icon: cat.systemIcon,
                category: cat
            )
        }

        let ultraWideWidth: CGFloat = 3840.0
        let spacing: CGFloat = 2.0
        let minWidth: CGFloat = 8.0

        let widths = DynamicStorageProgressBar.computeProportionalWidths(
            segments: segments,
            totalBytes: totalScanned,
            availableWidth: ultraWideWidth,
            spacing: spacing,
            minWidth: minWidth
        )

        #expect(widths.count == 12)

        for (_, width) in widths {
            #expect(!width.isNaN)
            #expect(!width.isInfinite)
            #expect(width >= minWidth)
        }

        // Verify total allocated width matches 3840.0 pt within 0.1 pt
        let totalAllocated = widths.values.reduce(0, +) + (CGFloat(segments.count - 1) * spacing)
        #expect(abs(totalAllocated - ultraWideWidth) <= 0.1, "Expected ultra-wide sum to match 3840.0, got \(totalAllocated)")

        // Verify media (largest: 150 GB) has the largest width
        let mediaWidth = widths[FileCategory.media.rawValue]!
        for (cat, size) in mockSizes where cat != .media {
            let otherWidth = widths[cat.rawValue]!
            #expect(mediaWidth > otherWidth, "Media (150GB) width \(mediaWidth) should exceed \(cat.rawValue) (\(size) bytes) width \(otherWidth)")
        }
    }

    // MARK: - 5. Category Card Counts & Data Flow Verification

    @Test("F5: Category card counts and data flow strictly match StorageOverview data across all 12 categories")
    func testCategoryCardCountsAndDataFlowMatchStorageOverview() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser

        // Construct items across several categories
        let itemInst1 = ScannedItem(url: homeURL.appendingPathComponent("App1.dmg"), size: 100_000, modificationDate: Date(), category: .installers, isDirectory: false)
        let itemInst2 = ScannedItem(url: homeURL.appendingPathComponent("App2.pkg"), size: 200_000, modificationDate: Date(), category: .installers, isDirectory: false)
        let itemDoc = ScannedItem(url: homeURL.appendingPathComponent("Thesis.pdf"), size: 50_000, modificationDate: Date(), category: .documents, isDirectory: false)
        let itemMedia1 = ScannedItem(url: homeURL.appendingPathComponent("Track.mp3"), size: 10_000_000, modificationDate: Date(), category: .media, isDirectory: false)
        let itemMedia2 = ScannedItem(url: homeURL.appendingPathComponent("Video.mov"), size: 50_000_000, modificationDate: Date(), category: .media, isDirectory: false)
        let itemMedia3 = ScannedItem(url: homeURL.appendingPathComponent("Film.mp4"), size: 40_000_000, modificationDate: Date(), category: .media, isDirectory: false)
        let itemCode = ScannedItem(url: homeURL.appendingPathComponent("main.swift"), size: 4_096, modificationDate: Date(), category: .code, isDirectory: false)

        let categoryFilesInput: [FileCategory: [ScannedItem]] = [
            .installers: [itemInst1, itemInst2],
            .documents: [itemDoc],
            .media: [itemMedia1, itemMedia2, itemMedia3],
            .code: [itemCode]
        ]

        let totalCapacity: Int64 = 512_000_000_000
        let availableCapacity: Int64 = 200_000_000_000
        let usedCapacity: Int64 = 312_000_000_000

        let overview = StorageOverview(
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            usedCapacity: usedCapacity,
            categoryFiles: categoryFilesInput
        )

        // 1. Verify all 12 categories exist in categoryFiles and categorySizes
        #expect(overview.categoryFiles.count == 12)
        #expect(overview.categorySizes.count == 12)

        // 2. Verify file counts and byte sizes match exactly
        #expect(overview.fileCount(for: .installers) == 2)
        #expect(overview.categorySizes[.installers] == 300_000)
        #expect(overview.files(for: .installers).count == 2)

        #expect(overview.fileCount(for: .documents) == 1)
        #expect(overview.categorySizes[.documents] == 50_000)
        #expect(overview.files(for: .documents).count == 1)

        #expect(overview.fileCount(for: .media) == 3)
        #expect(overview.categorySizes[.media] == 100_000_000)
        #expect(overview.files(for: .media).count == 3)

        #expect(overview.fileCount(for: .code) == 1)
        #expect(overview.categorySizes[.code] == 4_096)
        #expect(overview.files(for: .code).count == 1)

        // 3. Verify all other 8 categories are empty (0 count, 0 bytes, empty array)
        let emptyCategories: [FileCategory] = [
            .archives, .creative, .skills, .academics, .images, .caches, .junk, .other
        ]
        for cat in emptyCategories {
            #expect(overview.fileCount(for: cat) == 0, "Category \(cat.rawValue) expected 0 fileCount")
            #expect(overview.categorySizes[cat] == 0, "Category \(cat.rawValue) expected 0 size")
            #expect(overview.files(for: cat).isEmpty, "Category \(cat.rawValue) expected empty files array")
        }

        // 4. Verify total scanned metrics
        let expectedScannedTotal: Int64 = 300_000 + 50_000 + 100_000_000 + 4_096
        #expect(overview.scannedTotalBytes == expectedScannedTotal)
        #expect(overview.totalScannedFileCount == 7)

        // 5. Verify percentage formulas matching StorageCategoryCardView inputs
        let scannedTotal = overview.scannedTotalBytes
        for cat in FileCategory.allCases {
            let size = overview.categorySizes[cat] ?? 0
            let pct = scannedTotal > 0 ? (Double(size) / Double(scannedTotal)) * 100 : 0.0

            if emptyCategories.contains(cat) {
                #expect(pct == 0.0)
            } else {
                #expect(pct > 0.0)
            }
        }

        let mediaPct = (Double(overview.categorySizes[.media]!) / Double(scannedTotal)) * 100
        #expect(mediaPct > 99.0) // ~99.65%
    }

    // MARK: - 6. Int64.max Scale & Zero Spacing / Zero MinWidth Tests

    @Test("F6: Int64.max totalBytes does not overflow Double arithmetic or crash")
    func testProgressBarInt64MaxScale() {
        let maxBytes: Int64 = Int64.max
        let halfBytes: Int64 = maxBytes / 2

        let seg1 = StorageBarSegmentItem(id: "s1", title: "S1", subtitle: "", bytes: halfBytes, color: .blue, icon: "doc", category: .documents)
        let seg2 = StorageBarSegmentItem(id: "s2", title: "S2", subtitle: "", bytes: halfBytes, color: .purple, icon: "film", category: .media)

        let widths = DynamicStorageProgressBar.computeProportionalWidths(
            segments: [seg1, seg2],
            totalBytes: maxBytes,
            availableWidth: 1000.0,
            spacing: 2.0,
            minWidth: 8.0
        )

        #expect(widths.count == 2)
        #expect(widths["s1"] != nil)
        #expect(widths["s2"] != nil)
        #expect(!widths["s1"]!.isNaN)
        #expect(!widths["s2"]!.isNaN)
        #expect(abs(widths["s1"]! - widths["s2"]!) <= 0.001)

        let totalAllocated = widths["s1"]! + widths["s2"]! + 2.0
        #expect(abs(totalAllocated - 1000.0) <= 0.001)
    }

    @Test("F6: Zero spacing and zero minWidth computes exact continuous proportions")
    func testProgressBarZeroSpacingAndZeroMinWidth() {
        let seg1 = StorageBarSegmentItem(id: "s1", title: "S1", subtitle: "", bytes: 300, color: .blue, icon: "doc", category: .documents)
        let seg2 = StorageBarSegmentItem(id: "s2", title: "S2", subtitle: "", bytes: 700, color: .purple, icon: "film", category: .media)

        let widths = DynamicStorageProgressBar.computeProportionalWidths(
            segments: [seg1, seg2],
            totalBytes: 1000,
            availableWidth: 1000.0,
            spacing: 0.0,
            minWidth: 0.0
        )

        #expect(widths.count == 2)
        #expect(abs(widths["s1"]! - 300.0) <= 0.001)
        #expect(abs(widths["s2"]! - 700.0) <= 0.001)
        #expect(abs(widths["s1"]! + widths["s2"]! - 1000.0) <= 0.001)
    }

    // MARK: - 7. Category Card Callback Invariants

    @Test("F5: StorageCategoryCardView triggers onSelect and onDrillDown callbacks correctly")
    @MainActor
    func testCategoryCardCallbacks() {
        var selectedCalled = false
        var drillDownCalled = false

        let card = StorageCategoryCardView(
            category: .installers,
            byteCount: 50_000,
            fileCount: 5,
            percentage: 12.5,
            isSelected: false,
            isBarHovered: false,
            onSelect: {
                selectedCalled = true
            },
            onDrillDown: {
                drillDownCalled = true
            }
        )

        card.onSelect()
        #expect(selectedCalled == true)

        card.onDrillDown()
        #expect(drillDownCalled == true)
    }
}

