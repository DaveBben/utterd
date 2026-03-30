import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isLoading = false
    var errorMessage: String?
    var permissionResolved = false

    func clearError() {
        errorMessage = nil
    }
}
