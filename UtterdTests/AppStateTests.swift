import Foundation
import Testing
@testable import Utterd

@Suite("AppState")
struct AppStateTests {
    @Test("permissionResolved defaults to false")
    @MainActor
    func permissionResolvedDefault() {
        let state = AppState()

        #expect(state.permissionResolved == false)
    }

    @Test("lastProcessedDate defaults to nil")
    @MainActor
    func lastProcessedDateDefaultsToNil() {
        let state = AppState()

        #expect(state.lastProcessedDate == nil)
    }

    @Test("lastProcessedDate stores the assigned value")
    @MainActor
    func lastProcessedDateStoresValue() {
        let state = AppState()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        state.lastProcessedDate = date

        #expect(state.lastProcessedDate == date)
    }
}
