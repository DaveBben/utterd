/// Configuration snapshot for the note-routing pipeline.
/// Read once per `route()` invocation so settings changes take effect on the next memo.
public struct RoutingConfiguration: Sendable, Equatable {

    public var summarizationEnabled: Bool
    public var titleGenerationEnabled: Bool
    public var defaultFolderName: String?
    public var defaultFolderID: String?

    public init(
        summarizationEnabled: Bool = false,
        titleGenerationEnabled: Bool = false,
        defaultFolderName: String? = nil,
        defaultFolderID: String? = nil
    ) {
        self.summarizationEnabled = summarizationEnabled
        self.titleGenerationEnabled = titleGenerationEnabled
        self.defaultFolderName = defaultFolderName
        self.defaultFolderID = defaultFolderID
    }
}
