import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit

/// Observable ViewModel responsible for loading file attributes and computing cryptographic hashes asynchronously.
@MainActor
public final class FileMetadataViewModel: ObservableObject {
    @Published public var name: String
    @Published public var path: String
    @Published public var size: Int64
    @Published public var formattedSize: String
    @Published public var exactByteString: String
    @Published public var creationDate: Date?
    @Published public var modificationDate: Date?
    @Published public var utTypeIdentifier: String
    @Published public var utTypeDescription: String
    @Published public var posixPermissionsOctal: String
    @Published public var posixPermissionsSymbolic: String
    @Published public var owner: String
    @Published public var group: String
    @Published public var sha256: String?
    @Published public var isComputingHash: Bool = false
    @Published public var hashError: String?

    public let fileURL: URL
    private var hashTask: Task<Void, Never>?

    public init(file: ScannedItem) {
        self.fileURL = file.url
        self.name = file.name
        self.path = file.path
        self.size = file.size
        self.formattedSize = file.formattedSize
        self.exactByteString = "\(file.size.formatted()) bytes"
        self.modificationDate = file.modificationDate
        self.utTypeIdentifier = "public.item"
        self.utTypeDescription = "File"
        self.posixPermissionsOctal = "--"
        self.posixPermissionsSymbolic = "----------"
        self.owner = "--"
        self.group = "--"

        loadSynchronousAttributes()
    }

    public init(fileURL: URL, name: String, size: Int64, modificationDate: Date) {
        self.fileURL = fileURL
        self.name = name
        self.path = fileURL.path
        self.size = size
        self.formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        self.exactByteString = "\(size.formatted()) bytes"
        self.modificationDate = modificationDate
        self.utTypeIdentifier = "public.item"
        self.utTypeDescription = "File"
        self.posixPermissionsOctal = "--"
        self.posixPermissionsSymbolic = "----------"
        self.owner = "--"
        self.group = "--"

        loadSynchronousAttributes()
    }

    public func loadSynchronousAttributes() {
        let fileManager = FileManager.default
        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path) {
            if let creation = attrs[.creationDate] as? Date {
                self.creationDate = creation
            }
            if let mod = attrs[.modificationDate] as? Date {
                self.modificationDate = mod
            }
            if let posixNum = (attrs[.posixPermissions] as? NSNumber)?.intValue {
                self.posixPermissionsOctal = String(format: "%04o", posixNum)
                self.posixPermissionsSymbolic = formatSymbolicPermissions(posixNum)
            }
            if let ownerName = attrs[.ownerAccountName] as? String {
                self.owner = ownerName
            }
            if let groupName = attrs[.groupOwnerAccountName] as? String {
                self.group = groupName
            }
        }

        // Uniform Type Identifier
        if let resType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            self.utTypeIdentifier = resType.identifier
            self.utTypeDescription = resType.localizedDescription ?? resType.identifier
        } else if let type = UTType(filenameExtension: fileURL.pathExtension) {
            self.utTypeIdentifier = type.identifier
            self.utTypeDescription = type.localizedDescription ?? type.identifier
        }
    }

    /// Asynchronously streams file contents in 1 MB chunks to calculate SHA-256 without memory spikes.
    public func startAsyncHashComputation() {
        guard sha256 == nil, !isComputingHash else { return }
        isComputingHash = true
        hashError = nil

        hashTask = Task.detached(priority: .userInitiated) { [fileURL] in
            do {
                let handle = try FileHandle(forReadingFrom: fileURL)
                defer { try? handle.close() }

                var hasher = SHA256()
                let bufferSize = 1024 * 1024 // 1 MB buffer

                while true {
                    try Task.checkCancellation()
                    let data = handle.readData(ofLength: bufferSize)
                    if data.isEmpty { break }
                    hasher.update(data: data)
                }

                let digest = hasher.finalize()
                let hashHex = digest.map { String(format: "%02x", $0) }.joined()

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.sha256 = hashHex
                    self.isComputingHash = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    if !(error is CancellationError) {
                        self.hashError = error.localizedDescription
                    }
                    self.isComputingHash = false
                }
            }
        }
    }

    public func cancelHashComputation() {
        hashTask?.cancel()
        hashTask = nil
        isComputingHash = false
    }

    private func formatSymbolicPermissions(_ perm: Int) -> String {
        let chars = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        return chars.map { (mask, char) in (perm & mask) != 0 ? char : "-" }.joined()
    }
}

/// Metadata inspector popover displaying file attributes, POSIX permissions, UTType, and streaming SHA-256 hash.
public struct FileMetadataPopoverView: View {
    @StateObject private var viewModel: FileMetadataViewModel
    @State private var hasCopiedPath: Bool = false
    @State private var hasCopiedHash: Bool = false

    public init(file: ScannedItem) {
        _viewModel = StateObject(wrappedValue: FileMetadataViewModel(file: file))
    }

    public init(fileURL: URL, name: String, size: Int64, modificationDate: Date) {
        _viewModel = StateObject(wrappedValue: FileMetadataViewModel(fileURL: fileURL, name: name, size: size, modificationDate: modificationDate))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: System Icon + File Name + UTType localized description
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: viewModel.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(2)

                    Text(viewModel.utTypeDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Key-Value Attributes
            VStack(spacing: 9) {
                // Location / Full Path
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Location")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(viewModel.path, forType: .string)
                            hasCopiedPath = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                hasCopiedPath = false
                            }
                        } label: {
                            Text(hasCopiedPath ? "Copied!" : "Copy")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(hasCopiedPath ? .green : .accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(viewModel.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Divider()

                // File Size
                metadataRow(label: "Size", value: "\(viewModel.formattedSize) (\(viewModel.exactByteString))")

                // UTType Identifier
                metadataRow(label: "Type ID", value: viewModel.utTypeIdentifier)

                // Timestamps
                if let created = viewModel.creationDate {
                    metadataRow(label: "Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let modified = viewModel.modificationDate {
                    metadataRow(label: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                }

                // POSIX Permissions & Ownership
                metadataRow(label: "Permissions", value: "\(viewModel.posixPermissionsOctal) (\(viewModel.posixPermissionsSymbolic))")
                metadataRow(label: "Owner", value: "\(viewModel.owner):\(viewModel.group)")

                Divider()

                // SHA-256 Cryptographic Hash
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("SHA-256")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if let hash = viewModel.sha256 {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(hash, forType: .string)
                                hasCopiedHash = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    hasCopiedHash = false
                                }
                            } label: {
                                Text(hasCopiedHash ? "Copied!" : "Copy Hash")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(hasCopiedHash ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if viewModel.isComputingHash {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Computing hash (streaming)...")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    } else if let hash = viewModel.sha256 {
                        Text(hash)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    } else if let error = viewModel.hashError {
                        Text("Hash failed: \(error)")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                }
            }

            Divider()

            // Quick Actions: Reveal in Finder
            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([viewModel.fileURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            viewModel.startAsyncHashComputation()
        }
        .onDisappear {
            viewModel.cancelHashComputation()
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .leading)

            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
    }
}
