import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            HomeView()
        }
        .navigationTitle("Utterd")
    }
}

struct SidebarView: View {
    var body: some View {
        List {
            NavigationLink("Home", value: "home")
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
