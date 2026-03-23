import SwiftUI

enum Theme {
    static let cornerRadius: CGFloat = 8
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(Theme.padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
