import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class GraphDatabase {
    let handle: OpaquePointer

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            throw ToolError.database("Cannot open graph database at \(url.path).")
        }
        handle = database
        try execute("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
        try migrate()
    }

    deinit { sqlite3_close(handle) }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS files(
          path TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, kind TEXT NOT NULL,
          status TEXT NOT NULL, content TEXT NOT NULL, indexed_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS imports(file TEXT NOT NULL, module TEXT NOT NULL,
          PRIMARY KEY(file, module), FOREIGN KEY(file) REFERENCES files(path) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS symbols(
          id TEXT PRIMARY KEY, file TEXT NOT NULL, name TEXT NOT NULL, qualified_name TEXT NOT NULL,
          kind TEXT NOT NULL, signature TEXT NOT NULL, documentation TEXT NOT NULL,
          access TEXT NOT NULL, line INTEGER NOT NULL, end_line INTEGER NOT NULL, parent_id TEXT,
          FOREIGN KEY(file) REFERENCES files(path) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS symbols_name ON symbols(name);
        CREATE INDEX IF NOT EXISTS symbols_qualified_name ON symbols(qualified_name);
        CREATE INDEX IF NOT EXISTS symbols_file ON symbols(file, line);
        CREATE INDEX IF NOT EXISTS symbols_parent ON symbols(parent_id, kind, name);
        CREATE TABLE IF NOT EXISTS edges(
          source_file TEXT NOT NULL, from_id TEXT NOT NULL, to_name TEXT NOT NULL, to_id TEXT,
          kind TEXT NOT NULL, confidence TEXT NOT NULL, line INTEGER NOT NULL,
          FOREIGN KEY(source_file) REFERENCES files(path) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS edges_from ON edges(from_id, kind);
        CREATE INDEX IF NOT EXISTS edges_to ON edges(to_id, to_name, kind);
        CREATE INDEX IF NOT EXISTS edges_kind_confidence ON edges(kind, confidence, from_id, to_id);
        CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(
          path UNINDEXED, name, signature, documentation, content, status UNINDEXED, kind UNINDEXED,
          tokenize='unicode61 remove_diacritics 2 tokenchars _'
        );
        """)
    }

    func build(root: URL, config: ProjectConfig, full: Bool) throws -> BuildSummary {
        let started = Date()
        let scanner = ProjectScanner(root: root, config: config)
        let discovered = try scanner.files()
        let known = try fingerprints()
        let currentPaths = Set(discovered.map { scanner.relative($0.0) })
        let removed = Set(known.keys).subtracting(currentPaths)
        var changed = [(URL, String, String, Data, String)]()

        for (url, kind, status) in discovered {
            let data = try Data(contentsOf: url)
            let fingerprint = stableHash(data)
            let path = scanner.relative(url)
            if full || known[path] != fingerprint {
                changed.append((url, kind, status, data, fingerprint))
            }
        }

        try execute("BEGIN IMMEDIATE")
        do {
            for path in removed { try delete(path: path) }
            for (url, configuredKind, status, data, _) in changed {
                let path = scanner.relative(url)
                try delete(path: path)
                let parsed: ParsedFile
                if url.pathExtension.lowercased() == "swift" {
                    parsed = SourceAnalyzer.parseSwift(path: path, data: data, status: status)
                } else {
                    parsed = SourceAnalyzer.parseText(path: path, data: data, kind: configuredKind, status: status)
                }
                try insert(parsed)
            }
            if !changed.isEmpty || !removed.isEmpty {
                try resolveEdges()
                let codeChanged = changed.contains { $0.0.pathExtension.lowercased() == "swift" }
                    || removed.contains { $0.lowercased().hasSuffix(".swift") }
                let documentsChanged = changed.contains { $0.0.pathExtension.lowercased() == "md" }
                    || removed.contains { $0.lowercased().hasSuffix(".md") }
                try inferDerivedEdges(codeChanged: codeChanged, documentsChanged: documentsChanged || codeChanged)
            }
            let semanticSourcesChanged = changed.contains { $0.0.pathExtension.lowercased() == "swift" }
                || removed.contains { $0.lowercased().hasSuffix(".swift") }
            if semanticSourcesChanged, (try metadataValue("semantic_status"))?.hasPrefix("available") == true {
                try setMetadata("semantic_status", "stale")
            }
            try setMetadata("schema_version", "1")
            try setMetadata("project_id", config.projectID)
            let synonyms = try JSONEncoder().encode(config.searchSynonyms)
            try setMetadata("search_synonyms", String(decoding: synonyms, as: UTF8.self))
            try setMetadata("syntax_indexed_at", ISO8601DateFormatter().string(from: Date()))
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }

        let counts = try countRows()
        let summary = BuildSummary(
            project: config.projectName,
            changedFiles: changed.count,
            removedFiles: removed.count,
            totalFiles: counts.files,
            symbols: counts.symbols,
            edges: counts.edges,
            semanticIndex: try metadataValue("semantic_status") ?? "unavailable",
            elapsedMilliseconds: Int(Date().timeIntervalSince(started) * 1_000)
        )
        try writeArtifacts(root: root, config: config, summary: summary)
        return summary
    }

    func isFresh(root: URL, config: ProjectConfig) throws -> Bool {
        let scanner = ProjectScanner(root: root, config: config)
        let known = try fingerprints()
        let discovered = try scanner.files()
        guard known.count == discovered.count else { return false }
        for (url, _, _) in discovered {
            let path = scanner.relative(url)
            let hash = stableHash(try Data(contentsOf: url))
            if known[path] != hash { return false }
        }
        return true
    }

    private func fingerprints() throws -> [String: String] {
        let statement = try prepare("SELECT path, fingerprint FROM files")
        defer { sqlite3_finalize(statement) }
        var values = [String: String]()
        while sqlite3_step(statement) == SQLITE_ROW {
            values[text(statement, 0)] = text(statement, 1)
        }
        return values
    }

    private func insert(_ file: ParsedFile) throws {
        var statement = try prepare("INSERT INTO files(path,fingerprint,kind,status,content,indexed_at) VALUES(?,?,?,?,?,?)")
        bind(statement, [file.path, file.fingerprint, file.kind, file.status, file.content])
        sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
        try step(statement)
        sqlite3_finalize(statement)

        statement = try prepare("INSERT INTO search(path,name,signature,documentation,content,status,kind) VALUES(?,?,?,?,?,?,?)")
        bind(statement, [file.path, "", "", "", file.content, file.status, file.kind])
        try step(statement)
        sqlite3_finalize(statement)

        for module in file.imports {
            statement = try prepare("INSERT INTO imports(file,module) VALUES(?,?)")
            bind(statement, [file.path, module])
            try step(statement)
            sqlite3_finalize(statement)
        }
        for symbol in file.symbols {
            statement = try prepare("INSERT INTO symbols(id,file,name,qualified_name,kind,signature,documentation,access,line,end_line,parent_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)")
            bind(statement, [symbol.id, symbol.file, symbol.name, symbol.qualifiedName, symbol.kind, symbol.signature,
                             symbol.documentation, symbol.access])
            sqlite3_bind_int(statement, 9, Int32(symbol.line))
            sqlite3_bind_int(statement, 10, Int32(symbol.endLine))
            bindOptional(statement, index: 11, value: symbol.parentID)
            try step(statement)
            sqlite3_finalize(statement)

            statement = try prepare("INSERT INTO search(path,name,signature,documentation,content,status,kind) VALUES(?,?,?,?,?,?,?)")
            bind(statement, [symbol.file, symbol.qualifiedName, symbol.signature, symbol.documentation, "", file.status, symbol.kind])
            try step(statement)
            sqlite3_finalize(statement)
        }
        for edge in file.edges {
            statement = try prepare("INSERT INTO edges(source_file,from_id,to_name,to_id,kind,confidence,line) VALUES(?,?,?,?,?,?,?)")
            bind(statement, [edge.sourceFile, edge.fromID, edge.toName])
            bindOptional(statement, index: 4, value: edge.toID)
            bind(statement, start: 5, values: [edge.kind, edge.confidence])
            sqlite3_bind_int(statement, 7, Int32(edge.line))
            try step(statement)
            sqlite3_finalize(statement)
        }
    }

    private func delete(path: String) throws {
        var statement = try prepare("DELETE FROM search WHERE path = ?")
        bind(statement, [path]); try step(statement); sqlite3_finalize(statement)
        statement = try prepare("DELETE FROM files WHERE path = ?")
        bind(statement, [path]); try step(statement); sqlite3_finalize(statement)
    }

    private func resolveEdges() throws {
        try execute("""
        UPDATE edges SET to_id = NULL
        WHERE to_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM symbols s WHERE s.id = edges.to_id);
        UPDATE edges SET to_id = (
          SELECT s.id FROM symbols s WHERE s.qualified_name = edges.to_name ORDER BY s.id LIMIT 1
        ) WHERE to_id IS NULL AND EXISTS (
          SELECT 1 FROM symbols s WHERE s.qualified_name = edges.to_name
        );
        UPDATE edges SET to_id = (
          SELECT s.id FROM symbols s WHERE s.name = edges.to_name ORDER BY s.id LIMIT 1
        ) WHERE to_id IS NULL AND EXISTS (
          SELECT 1 FROM symbols s WHERE s.name = edges.to_name
        );
        """)
    }

    private func inferDerivedEdges(codeChanged: Bool, documentsChanged: Bool) throws {
        if codeChanged {
            try execute("""
        DELETE FROM edges WHERE confidence='inferred' AND kind IN ('tested_by','implements','calls');
        INSERT INTO edges(source_file,from_id,to_name,to_id,kind,confidence,line)
        SELECT DISTINCT implementation.file,implementation.id,requirement.qualified_name,requirement.id,
                        'implements','inferred',implementation.line
        FROM symbols owner
        JOIN edges conformance ON conformance.from_id=owner.id
        JOIN symbols protocol ON protocol.id=conformance.to_id AND protocol.kind='protocol'
        JOIN symbols implementation ON implementation.parent_id=owner.id
        JOIN symbols requirement ON requirement.parent_id=protocol.id
        WHERE conformance.kind IN ('conforms','inherits')
          AND implementation.kind IN ('function','initializer','var','let','subscript')
          AND requirement.kind=implementation.kind AND requirement.name=implementation.name;
        INSERT INTO edges(source_file,from_id,to_name,to_id,kind,confidence,line)
        SELECT DISTINCT call.source_file,call.from_id,implementation.qualified_name,implementation.id,
                        'calls','inferred',call.line
        FROM edges call
        JOIN edges reference ON reference.from_id=call.from_id AND reference.kind='references'
        JOIN symbols property ON property.id=reference.to_id AND property.kind IN ('let','var')
        JOIN symbols requirement ON requirement.name=call.to_name AND requirement.kind='function'
        JOIN symbols protocol ON protocol.id=requirement.parent_id AND protocol.kind='protocol'
        JOIN edges implementation_edge ON implementation_edge.to_id=requirement.id AND implementation_edge.kind='implements'
        JOIN symbols implementation ON implementation.id=implementation_edge.from_id
        WHERE call.kind='calls' AND call.confidence!='inferred'
          AND property.signature LIKE '%' || protocol.name || '%';
        INSERT INTO edges(source_file,from_id,to_name,to_id,kind,confidence,line)
        SELECT DISTINCT target.file,target.id,source.qualified_name,source.id,'tested_by','inferred',e.line
        FROM edges e
        JOIN symbols source ON source.id=e.from_id
        JOIN symbols target ON target.id=e.to_id
        WHERE lower(source.file) LIKE '%test%' AND lower(target.file) NOT LIKE '%test%';
        """)
        }
        if documentsChanged {
            try execute("""
        DELETE FROM edges WHERE confidence='inferred' AND kind='documented_by';
        INSERT INTO edges(source_file,from_id,to_name,to_id,kind,confidence,line)
        SELECT DISTINCT target.file,target.id,source.file,source.id,'documented_by','inferred',e.line
        FROM edges e
        JOIN symbols source ON source.id=e.from_id
        JOIN symbols target ON target.id=e.to_id
        JOIN files document ON document.path=source.file
        WHERE document.kind='document' AND target.kind NOT IN ('heading','script-function');
        """)
        }
    }

    private func countRows() throws -> (files: Int, symbols: Int, edges: Int) {
        func count(_ table: String) throws -> Int {
            let statement = try prepare("SELECT COUNT(*) FROM \(table)")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
            return Int(sqlite3_column_int64(statement, 0))
        }
        return (try count("files"), try count("symbols"), try count("edges"))
    }

    private func writeArtifacts(root: URL, config: ProjectConfig, summary: BuildSummary) throws {
        let graph = root.appendingPathComponent("tools/SwiftProjectGraph/graph")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary).write(to: graph.appendingPathComponent("metrics.json"), options: .atomic)
        let manifest: [String: String] = [
            "project": config.projectName, "projectID": config.projectID,
            "generatedAt": ISO8601DateFormatter().string(from: Date()), "format": "SwiftProjectGraph/1"
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: graph.appendingPathComponent("manifest.json"), options: .atomic)
        let subsystems = config.subsystems.map { "- **\($0.name)** — \($0.description) (`\($0.paths.joined(separator: "`, `"))`)" }.joined(separator: "\n")
        let map = """
        # \(config.projectName) local project graph

        Generated locally from `project.json`. Source and project files remain authoritative.

        - Files: \(summary.totalFiles)
        - Symbols: \(summary.symbols)
        - Relationships: \(summary.edges)
        - Semantic build index: \(summary.semanticIndex)

        ## Subsystems

        \(subsystems)
        """
        try Data(map.utf8).write(to: graph.appendingPathComponent("MAP.md"), options: .atomic)
    }

    func setMetadata(_ key: String, _ value: String) throws {
        let statement = try prepare("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
        bind(statement, [key, value]); try step(statement); sqlite3_finalize(statement)
    }

    func metadataValue(_ key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM metadata WHERE key=?")
        defer { sqlite3_finalize(statement) }; bind(statement, [key])
        return sqlite3_step(statement) == SQLITE_ROW ? text(statement, 0) : nil
    }

    func graphFreshness() throws -> String {
        let semantic = try metadataValue("semantic_status") ?? "unavailable"
        let compact = semantic.hasPrefix("available") ? "available" : semantic
        return "syntax:fresh;semantic:\(compact)"
    }

    func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(message)
            throw ToolError.database("SQLite error: \(detail)")
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        return statement
    }

    func bind(_ statement: OpaquePointer, _ values: [String]) { bind(statement, start: 1, values: values) }
    func bind(_ statement: OpaquePointer, start: Int32, values: [String]) {
        for (offset, value) in values.enumerated() {
            sqlite3_bind_text(statement, start + Int32(offset), value, -1, sqliteTransient)
        }
    }
    private func bindOptional(_ statement: OpaquePointer, index: Int32, value: String?) {
        if let value { sqlite3_bind_text(statement, index, value, -1, sqliteTransient) }
        else { sqlite3_bind_null(statement, index) }
    }
    func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }
    func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }
    private func databaseError() -> ToolError { .database("SQLite error: \(String(cString: sqlite3_errmsg(handle)))") }
}
