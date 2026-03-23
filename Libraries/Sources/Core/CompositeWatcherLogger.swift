public struct CompositeWatcherLogger: WatcherLogger {
    private let children: [any WatcherLogger]

    public init(_ children: [any WatcherLogger]) {
        self.children = children
    }

    public func info(_ message: String) {
        children.forEach { $0.info(message) }
    }

    public func warning(_ message: String) {
        children.forEach { $0.warning(message) }
    }

    public func error(_ message: String) {
        children.forEach { $0.error(message) }
    }
}
