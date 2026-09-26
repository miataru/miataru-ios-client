import Foundation

struct Installer {
    private let root: URL
    private let dryRun: Bool
    private let begin = "# BEGIN SwiftProjectGraph"
    private let end = "# END SwiftProjectGraph"

    init(root: URL, dryRun: Bool) { self.root = root; self.dryRun = dryRun }

    func run(command: String, codex: Bool, agentsPath: String?) throws {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else {
            throw ToolError.configuration("Project root must be a Git repository: \(root.path)")
        }
        let tool = root.appendingPathComponent("tools/SwiftProjectGraph")
        guard FileManager.default.fileExists(atPath: tool.appendingPathComponent("run.sh").path) else {
            throw ToolError.configuration("Copy tools/SwiftProjectGraph into the target repository first.")
        }
        if command == "uninstall" { try uninstall(agentsPath: agentsPath); return }
        let project = tool.appendingPathComponent("project.json")
        if !FileManager.default.fileExists(atPath: project.path) {
            try write(discoveredConfiguration(), to: project)
        } else { report("keep", project) }
        if codex { try installCodex() }
        if let agentsPath { try installAgentRule(path: agentsPath) }
        report(dryRun ? "dry-run complete" : "installed", tool)
    }

    private func installCodex() throws {
        let codex = root.appendingPathComponent(".codex")
        let config = codex.appendingPathComponent("config.toml")
        let block = """
        \(begin)
        [mcp_servers.swift_project_graph]
        command = "./tools/SwiftProjectGraph/run.sh"
        args = ["mcp"]
        cwd = "."
        enabled = true
        required = false
        startup_timeout_sec = 30
        tool_timeout_sec = 120
        default_tools_approval_mode = "auto"
        \(end)
        """
        try replaceMarkedBlock(at: config, block: block)

        let hooksURL = codex.appendingPathComponent("hooks.json")
        var object = (try? Data(contentsOf: hooksURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        hooks["SessionStart"] = removingGraphHooks(from: hooks["SessionStart"])
        let command = "python3 \"$(git rev-parse --show-toplevel)/scripts/project-graph-post-patch.py\""
        hooks["PostToolUse"] = mergedHook(existing: hooks["PostToolUse"], matcher: "apply_patch|Edit|Write", command: command)
        object["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try write(data, to: hooksURL)
    }

    private func installAgentRule(path: String) throws {
        let url = try contained(path)
        let block = """
        \(begin)
        ## Local project graph

        - Before broad source inspection, use `swift_graph_context` with a focused task query.
        - Use the graph for ambiguous behavior, signature-only APIs, semantic or multi-hop dependencies, architecture orientation, tests, and blast-radius analysis.
        - Use `swift_graph_file_api` for APIs, filtered `swift_graph_trace` for dependencies, and `swift_graph_impact` for blast radius.
        - Do not use `swift_graph_context` or `swift_graph_find_all` for one known literal, exact symbol spelling, or simple single-file occurrence search; targeted `rg` is faster and usually smaller. Use graph search when ranking, document status, grouping, or cross-file relationships add value.
        - Treat syntax-only, inferred, and stale-semantic edges as navigation hints: overloads, dynamic dispatch, reflection, generated code, and common short names can remain ambiguous. Prefer `semantic` confidence after a compatible build and confirm behavior in source before editing.
        - Prefer symbol targets over whole-file targets for `swift_graph_impact`; file impact is intentionally broader.
        - Keep context queries centered on one primary entity or behavior. Apply relationship, path, and status filters before increasing result limits or token budgets.
        - If MCP is unavailable, call the matching command through `tools/SwiftProjectGraph/run.sh`.
        - Graph data is a navigation and analysis aid; source code, project files, and repository source-of-truth rules remain authoritative.
        - Never load the complete graph database or large JSON dumps into model context. Queries fail closed when fingerprints are stale; refresh through the post-patch evaluator, selected verification, or the commit process before Current-behavior claims.
        - Update `tools/SwiftProjectGraph/project.json` when targets, architecture paths, document status, or verification commands change.
        - After a successful build/test verification and before a planned commit, run `tools/SwiftProjectGraph/run.sh enrich`, then confirm the resulting syntax/semantic state with `tools/SwiftProjectGraph/run.sh doctor`. Enrich only after the build that is meant to validate the change.
        - When versioned benchmark cases exist, run `tools/SwiftProjectGraph/run.sh benchmark-suite` after changing graph ranking, compression, relationships, refresh behavior, or output contracts.
        \(end)
        """
        try replaceMarkedBlock(at: url, block: block)
    }

    private func uninstall(agentsPath: String?) throws {
        try removeMarkedBlock(at: root.appendingPathComponent(".codex/config.toml"))
        if let agentsPath { try removeMarkedBlock(at: try contained(agentsPath)) }
        let hooksURL = root.appendingPathComponent(".codex/hooks.json")
        if let data = try? Data(contentsOf: hooksURL), var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = object["hooks"] as? [String: Any] {
            for event in ["SessionStart", "PostToolUse"] {
                hooks[event] = removingGraphHooks(from: hooks[event])
            }
            object["hooks"] = hooks
            try write(try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), to: hooksURL)
        }
        report(dryRun ? "would uninstall integration" : "uninstalled integration", root)
    }

    private func discoveredConfiguration() throws -> Data {
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])?.allObjects as? [URL]) ?? []
        let relative: (URL) -> String = { String($0.path.dropFirst(root.path.count + 1)) }
        let excluded = [".build", "DerivedData", "node_modules", "graph", "xcuserdata"]
        func acceptable(_ url: URL) -> Bool { !relative(url).split(separator: "/").contains { excluded.contains(String($0)) } }
        let projects = files.filter { $0.pathExtension == "xcodeproj" && acceptable($0) }.map { relative($0.appendingPathComponent("project.pbxproj")) }.sorted()
        let packages = files.filter { $0.lastPathComponent == "Package.swift" && acceptable($0) }.map(relative).sorted()
        var sources = files.filter { $0.lastPathComponent == "Sources" && acceptable($0) }.map(relative)
        var tests = files.filter { $0.lastPathComponent == "Tests" && acceptable($0) }.map(relative)
        if sources.isEmpty, files.contains(where: { $0.pathExtension == "swift" }) {
            let topSwift = Set(files.filter { $0.pathExtension == "swift" && acceptable($0) }.compactMap { relative($0).split(separator: "/").first.map(String.init) })
            sources = topSwift.filter { !$0.localizedCaseInsensitiveContains("test") }.sorted()
            tests = topSwift.filter { $0.localizedCaseInsensitiveContains("test") }.sorted()
        }
        let docs = ["README.md", "Documentation", "documentation", "docs"].filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        let scripts = ["scripts", "Scripts"].filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        let name = root.lastPathComponent
        let object: [String: Any] = [
            "schemaVersion": 1, "projectName": name, "projectID": "local.\(stableHash(Data(root.path.utf8)))",
            "sourceRoots": Array(Set(sources)).sorted(), "testRoots": Array(Set(tests)).sorted(),
            "documentRoots": docs, "scriptRoots": scripts, "excludePathComponents": excluded,
            "includeGlobs": ["**/*.swift", "**/*.c", "**/*.h", "**/*.md", "**/*.json", "**/*.yml", "**/*.yaml", "**/*.sh"], "excludeGlobs": [],
            "xcodeProjects": projects, "schemes": [], "packages": packages,
            "testPlans": [], "testTargets": [], "indexStorePaths": [],
            "verificationCommands": [], "documentRules": [], "subsystems": [], "architectureFlows": [], "searchSynonyms": [:]
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func mergedHook(existing: Any?, matcher: String, command: String) -> [[String: Any]] {
        var entries = removingGraphHooks(from: existing)
        entries.append(["matcher": matcher, "hooks": [["type": "command", "command": command, "timeout": 120]]])
        return entries
    }
    private func removingGraphHooks(from existing: Any?) -> [[String: Any]] {
        let entries = existing as? [[String: Any]] ?? []
        return entries.filter {
            !(($0["hooks"] as? [[String: Any]]) ?? []).contains {
                let command = ($0["command"] as? String) ?? ""
                return command.contains("SwiftProjectGraph")
                    || command.contains("project-graph-post-patch.py")
            }
        }
    }

    private func replaceMarkedBlock(at url: URL, block: String) throws {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stripped = stripBlock(existing).trimmingCharacters(in: .whitespacesAndNewlines)
        let output = stripped.isEmpty ? block + "\n" : stripped + "\n\n" + block + "\n"
        try write(Data(output.utf8), to: url)
    }
    private func removeMarkedBlock(at url: URL) throws {
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else { return }
        try write(Data((stripBlock(existing).trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8), to: url)
    }
    private func stripBlock(_ text: String) -> String {
        guard let start = text.range(of: begin), let finish = text.range(of: end, range: start.upperBound..<text.endIndex) else { return text }
        var output = text; output.removeSubrange(start.lowerBound..<finish.upperBound); return output
    }
    private func contained(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { throw ToolError.pathOutsideRoot(path) }
        return url
    }
    private func write(_ data: Data, to url: URL) throws {
        report(dryRun ? "would write" : "write", url)
        guard !dryRun else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private func report(_ action: String, _ url: URL) { print("\(action): \(url.path)") }
}
