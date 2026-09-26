import Foundation
import SQLite3

private struct IndexStringRef { let data: UnsafePointer<CChar>?; let length: Int }
private typealias IndexHandle = OpaquePointer
private typealias UnitCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Bool
private typealias DependencyCallback = @convention(c) (UnsafeMutableRawPointer?, IndexHandle?) -> Bool
private typealias OccurrenceCallback = @convention(c) (UnsafeMutableRawPointer?, IndexHandle?) -> Bool
private typealias RelationCallback = @convention(c) (UnsafeMutableRawPointer?, IndexHandle?) -> Bool

@_silgen_name("indexstore_store_create") private func storeCreate(_ path: UnsafePointer<CChar>, _ error: UnsafeMutablePointer<IndexHandle?>?) -> IndexHandle?
@_silgen_name("indexstore_store_dispose") private func storeDispose(_ store: IndexHandle?)
@_silgen_name("spg_store_units") private func storeUnits(_ store: IndexHandle?, _ context: UnsafeMutableRawPointer?, _ callback: UnitCallback) -> Bool
@_silgen_name("indexstore_unit_reader_create") private func unitCreate(_ store: IndexHandle?, _ name: UnsafePointer<CChar>, _ error: UnsafeMutablePointer<IndexHandle?>?) -> IndexHandle?
@_silgen_name("indexstore_unit_reader_dispose") private func unitDispose(_ reader: IndexHandle?)
@_silgen_name("indexstore_unit_reader_get_main_file") private func unitMainFile(_ reader: IndexHandle?) -> IndexStringRef
@_silgen_name("indexstore_unit_reader_dependencies_apply_f") private func unitDependencies(_ reader: IndexHandle?, _ context: UnsafeMutableRawPointer?, _ callback: DependencyCallback) -> Bool
@_silgen_name("indexstore_unit_dependency_get_kind") private func dependencyKind(_ dependency: IndexHandle?) -> UInt32
@_silgen_name("indexstore_unit_dependency_get_filepath") private func dependencyFile(_ dependency: IndexHandle?) -> IndexStringRef
@_silgen_name("indexstore_unit_dependency_get_name") private func dependencyName(_ dependency: IndexHandle?) -> IndexStringRef
@_silgen_name("indexstore_record_reader_create") private func recordCreate(_ store: IndexHandle?, _ name: UnsafePointer<CChar>, _ error: UnsafeMutablePointer<IndexHandle?>?) -> IndexHandle?
@_silgen_name("indexstore_record_reader_dispose") private func recordDispose(_ reader: IndexHandle?)
@_silgen_name("indexstore_record_reader_occurrences_apply_f") private func recordOccurrences(_ reader: IndexHandle?, _ context: UnsafeMutableRawPointer?, _ callback: OccurrenceCallback) -> Bool
@_silgen_name("indexstore_occurrence_get_symbol") private func occurrenceSymbol(_ occurrence: IndexHandle?) -> IndexHandle?
@_silgen_name("indexstore_occurrence_get_roles") private func occurrenceRoles(_ occurrence: IndexHandle?) -> UInt64
@_silgen_name("indexstore_occurrence_get_line_col") private func occurrenceLineColumn(_ occurrence: IndexHandle?, _ line: UnsafeMutablePointer<UInt32>?, _ column: UnsafeMutablePointer<UInt32>?)
@_silgen_name("indexstore_occurrence_relations_apply_f") private func occurrenceRelations(_ occurrence: IndexHandle?, _ context: UnsafeMutableRawPointer?, _ callback: RelationCallback) -> Bool
@_silgen_name("indexstore_symbol_get_name") private func symbolName(_ symbol: IndexHandle?) -> IndexStringRef
@_silgen_name("indexstore_symbol_get_usr") private func symbolUSR(_ symbol: IndexHandle?) -> IndexStringRef
@_silgen_name("indexstore_symbol_relation_get_roles") private func relationRoles(_ relation: IndexHandle?) -> UInt64
@_silgen_name("indexstore_symbol_relation_get_symbol") private func relationSymbol(_ relation: IndexHandle?) -> IndexHandle?

private func string(_ ref: IndexStringRef) -> String {
    guard let data = ref.data, ref.length > 0 else { return "" }
    return String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self), count: ref.length), as: UTF8.self)
}

private final class UnitCollector { var values = [String]() }
private func collectUnit(_ context: UnsafeMutableRawPointer?, _ data: UnsafePointer<CChar>?, _ length: Int) -> Bool {
    guard let context else { return false }
    Unmanaged<UnitCollector>.fromOpaque(context).takeUnretainedValue().values.append(string(IndexStringRef(data: data, length: length)))
    return true
}

