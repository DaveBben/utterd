import SwiftUI

struct HomeView: View {
    @State private var model = HomeModel()

    var body: some View {
        VStack(spacing: 16) {
            if model.isLoading {
                ProgressView("Loading...")
            } else {
                Text("Welcome to Utterd")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Items: \(model.items.count)")
                    .foregroundStyle(.secondary)

                List(model.items, id: \.self) { item in
                    Text(item)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await model.loadItems()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.loadItems() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
