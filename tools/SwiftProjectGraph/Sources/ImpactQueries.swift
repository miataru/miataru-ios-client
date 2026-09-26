import Foundation
import SQLite3

extension GraphDatabase {
    func impact(_ target: String, config: ProjectConfig, root: URL) throws -> String {
        if target == "git-diff" { return try impactGitDiff(root: root, config: config) }
        let targetIDs = try impactTargetIDs(target)
        guard !targetIDs.isEmpty else { return "No symbol or file matched `\(target)`." }
        let rows = try externalImpactRows(targetIDs: targetIDs)
        return renderImpact(title: "impact target=\(target)", rows: rows, config: config)
    }

    func impactJSON(targets: [String], config: ProjectConfig, root: URL) throws -> String {
        let resolvedTargets: [String]
        if targets == ["git-diff"] {
            resolvedTargets = try changedPaths(root: root)
        } else {
            resolvedTargets = targets
        }
        var rows = [ImpactRow]()
        for target in resolvedTargets {
            rows += try externalImpactRows(targetIDs: impactTargetIDs(target))
        }
        // Machine-readable selection is intentionally stricter than the human
        // impact view: syntax/name collisions are useful navigation hints but
        // are too broad to start tests automatically.
        let accepted = rows.filter { $0.kind != "documented_by" && $0.confidence == "semantic" }
        let report = ImpactReport(
            schemaVersion: 1,
            targets: resolvedTargets,
            tests: reportRows(accepted.filter { isTestPath($0.path, config: config) }),
            consumers: reportRows(accepted.filter { !isTestPath($0.path, config: config) && !$0.path.lowercased().hasSuffix(".md") })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    private func externalImpactRows(targetIDs: [String]) throws -> [ImpactRow] {
        var rows = [ImpactRow](), seen = Set<String>()
        for targetID in targetIDs {
            let statement = try prepare("""
            SELECT source.file,source.line,source.qualified_name,e.kind,e.confidence,target.file
            FROM edges e JOIN symbols source ON source.id=e.from_id JOIN symbols target ON target.id=e.to_id
            WHERE e.to_id=? AND source.file!=target.file
              AND e.kind NOT IN ('contains','imports')
            ORDER BY CASE e.confidence WHEN 'semantic' THEN 0 WHEN 'inferred' THEN 1 ELSE 2 END,
                     CASE e.kind WHEN 'constructs' THEN 0 WHEN 'calls' THEN 1 WHEN 'implements' THEN 2 WHEN 'references' THEN 3 ELSE 4 END
            """)
            bind(statement, [targetID])
            while sqlite3_step(statement) == SQLITE_ROW {
                let row = ImpactRow(path: text(statement, 0), line: Int(sqlite3_column_int(statement, 1)),
                                    symbol: text(statement, 2), kind: text(statement, 3), confidence: text(statement, 4))
                let key = "\(row.path):\(row.line):\(row.symbol)"
                if seen.insert(key).inserted { rows.append(row) }
            }
            sqlite3_finalize(statement)
        }
        return rows
    }

    private func renderImpact(title: String, rows: [ImpactRow], config: ProjectConfig) -> String {
        let tests = rows.filter { $0.path.localizedCaseInsensitiveContains("test") }
        let documents = rows.filter { $0.path.lowercased().hasSuffix(".md") }
        let consumers = rows.filter { !tests.contains($0) && !documents.contains($0) }
        var lines = [title]
        appendImpactSection("Direct consumers", rows: consumers, limit: 25, to: &lines)
        appendImpactSection("Tests", rows: tests, limit: 20, to: &lines)
        appendImpactSection("Documents", rows: documents, limit: 15, to: &lines)
        lines.append("Verification")
        lines += config.verificationCommands.map { "- \($0)" }
        return lines.joined(separator: "\n")
    }

    private func appendImpactSection(_ name: String, rows: [ImpactRow], limit: Int, to lines: inout [String]) {
        lines.append(name)
        if rows.isEmpty { lines.append("- none indexed") }
        lines += rows.prefix(limit).map { "- \($0.path):\($0.line) \($0.symbol) [\($0.kind),\($0.confidence)]" }
        if rows.count > limit { lines.append("… omitted=\(rows.count - limit)") }
    }

    private func impactTargetIDs(_ target: String) throws -> [String] {
        let statement = try prepare("""
        SELECT DISTINCT id FROM symbols WHERE name=? OR qualified_name=? OR file=? LIMIT 2000
        """)
        defer { sqlite3_finalize(statement) }; bind(statement, [target, target, target])
        var ids = [String]()
        while sqlite3_step(statement) == SQLITE_ROW { ids.append(text(statement, 0)) }
        return ids
    }

    private func impactGitDiff(root: URL, config: ProjectConfig) throws -> String {
        let paths = try changedPaths(root: root)
        if paths.isEmpty { return "impact git-diff: no changed files" }
        var rows = [ImpactRow]()
        for path in paths { rows += try externalImpactRows(targetIDs: impactTargetIDs(path)) }
        return renderImpact(title: "impact git-diff changed=\(paths.count)\n" + paths.map { "- \($0)" }.joined(separator: "\n"), rows: rows, config: config)
    }

    private func changedPaths(root: URL) throws -> [String] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "status", "--porcelain=v1"]
        process.standardOutput = pipe; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ToolError.database("Cannot read Git diff for impact analysis.") }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .components(separatedBy: .newlines).filter { !$0.isEmpty }.map {
                String($0.dropFirst(min(3, $0.count))).components(separatedBy: " -> ").last ?? ""
            }.filter { !$0.isEmpty }
    }

    private func isTestPath(_ path: String, config: ProjectConfig) -> Bool {
        config.testRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func reportRows(_ rows: [ImpactRow]) -> [ImpactReportRow] {
        var seen = Set<String>()
        return rows.compactMap {
            let key = "\($0.path):\($0.line):\($0.symbol):\($0.kind):\($0.confidence)"
            guard seen.insert(key).inserted else { return nil }
            return ImpactReportRow(path: $0.path, line: $0.line, symbol: $0.symbol, kind: $0.kind, confidence: $0.confidence)
        }.sorted {
            ($0.path, $0.line, $0.symbol) < ($1.path, $1.line, $1.symbol)
        }
    }
}

private struct ImpactRow: Hashable {
    let path: String
    let line: Int
    let symbol: String
    let kind: String
    let confidence: String
}

private struct ImpactReport: Codable {
    let schemaVersion: Int
    let targets: [String]
    let tests: [ImpactReportRow]
    let consumers: [ImpactReportRow]
}

private struct ImpactReportRow: Codable {
    let path: String
    let line: Int
    let symbol: String
    let kind: String
    let confidence: String
}
