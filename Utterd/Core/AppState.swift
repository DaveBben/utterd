import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isLoading = false
    var errorMessage: String?

    func clearError() {
        errorMessage = nil
    }
}
