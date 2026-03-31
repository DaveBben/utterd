import Foundation

/// A discovered folder with its full dot-notation path from the root.
public struct FolderHierarchyEntry: Sendable {
    public let path: String
    public let folder: NotesFolder

    public init(path: String, folder: NotesFolder) {
        self.path = path
        self.folder = folder
    }
}

/// Walks the Notes folder tree via `service` and returns every folder with its
/// full dot-notation path (e.g. "finance.home"), sorted alphabetically by path.
///
/// Errors from `listFolders(in:)` propagate to the caller — no local handling.
public func buildFolderHierarchy(using service: any NotesService) async throws -> [FolderHierarchyEntry] {
    var entries: [FolderHierarchyEntry] = []
    let topLevel = try await service.listFolders(in: nil)
    for folder in topLevel {
        try await collectEntries(for: folder, parentPath: nil, service: service, into: &entries)
    }
    return entries.sorted { $0.path < $1.path }
}

private func collectEntries(
    for folder: NotesFolder,
    parentPath: String?,
    service: any NotesService,
    into entries: inout [FolderHierarchyEntry]
) async throws {
    let path = parentPath.map { "\($0).\(folder.name)" } ?? folder.name
    entries.append(FolderHierarchyEntry(path: path, folder: folder))
    let children = try await service.listFolders(in: folder)
    for child in children {
        try await collectEntries(for: child, parentPath: path, service: service, into: &entries)
    }
}
