import SwiftUI
import AppKit
import QuickLook

// MARK: - FileCategory Presentation Extensions

extension FileCategory: Identifiable {
    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .installers: return .orange
        case .archives: return .yellow
        case .documents: return .blue
        case .media: return .purple
        case .creative: return .indigo
        case .skills: return .mint
        case .academics: return .teal
        case .images: return .pink
        case .code: return .cyan
        case .caches: return .red
        case .junk: return .gray
        case .other: return .secondary
        }
    }
}

// MARK: - Button Style for Category Cards

public struct StorageCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Interactive Category Card (Feature F5)

public struct StorageCategoryCardView: View {
    public let category: FileCategory
    public let byteCount: Int64
    public let fileCount: Int
    public let percentage: Double
    public let isSelected: Bool
    public let isBarHovered: Bool
    public let onSelect: () -> Void
    public let onDrillDown: () -> Void

    @State private var isCardHovered: Bool = false

    public init(
        category: FileCategory,
        byteCount: Int64,
        fileCount: Int,
        percentage: Double,
        isSelected: Bool,
        isBarHovered: Bool = false,
        onSelect: @escaping () -> Void,
        onDrillDown: @escaping () -> Void
    ) {
        self.category = category
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.percentage = percentage
        self.isSelected = isSelected
        self.isBarHovered = isBarHovered
        self.onSelect = onSelect
        self.onDrillDown = onDrillDown
    }

    private var accentColor: Color {
        category.color
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private var formattedCount: String {
        fileCount == 1 ? "1 file" : "\(fileCount) files"
    }

    private var iconBackground: Color {
        if isSelected {
            return accentColor.opacity(0.28)
        } else if isCardHovered || isBarHovered {
            return accentColor.opacity(0.20)
        } else {
            return accentColor.opacity(0.12)
        }
    }

    private var cardBackground: Color {
        if isSelected {
            return accentColor.opacity(0.14)
        } else if isCardHovered || isBarHovered {
            return accentColor.opacity(0.06)
        } else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.55)
        }
    }

    private var cardBorderColor: Color {
        if isSelected {
            return accentColor
        } else if isCardHovered || isBarHovered {
            return accentColor.opacity(0.45)
        } else {
            return Color.primary.opacity(0.08)
        }
    }

    private var cardShadowColor: Color {
        if isSelected {
            return accentColor.opacity(0.28)
        } else if isCardHovered {
            return Color.black.opacity(0.08)
        } else {
            return Color.black.opacity(0.02)
        }
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Top Row: Category Icon + File Count Badge + Chevron
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(iconBackground)
                            .frame(width: 32, height: 32)

                        Image(systemName: category.systemIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(accentColor)
                            .scaleEffect(isCardHovered ? 1.10 : 1.0)
                    }

                    Spacer()

                    // File Count Badge Pill
                    Text(formattedCount)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                        )
                        .foregroundColor(isSelected ? accentColor : .secondary)

                    // Drill-Down Chevron
                    Button(action: onDrillDown) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isSelected ? accentColor : .secondary.opacity(isCardHovered ? 0.9 : 0.4))
                            .offset(x: isCardHovered ? 2 : 0)
                    }
                    .buttonStyle(.plain)
                    .help("Inspect \(category.rawValue) files")
                }

                // Middle: Category Name
                Text(category.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Bottom Row: Primary Size & Percentage Share
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedSize)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    if percentage > 0.05 {
                        Text(String(format: "%.1f%%", percentage))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    } else if byteCount > 0 {
                        Text("<0.1%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Empty")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(
                color: cardShadowColor,
                radius: isSelected ? 6 : (isCardHovered ? 4 : 2),
                x: 0,
                y: isSelected ? 3 : (isCardHovered ? 2 : 1)
            )
            .scaleEffect(isCardHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isCardHovered)
            .animation(.easeInOut(duration: 0.18), value: isBarHovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(StorageCardButtonStyle())
        .onHover { hovering in
            isCardHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .contextMenu {
            Button("Inspect Files in \(category.rawValue)") {
                onDrillDown()
            }
            Button(isSelected ? "Clear Filter" : "Filter by \(category.rawValue)") {
                onSelect()
            }
        }
    }
}

// MARK: - Dynamic Segmented Progress Bar (Feature F6)

public enum StorageBarMode: String, CaseIterable, Identifiable {
    case fullDisk = "Entire APFS Disk"
    case scannedOnly = "Scanned Files"

    public var id: String { rawValue }
}

public struct StorageBarSegmentItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let bytes: Int64
    public let color: Color
    public let icon: String
    public let category: FileCategory?
    public let isSystemOrOther: Bool
    public let isFreeSpace: Bool

    public var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public init(
        id: String,
        title: String,
        subtitle: String,
        bytes: Int64,
        color: Color,
        icon: String,
        category: FileCategory?,
        isSystemOrOther: Bool = false,
        isFreeSpace: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.bytes = bytes
        self.color = color
        self.icon = icon
        self.category = category
        self.isSystemOrOther = isSystemOrOther
        self.isFreeSpace = isFreeSpace
    }
}

