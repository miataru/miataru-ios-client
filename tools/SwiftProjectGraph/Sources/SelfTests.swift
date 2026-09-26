import Foundation

enum SelfTests {
    static func run() throws {
        let fixture = """
        import SwiftUI
        /// A generic fixture.
        actor Loader<Value: Sendable>: ObservableObject {
            private var value: Value
            init(value: Value) { self.value = value }
            func load() async throws -> Value { helper(); return value }
            subscript(index: Int) -> Value { value }
        }
        extension Loader: CustomStringConvertible {
            var description: String { "fixture" }
        }
        struct FixtureView: View {
            struct Nested {}
            var body: some View { VStack { Text("Hello") } }
            func overloaded(_ value: Int) {}
            func overloaded(_ value: String) {}
        }
        #if DEBUG
        enum Conditional { case enabled }
        #endif
        func +++ (lhs: Int, rhs: Int) -> Int { lhs + rhs }
        """
        let parsed = SourceAnalyzer.parseSwift(path: "Sources/Fixture.swift", data: Data(fixture.utf8), status: "Current")
        try expect(parsed.imports == ["SwiftUI"], "imports")
        try expect(parsed.symbols.contains { $0.kind == "actor" && $0.name == "Loader" }, "actor")
        try expect(parsed.symbols.contains { $0.kind == "extension" }, "extension")
        try expect(parsed.symbols.contains { $0.kind == "subscript" }, "subscript")
        try expect(parsed.symbols.contains { $0.name == "+++" }, "operator")
        try expect(parsed.symbols.contains { $0.qualifiedName == "FixtureView.Nested" }, "nested type")
        try expect(parsed.symbols.filter { $0.name == "overloaded" }.count == 2, "overloads")
        try expect(parsed.symbols.contains { $0.name == "Conditional" }, "conditional compilation")
        try expect(parsed.symbols.first { $0.name == "Loader" }?.documentation == "A generic fixture.", "doc comment")
        try expect(parsed.edges.contains { $0.kind == "calls" && $0.toName == "helper" }, "call")
        try expect(parsed.edges.contains { $0.kind == "constructs" && $0.toName == "VStack" }, "SwiftUI construction")

        let incomplete = SourceAnalyzer.parseSwift(path: "Broken.swift", data: Data("struct Broken { func work(".utf8), status: "Current")
        try expect(incomplete.symbols.contains { $0.name == "Broken" }, "incomplete Swift")
        try searchAndFilterFixtures()
        print("PASS SwiftProjectGraph parser and query fixtures")
    }

    private static func searchAndFilterFixtures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swift-project-graph-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Tests"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tools/SwiftProjectGraph/graph"), withIntermediateDirectories: true)
        try Data("protocol Storing { func load() }\nfinal class SampleStore: Storing { init(value: Int) {}\nfunc load() {} }".utf8).write(to: root.appendingPathComponent("Sources/SampleStore.swift"))
        try Data("func makeStore() { _ = SampleStore(value: 1) }".utf8).write(to: root.appendingPathComponent("Tests/SampleStoreTests.swift"))
        try Data("# Release signing gate\nSee [Details](DETAILS.md).".utf8).write(to: root.appendingPathComponent("README.md"))
        try Data("# Details".utf8).write(to: root.appendingPathComponent("DETAILS.md"))
        let configuration = """
        {"schemaVersion":1,"projectName":"Fixture","projectID":"fixture","sourceRoots":["Sources"],"testRoots":["Tests"],"documentRoots":[],"scriptRoots":[],"excludePathComponents":["graph"],"xcodeProjects":[],"schemes":[],"packages":[],"verificationCommands":[],"documentRules":[],"subsystems":[],"searchSynonyms":{}}
        """
        let configURL = root.appendingPathComponent("tools/SwiftProjectGraph/project.json")
        try Data(configuration.utf8).write(to: configURL)
        let config = try ProjectConfig.load(from: configURL)
        let database = try GraphDatabase(url: root.appendingPathComponent("tools/SwiftProjectGraph/graph/index.sqlite3"))
        _ = try database.build(root: root, config: config, full: true)
        let indexedPaths = try database.indexedPaths()
        let coverageIssues = try ProjectScanner(root: root, config: config).documentationCoverageIssues(indexedPaths: indexedPaths)
        try expect(indexedPaths.contains("DETAILS.md"), "automatic root documentation")
        try expect(coverageIssues.isEmpty, "documentation coverage")
        let hits = try database.findCode("SampleStore initializer construction tests", limit: 4)
        try expect(hits.first?.kind == "class", "entity-anchored class ranking")
        try expect(hits.prefix(2).contains { $0.kind == "initializer" }, "entity-anchored initializer ranking")
        let trace = try database.trace("SampleStore", direction: "incoming", depth: 1, relationshipKinds: ["constructs"])
        try expect(trace.contains("Tests/SampleStoreTests.swift"), "filtered construction trace")
        let implementation = try database.trace("SampleStore.load", direction: "outgoing", depth: 1, relationshipKinds: ["implements"])
        try expect(implementation.contains("Storing.load"), "protocol implementation edge")
        let impact = try database.impact("SampleStore", config: config, root: root)
        try expect(!impact.contains("SampleStore.load") && impact.contains("Tests"), "external-only impact")
        let impactJSON = try database.impactJSON(targets: ["Sources/SampleStore.swift"], config: config, root: root)
        let impactData = try JSONSerialization.jsonObject(with: Data(impactJSON.utf8)) as? [String: Any]
        let impactTests = impactData?["tests"] as? [[String: Any]]
        try expect(impactData?["schemaVersion"] as? Int == 1 && impactTests?.isEmpty == true, "machine-readable impact filters syntax hints")
        let matches = try database.findAll("SampleStore", pathFilter: "Tests", statusFilter: "Current")
        try expect(matches.contains("Tests/SampleStoreTests.swift") && !matches.contains("Sources/SampleStore.swift"), "path-filtered complete search")
        let freshAfterBuild = try database.isFresh(root: root, config: config)
        try expect(freshAfterBuild, "fresh after explicit build")
        try Data("func makeStore() { _ = SampleStore(value: 2) }".utf8).write(to: root.appendingPathComponent("Tests/SampleStoreTests.swift"))
        let freshAfterEdit = try database.isFresh(root: root, config: config)
        try expect(!freshAfterEdit, "editing does not refresh implicitly")
        _ = try database.build(root: root, config: config, full: false)
        let freshAfterRefresh = try database.isFresh(root: root, config: config)
        try expect(freshAfterRefresh, "explicit incremental build restores freshness")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        if !condition() { throw ToolError.database("Self-test failed: \(name)") }
    }
}
