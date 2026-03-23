import Foundation
import Observation

@Observable
@MainActor
final class HomeModel {
    var items: [String] = []
    var isLoading = false

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        // TODO: Replace with actual data loading
        try? await Task.sleep(for: .milliseconds(500))
        items = ["Item 1", "Item 2", "Item 3"]
    }
}