private struct RecordKey: Hashable { let name: String; let file: String }
private final class DependencyCollector { let main: String; var values = Set<RecordKey>(); init(main: String) { self.main = main } }
private func collectDependency(_ context: UnsafeMutableRawPointer?, _ dependency: IndexHandle?) -> Bool {
    guard let context, dependencyKind(dependency) == 2 else { return true }
    let collector = Unmanaged<DependencyCollector>.fromOpaque(context).takeUnretainedValue()
    let file = string(dependencyFile(dependency)); let name = string(dependencyName(dependency))
    if !name.isEmpty { collector.values.insert(RecordKey(name: name, file: file.isEmpty ? collector.main : file)) }
    return true
}

private struct SemanticSymbol { let usr: String; let name: String; let file: String; let line: Int; let roles: UInt64 }
private struct SemanticEdge { let fromUSR: String; let toUSR: String; let kind: String; let file: String; let line: Int; let roles: UInt64 }
private final class RelationCollector { let ownerUSR: String; let roles: UInt64; let file: String; let line: Int; var edges = [SemanticEdge](); init(ownerUSR: String, roles: UInt64, file: String, line: Int) { self.ownerUSR = ownerUSR; self.roles = roles; self.file = file; self.line = line } }
private func collectRelation(_ context: UnsafeMutableRawPointer?, _ relation: IndexHandle?) -> Bool {
    guard let context else { return false }
    let collector = Unmanaged<RelationCollector>.fromOpaque(context).takeUnretainedValue()
    let related = string(symbolUSR(relationSymbol(relation))); guard !related.isEmpty else { return true }
    let relationRole = relationRoles(relation)
    if relationRole & (1 << 13) != 0 { collector.edges.append(SemanticEdge(fromUSR: related, toUSR: collector.ownerUSR, kind: "calls", file: collector.file, line: collector.line, roles: relationRole)) }
    if relationRole & (1 << 11) != 0 { collector.edges.append(SemanticEdge(fromUSR: collector.ownerUSR, toUSR: related, kind: "overrides", file: collector.file, line: collector.line, roles: relationRole)) }
    if relationRole & (1 << 10) != 0 { collector.edges.append(SemanticEdge(fromUSR: collector.ownerUSR, toUSR: related, kind: "inherits", file: collector.file, line: collector.line, roles: relationRole)) }
    if relationRole & (1 << 14) != 0 { collector.edges.append(SemanticEdge(fromUSR: related, toUSR: collector.ownerUSR, kind: "extends", file: collector.file, line: collector.line, roles: relationRole)) }
    if relationRole & (1 << 16) != 0 {
        let kind = collector.roles & (1 << 5) != 0 ? "calls" : (collector.roles & (1 << 4) != 0 ? "writes" : (collector.roles & (1 << 3) != 0 ? "reads" : "references"))
        collector.edges.append(SemanticEdge(fromUSR: related, toUSR: collector.ownerUSR, kind: kind, file: collector.file, line: collector.line, roles: relationRole))
    }
    return true
}

private final class OccurrenceCollector { let file: String; var symbols = [SemanticSymbol](); var edges = [SemanticEdge](); init(file: String) { self.file = file } }
private func collectOccurrence(_ context: UnsafeMutableRawPointer?, _ occurrence: IndexHandle?) -> Bool {
    guard let context, let symbol = occurrenceSymbol(occurrence) else { return true }
    let collector = Unmanaged<OccurrenceCollector>.fromOpaque(context).takeUnretainedValue()
    let usr = string(symbolUSR(symbol)); guard !usr.isEmpty else { return true }
    var line: UInt32 = 0, column: UInt32 = 0; occurrenceLineColumn(occurrence, &line, &column)
    let roles = occurrenceRoles(occurrence)
    collector.symbols.append(SemanticSymbol(usr: usr, name: string(symbolName(symbol)), file: collector.file, line: Int(line), roles: roles))
    let relations = RelationCollector(ownerUSR: usr, roles: roles, file: collector.file, line: Int(line))
    let pointer = Unmanaged.passUnretained(relations).toOpaque(); _ = occurrenceRelations(occurrence, pointer, collectRelation)
    collector.edges.append(contentsOf: relations.edges)
    return true
}

