import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var permissionResolved = false
    var lastProcessedDate: Date? = nil
}