public struct DynamicStorageProgressBar: View {
    public let overview: StorageOverview
    @Binding public var selectedCategory: FileCategory?
    @Binding public var hoveredCategory: FileCategory?
    public let onSelectCategory: (FileCategory) -> Void
    public let onDrillDown: (FileCategory) -> Void

    @State private var barMode: StorageBarMode = .fullDisk
    @State private var hoveredSegmentId: String? = nil

    public init(
        overview: StorageOverview,
        selectedCategory: Binding<FileCategory?>,
        hoveredCategory: Binding<FileCategory?>,
        onSelectCategory: @escaping (FileCategory) -> Void,
        onDrillDown: @escaping (FileCategory) -> Void
    ) {
        self.overview = overview
        self._selectedCategory = selectedCategory
        self._hoveredCategory = hoveredCategory
        self.onSelectCategory = onSelectCategory
        self.onDrillDown = onDrillDown
    }

    private var segments: [StorageBarSegmentItem] {
        var items: [StorageBarSegmentItem] = []

        // 1. Scanned Categories (sorted by size descending)
        let sortedCategories = FileCategory.allCases.sorted {
            (overview.categorySizes[$0] ?? 0) > (overview.categorySizes[$1] ?? 0)
        }

        for cat in sortedCategories {
            let size = overview.categorySizes[cat] ?? 0
            if size > 0 {
                items.append(
                    StorageBarSegmentItem(
                        id: cat.rawValue,
                        title: cat.rawValue,
                        subtitle: "\(overview.fileCount(for: cat)) files",
                        bytes: size,
                        color: cat.color,
                        icon: cat.systemIcon,
                        category: cat,
                        isSystemOrOther: false,
                        isFreeSpace: false
                    )
                )
            }
        }

        // 2. macOS System & Other Space (in fullDisk mode)
        if barMode == .fullDisk && overview.systemAndOtherBytes > 0 {
            items.append(
                StorageBarSegmentItem(
                    id: "systemAndOther",
                    title: "macOS System & Other",
                    subtitle: "APFS local snapshots, system data & applications",
                    bytes: overview.systemAndOtherBytes,
                    color: Color(nsColor: .systemGray),
                    icon: "apple.logo",
                    category: nil,
                    isSystemOrOther: true,
                    isFreeSpace: false
                )
            )
        }

        // 3. Available Free Space (in fullDisk mode)
        if barMode == .fullDisk && overview.availableCapacity > 0 {
            items.append(
                StorageBarSegmentItem(
                    id: "freeSpace",
                    title: "Available Free Space",
                    subtitle: "APFS purgeable & unallocated space",
                    bytes: overview.availableCapacity,
                    color: Color.green.opacity(0.35),
                    icon: "circle.dashed",
                    category: nil,
                    isSystemOrOther: false,
                    isFreeSpace: true
                )
            )
        }

        return items
    }