extension GraphDatabase {
    func enrich(root: URL, config: ProjectConfig) throws -> String {
        let configured = config.indexStorePaths ?? []
        var selected: URL?
        for path in configured {
            let candidate = root.appendingPathComponent(path).standardizedFileURL
            guard candidate.path.hasPrefix(root.path + "/") else { throw ToolError.pathOutsideRoot(path) }
            if FileManager.default.fileExists(atPath: candidate.path) { selected = candidate; break }
        }
        guard let selected else { return "unavailable" }
        var error: IndexHandle?
        guard let store = selected.path.withCString({ storeCreate($0, &error) }) else { return "unavailable" }
        defer { storeDispose(store) }

        let units = UnitCollector(); _ = storeUnits(store, Unmanaged.passUnretained(units).toOpaque(), collectUnit)
        var records = Set<RecordKey>()
        for unitName in units.values {
            guard let reader = unitName.withCString({ unitCreate(store, $0, &error) }) else { continue }
            let dependencies = DependencyCollector(main: string(unitMainFile(reader)))
            _ = unitDependencies(reader, Unmanaged.passUnretained(dependencies).toOpaque(), collectDependency)
            records.formUnion(dependencies.values); unitDispose(reader)
        }
        var symbols = [SemanticSymbol](), edges = [SemanticEdge]()
        for record in records where record.file.hasPrefix(root.path + "/") {
            guard let reader = record.name.withCString({ recordCreate(store, $0, &error) }) else { continue }
            let relative = String(record.file.dropFirst(root.path.count + 1)); let collector = OccurrenceCollector(file: relative)
            _ = recordOccurrences(reader, Unmanaged.passUnretained(collector).toOpaque(), collectOccurrence)
            symbols.append(contentsOf: collector.symbols); edges.append(contentsOf: collector.edges); recordDispose(reader)
        }
        try storeSemantic(symbols: symbols, edges: edges)
        let status = "available:units=\(units.values.count),records=\(records.count),symbols=\(symbols.count),edges=\(edges.count)"
        try setMetadata("semantic_status", status)
        try setMetadata("semantic_indexed_at", ISO8601DateFormatter().string(from: Date()))
        return status
    }

    private func storeSemantic(symbols: [SemanticSymbol], edges semanticEdges: [SemanticEdge]) throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS semantic_symbols(usr TEXT NOT NULL,name TEXT NOT NULL,file TEXT NOT NULL,line INTEGER NOT NULL,roles INTEGER NOT NULL,symbol_id TEXT,PRIMARY KEY(usr,file,line));
        CREATE INDEX IF NOT EXISTS semantic_usr ON semantic_symbols(usr);
        CREATE TABLE IF NOT EXISTS semantic_edges(from_usr TEXT NOT NULL,to_usr TEXT NOT NULL,kind TEXT NOT NULL,file TEXT NOT NULL,line INTEGER NOT NULL,roles INTEGER NOT NULL);
        DELETE FROM semantic_symbols; DELETE FROM semantic_edges; DELETE FROM edges WHERE confidence='semantic';
        """)
        var statement = try prepare("INSERT OR IGNORE INTO semantic_symbols(usr,name,file,line,roles) VALUES(?,?,?,?,?)")
        for symbol in symbols {
            bind(statement, [symbol.usr, symbol.name, symbol.file]); sqlite3_bind_int(statement, 4, Int32(symbol.line)); sqlite3_bind_int64(statement, 5, Int64(bitPattern: symbol.roles)); try step(statement); sqlite3_reset(statement); sqlite3_clear_bindings(statement)
        }
        sqlite3_finalize(statement)
        statement = try prepare("INSERT INTO semantic_edges(from_usr,to_usr,kind,file,line,roles) VALUES(?,?,?,?,?,?)")
        for edge in semanticEdges {
            bind(statement, [edge.fromUSR, edge.toUSR, edge.kind, edge.file]); sqlite3_bind_int(statement, 5, Int32(edge.line)); sqlite3_bind_int64(statement, 6, Int64(bitPattern: edge.roles)); try step(statement); sqlite3_reset(statement); sqlite3_clear_bindings(statement)
        }
        sqlite3_finalize(statement)
        try execute("""
        UPDATE semantic_symbols SET symbol_id=(SELECT s.id FROM symbols s
          WHERE s.file=semantic_symbols.file AND s.line=semantic_symbols.line AND
            (s.name=semantic_symbols.name OR
             (instr(semantic_symbols.name,'(')>0 AND s.name=substr(semantic_symbols.name,1,instr(semantic_symbols.name,'(')-1)))
          LIMIT 1) WHERE (roles & 3) != 0;
        INSERT INTO edges(source_file,from_id,to_name,to_id,kind,confidence,line)
        SELECT DISTINCT source.file,source.symbol_id,target.name,target.symbol_id,e.kind,'semantic',e.line
        FROM semantic_edges e JOIN semantic_symbols source ON source.usr=e.from_usr JOIN semantic_symbols target ON target.usr=e.to_usr
        WHERE source.symbol_id IS NOT NULL AND target.symbol_id IS NOT NULL;
        """)
    }
}
