import Testing
@testable import Utterd

@Suite("AppState")
struct AppStateTests {
    @Test("clearError resets errorMessage")
    @MainActor
    func clearError() {
        let state = AppState()
        state.errorMessage = "Something went wrong"

        state.clearError()

        #expect(state.errorMessage == nil)
    }

    @Test("permissionResolved defaults to false")
    @MainActor
    func permissionResolvedDefault() {
        let state = AppState()

        #expect(state.permissionResolved == false)
    }
}
