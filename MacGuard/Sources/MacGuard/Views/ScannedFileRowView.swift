import SwiftUI
import AppKit
import QuickLook

/// Reusable file row component with action buttons for Quick Look, Inspect Metadata, Reveal in Finder, and Move to Trash.
public struct ScannedFileRowView: View {
    public let file: ScannedItem
    public var categoryColor: Color
    public var isSelected: Bool
    public var showCheckbox: Bool
    public var showCategoryIcon: Bool
    public var showPath: Bool
    public var showDate: Bool

    // Action Callbacks
    public var onSelect: (() -> Void)?
    public var onQuickLook: ((URL) -> Void)?
    public var onReveal: ((URL) -> Void)?
    public var onTrash: ((ScannedItem) -> Void)?

    // Internal State
    @State private var isHovered: Bool = false
    @State private var showMetadataPopover: Bool = false
    @State private var showTrashConfirmation: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false

    public init(
        file: ScannedItem,
        categoryColor: Color = .blue,
        isSelected: Bool = false,
        showCheckbox: Bool = false,
        showCategoryIcon: Bool = true,
        showPath: Bool = true,
        showDate: Bool = false,
        onSelect: (() -> Void)? = nil,
        onQuickLook: ((URL) -> Void)? = nil,
        onReveal: ((URL) -> Void)? = nil,
        onTrash: ((ScannedItem) -> Void)? = nil
    ) {
        self.file = file
        self.categoryColor = categoryColor
        self.isSelected = isSelected
        self.showCheckbox = showCheckbox
        self.showCategoryIcon = showCategoryIcon
        self.showPath = showPath
        self.showDate = showDate
        self.onSelect = onSelect
        self.onQuickLook = onQuickLook
        self.onReveal = onReveal
        self.onTrash = onTrash
    }

    /// Convenience initializer using `item` parameter naming
    public init(
        item: ScannedItem,
        categoryColor: Color = .blue,
        isSelected: Bool = false,
        showCheckbox: Bool = false,
        showCategoryIcon: Bool = true,
        showPath: Bool = true,
        showDate: Bool = false,
        onSelect: (() -> Void)? = nil,
        onQuickLook: ((URL) -> Void)? = nil,
        onReveal: ((URL) -> Void)? = nil,
        onTrash: ((ScannedItem) -> Void)? = nil
    ) {
        self.init(
            file: item,
            categoryColor: categoryColor,
            isSelected: isSelected,
            showCheckbox: showCheckbox,
            showCategoryIcon: showCategoryIcon,
            showPath: showPath,
            showDate: showDate,
            onSelect: onSelect,
            onQuickLook: onQuickLook,
            onReveal: onReveal,
            onTrash: onTrash
        )
    }

    /// Convenience initializer supporting legacy `onItemTrashed` parameter naming
    public init(
        item: ScannedItem,
        categoryColor: Color = .blue,
        onQuickLook: ((URL) -> Void)? = nil,
        onItemTrashed: (() -> Void)? = nil
    ) {
        self.init(
            file: item,
            categoryColor: categoryColor,
            onQuickLook: onQuickLook,
            onTrash: { _ in onItemTrashed?() }
        )
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Optional Multi-Select Checkbox
            if showCheckbox {
                Button {
                    onSelect?()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.6))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            // Category Icon Badge or System Icon
            if showCategoryIcon {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 28, height: 28)

                    Image(systemName: file.category.systemIcon)
                        .foregroundColor(categoryColor)
                        .font(.system(size: 13, weight: .semibold))
                }
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            }

            // File Name and Path / Date Info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if showPath {
                    Text(file.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if showDate {
                    Text(file.modificationDate, style: .date)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Formatted File Size
            Text(file.formattedSize)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.trailing, 4)

            // Action Button Strip
            HStack(spacing: 4) {
                // Action 1: Quick Look
                Button {
                    onQuickLook?(file.url)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Quick Look Preview (Space)")

                // Action 2: Inspect Metadata
                Button {
                    showMetadataPopover = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Inspect Metadata")
                .popover(isPresented: $showMetadataPopover, arrowEdge: .trailing) {
                    FileMetadataPopoverView(file: file)
                }

                // Action 3: Reveal in Finder
                Button {
                    if let onReveal = onReveal {
                        onReveal(file.url)
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder (⌘R)")

                // Action 4: Move to Trash (Confirmation Required per R3)
                Button {
                    showTrashConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(isHovered ? .red.opacity(0.85) : .secondary)
                        .frame(width: 24, height: 24)
                        .background(isHovered ? Color.red.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Move to Trash")
            }
            .opacity(isHovered || isSelected ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.03)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                self.isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            onQuickLook?(file.url)
        }
        .onTapGesture(count: 1) {
            if showCheckbox {
                onSelect?()
            }
        }
        .contextMenu {
            Button {
                onQuickLook?(file.url)
            } label: {
                Label("Quick Look", systemImage: "eye")
            }

            Button {
                if let onReveal = onReveal {
                    onReveal(file.url)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                showMetadataPopover = true
            } label: {
                Label("Inspect Metadata", systemImage: "info.circle")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            } label: {
                Label("Copy Full Path", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                showTrashConfirmation = true
            } label: {
                Label("Move to Trash…", systemImage: "trash")
            }
        }
        // Confirmation Dialog per Requirement R3
        .confirmationDialog(
            "Move \"\(file.name)\" to Trash?",
            isPresented: $showTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                performSafeTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This item (\(file.formattedSize)) will be safely moved to macOS Trash. You can restore it anytime from Approvals & History or macOS Trash.")
        }
        // Error Alert if Trashing Fails
        .alert("File Operation Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred while moving the file to Trash.")
        }
    }

    private func performSafeTrash() {
        do {
            let trashedURL = try SecurityGuard.shared.safelyMoveToTrash(at: file.url, reason: "Storage Analyzer file action")
            RollbackLedger.shared.recordOperation(
                OperationRecord(
                    actionType: .moveToTrash,
                    sourcePath: file.path,
                    destinationPath: trashedURL.path,
                    fileSize: file.size,
                    reason: "User trashed from Storage Analyzer"
                )
            )
            onTrash?(file)
        } catch {
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }
    }
}
