/// Thread-safe container for mutable test state shared across actor boundaries.
actor ActorBox<T: Sendable> {
    private var value: T

    init(_ initial: T) {
        value = initial
    }

    func get() -> T { value }

    func set(_ newValue: T) {
        value = newValue
    }
}

extension ActorBox where T == Int {
    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

extension ActorBox where T: RangeReplaceableCollection, T.Element: Sendable {
    func append(_ element: T.Element) {
        value.append(element)
    }
}
