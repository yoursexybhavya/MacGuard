import SwiftUI
import AppKit

public struct StorageView: View {
    @State private var overview: StorageOverview?
    @State private var isLoading: Bool = true
    @State private var selectedCategory: FileCategory?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Analyzer")
                        .font(.system(size: 22, weight: .bold))
                    Text("Interactive APFS breakdown and largest files discovery")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    loadStorageData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Analyzing local storage volumes...")
                Spacer()
            } else if let overview = overview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Total Storage Banner
                        VStack(spacing: 8) {
                            HStack {
                                Text("\(overview.formattedUsed) Used")
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                                Text("\(overview.formattedAvailable) Available")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.green)
                            }

                            // Visual Stacked Bar
                            GeometryReader { geo in
                                HStack(spacing: 2) {
                                    ForEach(FileCategory.allCases, id: \.self) { cat in
                                        let size = overview.categoryBreakdown[cat] ?? 0
                                        if size > 0 && overview.totalCapacity > 0 {
                                            let width = max(4, geo.size.width * CGFloat(Double(size) / Double(overview.totalCapacity)))
                                            Rectangle()
                                                .fill(categoryColor(for: cat))
                                                .frame(width: width)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .frame(height: 16)

                            Text("Total Capacity: \(overview.formattedTotal) (APFS Macintosh HD)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(12)

                        // Category Pills
                        Text("Storage by File Category")
                            .font(.system(size: 14, weight: .bold))

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(FileCategory.allCases, id: \.self) { cat in
                                let size = overview.categoryBreakdown[cat] ?? 0
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(categoryColor(for: cat).opacity(0.15)).frame(width: 30, height: 30)
                                        Image(systemName: cat.systemIcon)
                                            .foregroundColor(categoryColor(for: cat))
                                            .font(.system(size: 12))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.rawValue)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }

                        // Largest Files Section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Largest Discovered Files")
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                                Text("Top \(overview.largestFiles.count)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            VStack(spacing: 6) {
                                ForEach(overview.largestFiles) { file in
                                    HStack {
                                        Image(systemName: file.category.systemIcon)
                                            .foregroundColor(categoryColor(for: file.category))
                                            .frame(width: 20)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(file.name)
                                                .font(.system(size: 12, weight: .semibold))
                                                .lineLimit(1)
                                            Text(file.path)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }

                                        Spacer()

                                        Text(file.formattedSize)
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.trailing, 8)

                                        Button {
                                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                        } label: {
                                            Image(systemName: "magnifyingglass")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Reveal in Finder")
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.03))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear {
            loadStorageData()
        }
    }

    private func loadStorageData() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = StorageAnalyzer.shared.analyzeStorage()
            DispatchQueue.main.async {
                self.overview = res
                self.isLoading = false
            }
        }
    }

    private func categoryColor(for cat: FileCategory) -> Color {
        switch cat {
        case .installers: return .orange
        case .archives: return .yellow
        case .documents: return .blue
        case .media: return .purple
        case .images: return .pink
        case .code: return .cyan
        case .caches: return .red
        case .other: return .gray
        }
    }
}
