import Testing
@testable import Core

@MainActor
struct FolderHierarchyBuilderTests {

    // MARK: - Flat hierarchy

    @Test
    func flatHierarchyReturnsSortedTopLevelPaths() async throws {
        let finance = NotesFolder(id: "1", name: "finance")
        let personal = NotesFolder(id: "2", name: "personal")
        let work = NotesFolder(id: "3", name: "work")

        let mock = MockNotesService()
        mock.listFoldersByParent = [
            nil: [finance, personal, work],
            "1": [],
            "2": [],
            "3": [],
        ]

        let result = try await buildFolderHierarchy(using: mock)

        #expect(result.map(\.path) == ["finance", "personal", "work"])
    }

    // MARK: - Nested hierarchy

    @Test
    func nestedHierarchyReturnsDotNotationPaths() async throws {
        let finance = NotesFolder(id: "f", name: "finance")
        let home = NotesFolder(id: "fh", name: "home")
        let taxes = NotesFolder(id: "ft", name: "taxes")
        let personal = NotesFolder(id: "p", name: "personal")
        let health = NotesFolder(id: "ph", name: "health")

        let mock = MockNotesService()
        mock.listFoldersByParent = [
            nil: [finance, personal],
            "f": [home, taxes],
            "fh": [],
            "ft": [],
            "p": [health],
            "ph": [],
        ]

        let result = try await buildFolderHierarchy(using: mock)

        #expect(result.map(\.path) == ["finance", "finance.home", "finance.taxes", "personal", "personal.health"])
    }

    // MARK: - Deep nesting (3+ levels)

    @Test
    func deeplyNestedHierarchyUsesDotNotationAtAnyDepth() async throws {
        let work = NotesFolder(id: "w", name: "work")
        let projects = NotesFolder(id: "wp", name: "projects")
        let utterd = NotesFolder(id: "wpu", name: "utterd")

        let mock = MockNotesService()
        mock.listFoldersByParent = [
            nil: [work],
            "w": [projects],
            "wp": [utterd],
            "wpu": [],
        ]

        let result = try await buildFolderHierarchy(using: mock)

        #expect(result.map(\.path) == ["work", "work.projects", "work.projects.utterd"])
    }

    // MARK: - Empty

    @Test
    func emptyTopLevelFoldersReturnsEmptyArray() async throws {
        let mock = MockNotesService()
        mock.listFoldersByParent = [nil: []]

        let result = try await buildFolderHierarchy(using: mock)

        #expect(result.isEmpty)
    }

    // MARK: - Sort order

    @Test
    func resultIsSortedAlphabeticallyRegardlessOfServiceOrder() async throws {
        let personal = NotesFolder(id: "p", name: "personal")
        let finance = NotesFolder(id: "f", name: "finance")

        let mock = MockNotesService()
        // Service returns personal first, finance second
        mock.listFoldersByParent = [
            nil: [personal, finance],
            "p": [],
            "f": [],
        ]

        let result = try await buildFolderHierarchy(using: mock)

        #expect(result.map(\.path) == ["finance", "personal"])
    }

    // MARK: - Folder identity in results

    @Test
    func resultContainsCorrectFolderReferences() async throws {
        let finance = NotesFolder(id: "f", name: "finance")
        let home = NotesFolder(id: "fh", name: "home")

        let mock = MockNotesService()
        mock.listFoldersByParent = [
            nil: [finance],
            "f": [home],
            "fh": [],
        ]

        let result = try await buildFolderHierarchy(using: mock)

        let financeEntry = try #require(result.first { $0.path == "finance" })
        let homeEntry = try #require(result.first { $0.path == "finance.home" })
        #expect(financeEntry.folder == finance)
        #expect(homeEntry.folder == home)
    }
}
