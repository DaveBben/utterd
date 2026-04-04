import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var errorMessage: String?
    var permissionResolved = false
    var lastProcessedDate: Date? = nil

    func clearError() {
        errorMessage = nil
    }
}
