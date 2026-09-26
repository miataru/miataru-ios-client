import Foundation

@main
enum SwiftProjectGraphMain {
    static func main() {
        do {
            let options = try Options(CommandLine.arguments.dropFirst())
            let selectedRoot = options.value("project-root") ?? options.root
            let root = URL(fileURLWithPath: selectedRoot, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
            if options.command == "install" || options.command == "uninstall" {
                try Installer(root: root, dryRun: options.flag("dry-run")).run(command: options.command,
                    codex: options.flag("codex"), agentsPath: options.value("agents"))
                return
            }
            let tool = root.appendingPathComponent("tools/SwiftProjectGraph")
            let configURL = tool.appendingPathComponent("project.json")
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                throw ToolError.configuration("Missing \(configURL.path). Run `run.sh install` first.")
            }
            let config = try ProjectConfig.load(from: configURL)
            let database = try GraphDatabase(url: tool.appendingPathComponent("graph/index.sqlite3"))
            try run(options, root: root, config: config, database: database)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("swift-project-graph: \(message)\n".utf8))
            switch error {
            case ToolError.usage: exit(64)
            case ToolError.configuration, ToolError.pathOutsideRoot: exit(78)
            case ToolError.stale: exit(3)
            default: exit(1)
            }
        }
    }

    private static func run(_ options: Options, root: URL, config: ProjectConfig, database: GraphDatabase) throws {
        switch options.command {
        case "build", "hook":
            let summary = try database.build(root: root, config: config, full: options.flag("full"))
            if !options.flag("quiet") { printSummary(summary) }
        case "enrich":
            _ = try database.build(root: root, config: config, full: options.flag("full"))
            let semantic = try database.enrich(root: root, config: config)
            _ = try database.build(root: root, config: config, full: false)
            print("semantic=\(semantic)")
        case "check":
            guard try database.isFresh(root: root, config: config) else { throw ToolError.stale }
            if !options.flag("quiet") { print("fresh project=\(config.projectName)") }
        case "doctor":
            let fresh = try database.isFresh(root: root, config: config)
            let counts = try database.rawCounts()
            let coverage = try ProjectScanner(root: root, config: config).documentationCoverageIssues(indexedPaths: database.indexedPaths())
            print("project=\(config.projectName) root=\(root.path) syntax=\(fresh ? "fresh" : "stale") semantic=\(try database.metadataValue("semantic_status") ?? "unavailable") sqlite=ok documentation=\(coverage.isEmpty ? "complete" : "incomplete") files=\(counts.0) symbols=\(counts.1) edges=\(counts.2)")
            coverage.forEach { print("coverage-warning: \($0)") }
            if !fresh { throw ToolError.stale }
        case "query": try checked(root, config, database) { print(renderHits(try $0.findCode(options.requiredArgument(), limit: options.int("limit", 20)))) }
        case "api": try checked(root, config, database) { print(try $0.fileAPI(options.requiredArgument())) }
        case "trace": try checked(root, config, database) {
            let kinds = options.value("relations").map { Set($0.split(separator: ",").map(String.init)) }
            print(try $0.trace(options.requiredArgument(), direction: options.value("direction") ?? "outgoing", depth: options.int("depth", 2), relationshipKinds: kinds))
        }
        case "find-all": try checked(root, config, database) {
            print(try $0.findAll(options.requiredArgument(), limit: options.int("limit", 200), pathFilter: options.value("path"), statusFilter: options.value("status")))
        }
        case "context": try checked(root, config, database) { print(try $0.context(options.requiredArgument(), tokenBudget: options.int("tokens", 3_000), includeSource: options.flag("source"), config: config).text) }
        case "impact": try checked(root, config, database) {
            if options.value("format") == "json" {
                let targets: [String]
                if let encoded = options.value("targets-json") {
                    targets = try JSONDecoder().decode([String].self, from: Data(encoded.utf8))
                } else {
                    targets = [options.flag("git-diff") ? "git-diff" : try options.requiredArgument()]
                }
                print(try $0.impactJSON(targets: targets, config: config, root: root))
            } else {
                print(try $0.impact(options.flag("git-diff") ? "git-diff" : options.requiredArgument(), config: config, root: root))
            }
        }
        case "repo-map": try checked(root, config, database) { print(try $0.repoMap(config: config)) }
        case "benchmark": try benchmark(root: root, config: config, database: database, query: options.argument ?? "playback progress")
        case "mcp": try MCPServer(root: root, config: config, database: database).serve()
        case "test": try SelfTests.run()
        case "help", "--help", "-h": print(Options.help)
        default: throw ToolError.usage("Unknown command `\(options.command)`.\n\(Options.help)")
        }
    }

    private static func checked(_ root: URL, _ config: ProjectConfig, _ database: GraphDatabase, action: (GraphDatabase) throws -> Void) throws {
        guard try database.isFresh(root: root, config: config) else { throw ToolError.stale }
        try action(database)
    }

    private static func renderHits(_ hits: [GraphHit]) -> String {
        hits.isEmpty ? "No matches." : hits.map {
            "\($0.path):\($0.line) [\($0.status)] \($0.kind) \($0.signature.isEmpty ? $0.name : $0.signature)"
        }.joined(separator: "\n")
    }

    private static func benchmark(root: URL, config: ProjectConfig, database: GraphDatabase, query: String) throws {
        let refreshStart = Date(); let summary = try database.build(root: root, config: config, full: false)
        let queryStart = Date(); _ = try database.context(query, tokenBudget: 3_000, config: config)
        print("refresh_ms=\(Int(queryStart.timeIntervalSince(refreshStart) * 1000)) query_ms=\(Int(Date().timeIntervalSince(queryStart) * 1000)) changed=\(summary.changedFiles)")
    }

    private static func printSummary(_ value: BuildSummary) {
        print("updated=\(value.changedFiles) removed=\(value.removedFiles) files=\(value.totalFiles) symbols=\(value.symbols) edges=\(value.edges) semantic=\(value.semanticIndex) ms=\(value.elapsedMilliseconds)")
    }
}

