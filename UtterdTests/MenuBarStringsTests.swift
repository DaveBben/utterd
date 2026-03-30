import Testing
@testable import Utterd

@Suite("MenuBarStrings")
struct MenuBarStringsTests {
    @Test("title is 'Last Voice Memo Synced'")
    func title() {
        #expect(MenuBarStrings.title == "Last Voice Memo Synced")
    }

    @Test("subtitle is 'Yesterday, 1:25 AM'")
    func subtitle() {
        #expect(MenuBarStrings.subtitle == "Yesterday, 1:25 AM")
    }

    @Test("settingsButton is 'Settings...'")
    func settingsButton() {
        #expect(MenuBarStrings.settingsButton == "Settings...")
    }

    @Test("quitButton is 'Quit Utterd'")
    func quitButton() {
        #expect(MenuBarStrings.quitButton == "Quit Utterd")
    }
}
