import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 450, height: 250)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("showWelcome") private var showWelcome = true

    var body: some View {
        Form {
            Toggle("Show welcome message", isOn: $showWelcome)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