    private var totalBaseBytes: Int64 {
        switch barMode {
        case .fullDisk:
            return overview.totalCapacity > 0 ? overview.totalCapacity : 1
        case .scannedOnly:
            return overview.scannedTotalBytes > 0 ? overview.scannedTotalBytes : 1
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header: Metrics & Scale Switcher
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("\(overview.formattedUsed) Used")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(overview.formattedAvailable) Free")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    Text("Total APFS Capacity: \(overview.formattedTotal) (Macintosh HD)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Mode Picker
                Picker("Scale", selection: $barMode.animation(.easeInOut(duration: 0.25))) {
                    ForEach(StorageBarMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            // Real-Time Hover Tooltip / Floating HUD Banner
            if let activeId = hoveredSegmentId, let seg = segments.first(where: { $0.id == activeId }) {
                HStack(spacing: 8) {
                    Image(systemName: seg.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(seg.color)

                    Text(seg.title)
                        .font(.system(size: 12, weight: .bold))

                    Text("—")
                        .foregroundColor(.secondary)

                    Text(seg.formattedBytes)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    let pct = totalBaseBytes > 0 ? (Double(seg.bytes) / Double(totalBaseBytes)) * 100 : 0
                    Text(String(format: "(%.1f%%)", pct))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let cat = seg.category {
                        Text("\(overview.fileCount(for: cat)) files • Click to filter")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text(seg.subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                Color.clear.frame(height: 28)
            }

            // The Segmented Progress Bar
            GeometryReader { geo in
                let widths = computeWidths(for: segments, availableWidth: geo.size.width)

                HStack(spacing: 2) {
                    ForEach(segments) { seg in
                        let width = widths[seg.id] ?? 0
                        let isCatSelected = (seg.category != nil && seg.category == selectedCategory)
                        let isSegHovered = (hoveredSegmentId == seg.id)
                        let isDimmed = (selectedCategory != nil && !isCatSelected && !seg.isFreeSpace)

                        if width > 0 {
                            Button {
                                if let cat = seg.category {
                                    onSelectCategory(cat)
                                }
                            } label: {
                                ZStack {
                                    Rectangle()
                                        .fill(seg.color)
                                        .frame(width: width, height: isSegHovered || isCatSelected ? 22 : 16)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))

                                    if isCatSelected {
                                        RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(Color.white, lineWidth: 2)
                                            .frame(width: width, height: 22)
                                    }
                                }
                                .opacity(isDimmed ? 0.35 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if hovering {
                                        hoveredSegmentId = seg.id
                                        hoveredCategory = seg.category
                                        NSCursor.pointingHand.push()
                                    } else {
                                        if hoveredSegmentId == seg.id {
                                            hoveredSegmentId = nil
                                            hoveredCategory = nil
                                        }
                                        NSCursor.pop()
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(height: 24, alignment: .center)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 24)

            // Segment Legend & Quick Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(segments) { seg in
                        Button {
                            if let cat = seg.category {
                                onSelectCategory(cat)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(seg.color)
                                    .frame(width: 8, height: 8)
                                Text(seg.title)
                                    .font(.system(size: 11, weight: seg.category == selectedCategory ? .bold : .medium))
                                Text(seg.formattedBytes)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(seg.category == selectedCategory ? seg.color.opacity(0.18) : Color.primary.opacity(0.04))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(seg.category == selectedCategory ? seg.color : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
    }

    private func computeWidths(for segments: [StorageBarSegmentItem], availableWidth: CGFloat) -> [String: CGFloat] {
        DynamicStorageProgressBar.computeProportionalWidths(
            segments: segments,
            totalBytes: totalBaseBytes,
            availableWidth: availableWidth
        )
    }

    /// Two-pass proportional width algorithm enforcing a minimum width of at least minWidth (default 8 pt).
    public nonisolated static func computeProportionalWidths(
        segments: [StorageBarSegmentItem],
        totalBytes: Int64,
        availableWidth: CGFloat,
        spacing: CGFloat = 2.0,
        minWidth: CGFloat = 8.0
    ) -> [String: CGFloat] {
        guard totalBytes > 0, availableWidth > 0 else { return [:] }
        let nonZero = segments.filter { $0.bytes > 0 }
        guard !nonZero.isEmpty else { return [:] }

        let totalSpacing = spacing * CGFloat(nonZero.count - 1)
        let usableWidth = max(0, availableWidth - totalSpacing)

        var widths: [String: CGFloat] = [:]
        var smallIds: Set<String> = []
        var smallWidthTotal: CGFloat = 0
        var largeBytesTotal: Int64 = 0

        for seg in nonZero {
            let linearWidth = usableWidth * CGFloat(Double(seg.bytes) / Double(totalBytes))
            if linearWidth < minWidth {
                smallIds.insert(seg.id)
                smallWidthTotal += minWidth
                widths[seg.id] = minWidth
            } else {
                largeBytesTotal += seg.bytes
            }
        }

        let remainingWidth = max(0, usableWidth - smallWidthTotal)
        for seg in nonZero where !smallIds.contains(seg.id) {
            if largeBytesTotal > 0 {
                let share = remainingWidth * CGFloat(Double(seg.bytes) / Double(largeBytesTotal))
                widths[seg.id] = max(minWidth, share)
            } else {
                widths[seg.id] = minWidth
            }
        }

        return widths
    }
}

// MARK: - Main Storage Analyzer View (Features F5, F6, F7, F8, F9)

public struct StorageView: View {
    @ObservedObject private var coordinator = NavigationCoordinator.shared
    @State private var overview: StorageOverview?
    @State private var isLoading: Bool = true

    // Interactive filter and hover synchronization
    @State private var selectedCategory: FileCategory? = nil
    @State private var hoveredCategory: FileCategory? = nil

    // Drill-Down transition trigger (Feature F7)
    @State private var drillDownCategory: FileCategory? = nil

    // Quick Look Preview URL (Feature F9)
    @State private var previewURL: URL? = nil

    public init() {}

    public var body: some View {
        Group {
            if let drillDown = drillDownCategory, let currentOverview = overview {
                CategoryDetailView(
                    category: drillDown,
                    overview: currentOverview,
                    onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            drillDownCategory = nil
                            coordinator.storageDrillDownCategory = nil
                        }
                    },
                    onFilesChanged: { updatedItems in
                        handleCategoryFilesChanged(category: drillDown, items: updatedItems)
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                storageOverviewContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: drillDownCategory)
        .quickLookPreview($previewURL)
        .onAppear {
            if let target = coordinator.storageDrillDownCategory {
                self.drillDownCategory = target
            }
            if overview == nil {
                if let cached = StorageAnalyzer.shared.cachedOverview {
                    self.overview = cached
                } else {
                    loadStorageData()
                }
            }
        }
        .onChange(of: coordinator.storageDrillDownCategory) { _, newCategory in
            if let target = newCategory {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    self.drillDownCategory = target
                }
            }
        }
    }

    // MARK: - Dashboard Content

    private var storageOverviewContent: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Analyzing local storage volumes...")
                Spacer()
            } else if let overview = overview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 1. Dynamic Segmented Storage Bar (Feature F6)
                        DynamicStorageProgressBar(
                            overview: overview,
                            selectedCategory: $selectedCategory,
                            hoveredCategory: $hoveredCategory,
                            onSelectCategory: { cat in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    if selectedCategory == cat {
                                        selectedCategory = nil
                                    } else {
                                        selectedCategory = cat
                                    }
                                }
                            },
                            onDrillDown: { cat in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    drillDownCategory = cat
                                }
                            }
                        )

                        // 2. Storage Category Cards Grid (Feature F5)
                        categoryCardsSection(overview: overview)

                        // 3. File Listing: Filtered Category or Largest Discovered Files (Features F8 & F9)
                        filesListingSection(overview: overview)
                    }
                    .padding(20)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Storage Analyzer")
                    .font(.system(size: 22, weight: .bold))
                Text("Interactive APFS breakdown, category drill-down, and file discovery")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                loadStorageData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
    }

    private func categoryCardsSection(overview: StorageOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Storage by File Category")
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                if selectedCategory != nil {
                    Button("Clear Filter") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedCategory = nil
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 12)],
                spacing: 12
            ) {
                ForEach(FileCategory.allCases) { cat in
                    let size = overview.categorySizes[cat] ?? 0
                    let count = overview.fileCount(for: cat)
                    let pct = overview.scannedTotalBytes > 0
                        ? (Double(size) / Double(overview.scannedTotalBytes)) * 100
                        : 0.0

                    StorageCategoryCardView(
                        category: cat,
                        byteCount: size,
                        fileCount: count,
                        percentage: pct,
                        isSelected: selectedCategory == cat,
                        isBarHovered: hoveredCategory == cat,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if selectedCategory == cat {
                                    selectedCategory = nil
                                } else {
                                    selectedCategory = cat
                                }
                            }
                        },
                        onDrillDown: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                drillDownCategory = cat
                            }
                        }
                    )
                }
            }
        }
    }

    private func filesListingSection(overview: StorageOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let selected = selectedCategory {
                    Text("\(selected.rawValue) Files")
                        .font(.system(size: 14, weight: .bold))
                    Text("(\(overview.fileCount(for: selected)) files discovered)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Open Full Inspection View →") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            drillDownCategory = selected
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.link)
                } else {
                    Text("Largest Discovered Files")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text("Top \(overview.largestFiles.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            let displayedFiles = selectedCategory != nil
                ? overview.files(for: selectedCategory!)
                : overview.largestFiles

            if displayedFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No files discovered in this category")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color.secondary.opacity(0.03))
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(displayedFiles.prefix(25)) { file in
                        ScannedFileRowView(
                            file: file,
                            categoryColor: file.category.color,
                            onQuickLook: { url in
                                self.previewURL = url
                            },
                            onReveal: { url in
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            },
                            onTrash: { trashedItem in
                                handleFileTrashed(trashedItem)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Data Management & Reactive State Updates

    private func loadStorageData() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = StorageAnalyzer.shared.analyzeStorage()
            DispatchQueue.main.async {
                self.overview = res
                self.isLoading = false
                if let target = self.coordinator.storageDrillDownCategory {
                    self.drillDownCategory = target
                }
            }
        }
    }

    private func handleFileTrashed(_ file: ScannedItem) {
        guard let current = overview else { return }
        let updatedLargest = current.largestFiles.filter { $0.id != file.id }
        var updatedCatFiles = current.categoryFiles
        updatedCatFiles[file.category]?.removeAll(where: { $0.id == file.id })
        var updatedSizes = current.categorySizes
        let currentCatSize = updatedSizes[file.category] ?? file.size
        updatedSizes[file.category] = max(0, currentCatSize - file.size)
        let updatedUsed = max(0, current.usedCapacity - file.size)
        let updatedAvailable = current.availableCapacity + file.size

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.overview = StorageOverview(
                totalCapacity: current.totalCapacity,
                availableCapacity: updatedAvailable,
                usedCapacity: updatedUsed,
                categorySizes: updatedSizes,
                categoryFiles: updatedCatFiles,
                largestFiles: updatedLargest,
                reclaimableEstimate: max(0, current.reclaimableEstimate - file.size)
            )
        }
    }

    private func handleCategoryFilesChanged(category: FileCategory, items: [ScannedItem]) {
        guard let current = overview else { return }
        var updatedCatFiles = current.categoryFiles
        updatedCatFiles[category] = items
        var updatedSizes = current.categorySizes
        let newCatSize = items.reduce(0) { $0 + $1.size }
        let diff = (updatedSizes[category] ?? 0) - newCatSize
        updatedSizes[category] = newCatSize
        let updatedUsed = max(0, current.usedCapacity - diff)
        let updatedAvailable = current.availableCapacity + diff
        let remainingIds = Set(items.map(\.id))
        let updatedLargest = current.largestFiles.filter { file in
            if file.category == category {
                return remainingIds.contains(file.id)
            }
            return true
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.overview = StorageOverview(
                totalCapacity: current.totalCapacity,
                availableCapacity: updatedAvailable,
                usedCapacity: updatedUsed,
                categorySizes: updatedSizes,
                categoryFiles: updatedCatFiles,
                largestFiles: updatedLargest,
                reclaimableEstimate: max(0, current.reclaimableEstimate - diff)
            )
        }
    }
}
