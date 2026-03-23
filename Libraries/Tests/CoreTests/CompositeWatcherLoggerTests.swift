import Testing

@testable import Core

@Suite("CompositeWatcherLogger")
struct CompositeWatcherLoggerTests {

    // AC-4.4: all children receive the message
    @Test("forwards info, warning, and error to all children")
    func compositeForwardsToAllChildren() {
        let first = MockWatcherLogger()
        let second = MockWatcherLogger()
        let composite = CompositeWatcherLogger([first, second])

        composite.info("hello")
        composite.warning("world")
        composite.error("boom")

        #expect(first.infos == ["hello"])
        #expect(first.warnings == ["world"])
        #expect(first.errors == ["boom"])

        #expect(second.infos == ["hello"])
        #expect(second.warnings == ["world"])
        #expect(second.errors == ["boom"])
    }

    @Test("works with an empty children array without crashing")
    func emptyChildrenNoOp() {
        let composite = CompositeWatcherLogger([])
        composite.info("msg")
        composite.warning("msg")
        composite.error("msg")
    }
}