struct Options {
    let root: String
    let command: String
    let argument: String?
    private let flags: Set<String>
    private let values: [String: String]

    init(_ raw: ArraySlice<String>) throws {
        let arguments = Array(raw); var root = FileManager.default.currentDirectoryPath
        var command: String?, positional = [String](), flags = Set<String>(), values = [String: String](), index = 0
        while index < arguments.count {
            let item = arguments[index]
            if item == "--root" {
                guard index + 1 < arguments.count else { throw ToolError.usage("--root requires a path.") }
                root = arguments[index + 1]; index += 2
            } else if item.hasPrefix("--") {
                let key = String(item.dropFirst(2))
                if ["full", "quiet", "codex", "dry-run", "git-diff", "source"].contains(key) { flags.insert(key); index += 1 }
                else {
                    guard index + 1 < arguments.count else { throw ToolError.usage("\(item) requires a value.") }
                    values[key] = arguments[index + 1]; index += 2
                }
            } else if command == nil { command = item; index += 1 }
            else { positional.append(item); index += 1 }
        }
        self.root = root; self.command = command ?? "build"; self.argument = positional.isEmpty ? nil : positional.joined(separator: " ")
        self.flags = flags; self.values = values
    }
    func flag(_ key: String) -> Bool { flags.contains(key) }
    func value(_ key: String) -> String? { values[key] }
    func int(_ key: String, _ fallback: Int) -> Int { values[key].flatMap(Int.init) ?? fallback }
    func requiredArgument() throws -> String { guard let argument, !argument.isEmpty else { throw ToolError.usage("\(command) requires a query or target.") }; return argument }

    static let help = """
    usage: run.sh <command> [query/target] [options]
      build, check, enrich, hook, doctor, install, uninstall
      query, api, trace, find-all, context, impact, repo-map, benchmark
      mcp, test
    install: --project-root PATH [--codex] [--agents AGENTS.md] [--dry-run]
    options: --full --quiet --source --limit N --depth N --direction incoming|outgoing|both --relations calls,constructs --path PATH --status STATUS --tokens N --format json --targets-json JSON
    """
}
