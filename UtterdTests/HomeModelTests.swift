import Testing
@testable import Utterd

@Suite("HomeModel")
struct HomeModelTests {
    @Test("Loading items populates the list")
    @MainActor
    func loadItems() async {
        let model = HomeModel()
        #expect(model.items.isEmpty)

        await model.loadItems()

        #expect(!model.items.isEmpty)
        #expect(!model.isLoading)
    }

    @Test("Loading sets and clears isLoading flag")
    @MainActor
    func loadingFlag() async {
        let model = HomeModel()
        #expect(!model.isLoading)

        await model.loadItems()

        #expect(!model.isLoading)
    }
}
