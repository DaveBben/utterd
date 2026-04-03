/// Configuration snapshot for the note-routing pipeline.
/// Read once per `route()` invocation so settings changes take effect on the next memo.
public struct RoutingConfiguration: Sendable, Equatable {

    /// How the LLM is used (or not) during classification.
    public enum LLMApproach: Sendable, Equatable {
        case disabled
        case autoRoute
        case customPrompt(String)
    }

    public var llmApproach: LLMApproach
    public var defaultFolderName: String?
    public var summarizationEnabled: Bool

    public init(
        llmApproach: LLMApproach = .disabled,
        defaultFolderName: String? = nil,
        summarizationEnabled: Bool = false
    ) {
        self.llmApproach = llmApproach
        self.defaultFolderName = defaultFolderName
        self.summarizationEnabled = summarizationEnabled
    }
}
