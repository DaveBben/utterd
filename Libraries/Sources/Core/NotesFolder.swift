import Foundation

/// A folder in Apple Notes, identified by a stable `id` property.
/// Two folders are equal if and only if they share the same `id`,
/// regardless of display name — this handles duplicate folder names (AC-01.7).
public struct NotesFolder: Sendable {
    public let id: String
    public let name: String
    /// The ID of the parent container, or `nil` for top-level folders.
    public let containerID: String?

    public init(id: String, name: String, containerID: String? = nil) {
        self.id = id
        self.name = name
        self.containerID = containerID
    }
}

extension NotesFolder: Equatable {
    public static func == (lhs: NotesFolder, rhs: NotesFolder) -> Bool {
        lhs.id == rhs.id
    }
}

extension NotesFolder: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
