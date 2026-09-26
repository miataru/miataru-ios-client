import Foundation
import SQLite3

struct GraphHit: Codable {
    let path: String
    let line: Int
    let kind: String
    let name: String
    let signature: String
    let documentation: String
    let status: String
    let score: Double
}

struct QueryEnvelope: Codable {
    let freshness: String
    let estimatedTokens: Int
    let omitted: Int
    let text: String
}

extension GraphDatabase {
    func findCode(_ query: String, limit: Int = 20) throws -> [GraphHit] {
        let requestedLimit = max(1, min(limit, 200))
        let anchor = entityAnchor(query)
        var terms = searchTerms(query)
        if let encoded = try metadataValue("search_synonyms"), let data = encoded.data(using: .utf8),
           let synonyms = try? JSONDecoder().decode([String: [String]].self, from: data) {
            let lower = Set(terms.map { $0.lowercased() })
            for (key, values) in synonyms where lower.contains(key.lowercased()) { terms.append(contentsOf: values) }
            terms = Array(Set(terms))
        }
        guard !terms.isEmpty else { return [] }
        let fts = terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }.joined(separator: " OR ")
        let statement = try prepare("""
        SELECT search.path, COALESCE(symbols.line, 1), search.kind, search.name,
               search.signature, search.documentation, search.status,
               bm25(search, 2.0, 8.0, 4.0, 3.0, 1.0) -
                 MIN(100, (SELECT COUNT(DISTINCT e.from_id) FROM edges e WHERE e.to_id=symbols.id)) * 0.01 AS rank
        FROM search LEFT JOIN symbols
          ON symbols.file = search.path AND symbols.qualified_name = search.name
        WHERE search MATCH ?
        ORDER BY CASE WHEN lower(search.name) = lower(?) THEN 0
                      WHEN lower(search.name) LIKE lower(?) || '%' THEN 1 ELSE 2 END,
                 rank
        LIMIT ?
        """)
        defer { sqlite3_finalize(statement) }
        bind(statement, [fts, anchor ?? query, anchor ?? query])
        // Intent and project-specific reranking happen after FTS. Keep a stable
        // candidate pool so compact limits do not accidentally hide documents.
        sqlite3_bind_int(statement, 4, 1_000)
        var hits = [GraphHit]()
        while sqlite3_step(statement) == SQLITE_ROW {
            hits.append(GraphHit(path: text(statement, 0), line: Int(sqlite3_column_int(statement, 1)),
                                 kind: text(statement, 2), name: text(statement, 3), signature: text(statement, 4),
                                 documentation: text(statement, 5), status: text(statement, 6),
                                 score: sqlite3_column_double(statement, 7)))
        }
        if let anchor { hits.append(contentsOf: try anchoredDeclarationHits(anchor)) }
        var seen = Set<String>()
        hits = hits.filter { seen.insert("\($0.path):\($0.line):\($0.kind)").inserted }
        let queryLower = query.lowercased()
        let documentationIntent = isDocumentationIntent(query)
        let explicitToolQuery = queryLower.contains("swiftprojectgraph") || queryLower.contains("swift project graph") || queryLower.contains("tools/")
        let ranked = hits.map { hit -> GraphHit in
            let searchable = [hit.path, hit.name, hit.signature, hit.documentation].joined(separator: " ").lowercased()
            let coverage = terms.filter { searchable.contains($0.lowercased()) }.count
            var relevance = hit.score - Double(coverage * 4)
            if let anchor {
                let anchorLower = anchor.lowercased(), nameLower = hit.name.lowercased()
                if nameLower == anchorLower, ["class", "actor", "struct", "enum", "protocol"].contains(hit.kind) { relevance -= 240 }
                else if queryLower.contains("init"), hit.kind == "initializer", nameLower.contains(anchorLower + ".") { relevance -= 220 }
                else if nameLower == anchorLower { relevance -= 180 }
                else if searchable.contains(anchorLower) { relevance -= 70 }
                else { relevance += 120 }
                if URL(fileURLWithPath: hit.path).lastPathComponent.lowercased().contains(anchorLower) { relevance -= 35 }
            }
            if !explicitToolQuery, hit.path.hasPrefix("tools/SwiftProjectGraph/") { relevance += 160 }
            if documentationIntent {
                if hit.path.lowercased().hasSuffix(".md") || hit.kind == "heading" { relevance -= 180 }
                else { relevance += 60 }
                if hit.status == "P0 target" || hit.status == "Current" { relevance -= 20 }
            }
            if hit.status == "historical" { relevance += 30 }
            return GraphHit(path: hit.path, line: hit.line, kind: hit.kind, name: hit.name,
                            signature: hit.signature, documentation: hit.documentation,
                            status: hit.status, score: relevance)
        }
        return Array(ranked.sorted { lhs, rhs in
            lhs.score == rhs.score ? (lhs.path, lhs.line) < (rhs.path, rhs.line) : lhs.score < rhs.score
        }.prefix(requestedLimit))
    }

    func fileAPI(_ pathQuery: String) throws -> String {
        let statement = try prepare("""
        SELECT file,line,kind,access,qualified_name,signature,documentation
        FROM symbols WHERE file = ? OR file LIKE ? ORDER BY file,line
        """)
        defer { sqlite3_finalize(statement) }
        bind(statement, [pathQuery, "%\(pathQuery)%"])
        var output = [String](), current = ""
        while sqlite3_step(statement) == SQLITE_ROW {
            let path = text(statement, 0)
            if path != current { current = path; output.append("# \(path)") }
            let doc = text(statement, 6)
            output.append("\(text(statement, 1)): \(text(statement, 3)) \(text(statement, 2)) \(text(statement, 5))" + (doc.isEmpty ? "" : " — \(doc)"))
        }
        return output.isEmpty ? "No indexed API matched `\(pathQuery)`." : output.joined(separator: "\n")
    }

    func trace(_ target: String, direction: String, depth: Int, limit: Int = 100, relationshipKinds: Set<String>? = nil, includeMembers: Bool = false) throws -> String {
        var symbolIDs = try matchingSymbolIDs(target)
        guard !symbolIDs.isEmpty else { return "No symbol matched `\(target)`." }
        if includeMembers { symbolIDs += try directMemberIDs(of: symbolIDs) }
        var frontier = Set(symbolIDs), visited = Set(symbolIDs), lines = ["trace \(direction) depth=\(depth) target=\(target)"]
        var seenRelationships = Set<String>()
        for level in 1...max(1, min(depth, 6)) {
            var next = Set<String>()
            for id in frontier.sorted() {
                let incoming = direction == "incoming" || direction == "both"
                let outgoing = direction != "incoming"
                if outgoing {
                    try appendEdges(sql: "SELECT e.kind,e.confidence,e.line,s.file,s.qualified_name,e.to_name,e.to_id FROM edges e JOIN symbols s ON s.id=e.from_id WHERE e.from_id=? ORDER BY CASE e.confidence WHEN 'semantic' THEN 0 WHEN 'inferred' THEN 1 ELSE 2 END, CASE e.kind WHEN 'tested_by' THEN 0 WHEN 'constructs' THEN 1 WHEN 'calls' THEN 2 WHEN 'reads' THEN 3 WHEN 'writes' THEN 4 WHEN 'references' THEN 5 ELSE 6 END", id: id, level: level, lines: &lines, next: &next, nextColumn: 6, relationshipKinds: relationshipKinds, seen: &seenRelationships, limit: limit)
                }
                if incoming {
                    try appendEdges(sql: "SELECT e.kind,e.confidence,e.line,s.file,s.qualified_name,e.to_name,e.from_id FROM edges e JOIN symbols s ON s.id=e.from_id WHERE e.to_id=? ORDER BY CASE e.confidence WHEN 'semantic' THEN 0 WHEN 'inferred' THEN 1 ELSE 2 END, CASE e.kind WHEN 'tested_by' THEN 0 WHEN 'constructs' THEN 1 WHEN 'calls' THEN 2 WHEN 'reads' THEN 3 WHEN 'writes' THEN 4 WHEN 'references' THEN 5 ELSE 6 END", id: id, level: level, lines: &lines, next: &next, nextColumn: 6, relationshipKinds: relationshipKinds, seen: &seenRelationships, limit: limit)
                }
                if lines.count >= limit { break }
            }
            frontier = next.subtracting(visited); visited.formUnion(frontier)
            if frontier.isEmpty || lines.count >= limit { break }
        }
        if lines.count >= limit { lines.append("… additional relationships omitted") }
        return lines.joined(separator: "\n")
    }

    func findAll(_ pattern: String, limit: Int = 200, pathFilter: String? = nil, statusFilter: String? = nil) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let statement = try prepare("SELECT path,content FROM files WHERE (?='' OR path LIKE ?) AND (?='' OR status=?) ORDER BY path")
        defer { sqlite3_finalize(statement) }
        let path = pathFilter ?? "", status = statusFilter ?? ""
        bind(statement, [path, path.isEmpty ? "" : "%\(path)%", status, status])
        var lines = [String](), omitted = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            let path = text(statement, 0), content = text(statement, 1)
            let sourceLines = content.components(separatedBy: .newlines)
            for (offset, sourceLine) in sourceLines.enumerated() {
                let range = NSRange(sourceLine.startIndex..<sourceLine.endIndex, in: sourceLine)
                guard regex.firstMatch(in: sourceLine, range: range) != nil else { continue }
                if lines.count < limit { lines.append("\(path):\(offset + 1): \(compactWhitespace(sourceLine, limit: 240))") }
                else { omitted += 1 }
            }
        }
        if omitted > 0 { lines.append("… omitted=\(omitted)") }
        return lines.isEmpty ? "No matches for `\(pattern)`." : lines.joined(separator: "\n")
    }

    func context(_ query: String, tokenBudget: Int, includeSource: Bool = false, config: ProjectConfig? = nil) throws -> QueryEnvelope {
        let budget = max(300, min(tokenBudget, 20_000))
        let hitBudget = includeSource ? budget / 2 : budget * 35 / 100
        let hits = try findCode(query, limit: 80)
        var sections = [String](), used = 0, omitted = 0, extensionCounts = [String: Int]()
        var essentialKeys = Set<String>()
        if let anchor = entityAnchor(query) {
            let essentialHits = try anchoredDeclarationHits(anchor)
            essentialKeys = Set(essentialHits.map { "\($0.path):\($0.line)" })
            let essentials = renderHits(essentialHits.prefix(12))
            let cost = essentials.count / 4
            if !essentials.isEmpty, cost < hitBudget { sections.append("Essentials\n\(essentials)"); used += cost }
        }
        let grouped = Dictionary(grouping: hits.filter { !essentialKeys.contains("\($0.path):\($0.line)") }) { hit in
            contextGroup(for: hit, config: config)
        }
        let documentationIntent = isDocumentationIntent(query)
        let groupOrder = grouped.keys.sorted {
            if documentationIntent, ($0 == "Documents") != ($1 == "Documents") { return $0 == "Documents" }
            return contextGroupPriority($0) < contextGroupPriority($1)
        }
        var fileCounts = [String: Int]()
        for group in groupOrder {
            var groupLines = [String]()
            let orderedHits = (grouped[group] ?? []).sorted {
                let left = contextKindPriority($0.kind), right = contextKindPriority($1.kind)
                return left == right ? $0.score < $1.score : left < right
            }
            for hit in orderedHits {
                let perFileLimit = group == "Tests" ? 6 : (group == "Documents" ? 6 : 3)
                if fileCounts[hit.path, default: 0] >= perFileLimit { omitted += 1; continue }
            if hit.kind == "extension" {
                let count = extensionCounts[hit.name, default: 0]
                if count >= 2 { omitted += 1; continue }
                extensionCounts[hit.name] = count + 1
            }
            var line = "\(hit.path):\(hit.line) [\(hit.status)] \(hit.kind) \(hit.signature.isEmpty ? hit.name : hit.signature)"
            if !hit.documentation.isEmpty { line += " — \(hit.documentation)" }
            let cost = max(1, line.count / 4)
            if used + cost > hitBudget { omitted += 1; continue }
                groupLines.append(line); used += cost; fileCounts[hit.path, default: 0] += 1
            }
            if !groupLines.isEmpty { sections.append("\(group)\n" + groupLines.joined(separator: "\n")) }
        }
        if !documentationIntent, let anchorHit = relationshipAnchor(in: hits, query: query), used < budget * 3 / 4 {
            let relatedTests = try relatedTests(for: anchorHit.name, query: query, limit: 4)
            if !relatedTests.isEmpty {
                let testText = "Related tests\n" + relatedTests.joined(separator: "\n")
                let testCost = testText.count / 4
                if used + testCost < budget { sections.append(testText); used += testCost }
            }
            let relationships = try trace(anchorHit.name, direction: inferredDirection(query), depth: 1, limit: 10,
                                          relationshipKinds: inferredRelationshipKinds(query), includeMembers: true)
            var included = [String](), relationshipCost = 0
            for line in relationships.components(separatedBy: .newlines) {
                let cost = max(1, line.count / 4)
                if used + relationshipCost + cost > budget { omitted += 1; continue }
                included.append(line); relationshipCost += cost
            }
            if !included.isEmpty { sections.append("\nRelationships\n\(included.joined(separator: "\n"))"); used += relationshipCost }
        }
        if includeSource {
            for hit in hits.prefix(3) {
                let excerpt = try sourceExcerpt(path: hit.path, line: hit.line, radius: 4)
                let cost = excerpt.count / 4
                if !excerpt.isEmpty, used + cost <= budget { sections.append("\nExcerpt \(hit.path):\(hit.line)\n\(excerpt)"); used += cost }
            }
        }
        let freshness = try graphFreshness()
        sections.append("\nfreshness=\(freshness) estimated_tokens=\(used) omitted=\(omitted)")
        return QueryEnvelope(freshness: freshness, estimatedTokens: used, omitted: omitted, text: sections.joined(separator: "\n"))
    }

    private func renderHits<S: Sequence>(_ hits: S) -> String where S.Element == GraphHit {
        hits.map { "\($0.path):\($0.line) [\($0.status)] \($0.kind) \($0.signature.isEmpty ? $0.name : $0.signature)" }.joined(separator: "\n")
    }

    private func contextGroup(for hit: GraphHit, config: ProjectConfig?) -> String {
        if hit.path.localizedCaseInsensitiveContains("test") { return "Tests" }
        if hit.path.lowercased().hasSuffix(".md") { return "Documents" }
        if let subsystem = config?.subsystems.first(where: { subsystem in subsystem.paths.contains { hit.path.hasPrefix($0) } }) {
            return subsystem.name
        }
        return "Code"
    }

    private func contextGroupPriority(_ group: String) -> Int {
        group == "Code" ? 0 : (group == "Tests" ? 90 : (group == "Documents" ? 100 : 10))
    }

    private func contextKindPriority(_ kind: String) -> Int {
        ["class", "actor", "struct", "enum", "protocol", "function", "initializer", "heading", "document"]
            .firstIndex(of: kind) ?? 20
    }

    private func relationshipAnchor(in hits: [GraphHit], query: String) -> GraphHit? {
        let isProduction: (GraphHit) -> Bool = { !$0.path.localizedCaseInsensitiveContains("test") && !$0.path.lowercased().hasSuffix(".md") }
        let typeKinds = Set(["class", "actor", "struct", "enum", "protocol"])
        let callableKinds = Set(["function", "initializer"])
        let queryTerms = Set(searchTerms(query).map { $0.lowercased() })
        let types = hits.filter { isProduction($0) && typeKinds.contains($0.kind) }
        return types.max { lhs, rhs in
            let left = searchTerms(lhs.name).filter { queryTerms.contains($0.lowercased()) }.count
            let right = searchTerms(rhs.name).filter { queryTerms.contains($0.lowercased()) }.count
            return left == right ? lhs.score > rhs.score : left < right
        }
            ?? hits.first { isProduction($0) && callableKinds.contains($0.kind) }
            ?? hits.first { !$0.path.localizedCaseInsensitiveContains("test") && !$0.path.lowercased().hasSuffix(".md") }
            ?? hits.first
    }

    private func sourceExcerpt(path: String, line: Int, radius: Int) throws -> String {
        let statement = try prepare("SELECT content FROM files WHERE path=?")
        defer { sqlite3_finalize(statement) }; bind(statement, [path])
        guard sqlite3_step(statement) == SQLITE_ROW else { return "" }
        let lines = text(statement, 0).components(separatedBy: .newlines)
        let start = max(0, line - radius - 1), end = min(lines.count, line + radius)
        return lines[start..<end].enumerated().map { "\(start + $0.offset + 1) \($0.element)" }.joined(separator: "\n")
    }

    func repoMap(config: ProjectConfig) throws -> String {
        var lines = ["# \(config.projectName) repository map"]
        if !config.xcodeProjects.isEmpty { lines.append("Xcode: \(config.xcodeProjects.joined(separator: ", ")); schemes=\(config.schemes.joined(separator: ", "))") }
        if !config.packages.isEmpty { lines.append("SwiftPM: \(config.packages.joined(separator: ", "))") }
        if let plans = config.testPlans, !plans.isEmpty { lines.append("Test plans: \(plans.joined(separator: ", "))") }
        for subsystem in config.subsystems {
            let patterns = subsystem.paths.map { $0 + "%" }
            var count = 0
            for pattern in patterns {
                let statement = try prepare("SELECT COUNT(*) FROM symbols WHERE file LIKE ?")
                bind(statement, [pattern]); if sqlite3_step(statement) == SQLITE_ROW { count += Int(sqlite3_column_int(statement, 0)) }; sqlite3_finalize(statement)
            }
            lines.append("- \(subsystem.name): symbols=\(count); \(subsystem.description); paths=\(subsystem.paths.joined(separator: ","))")
        }
        if let flows = config.architectureFlows, !flows.isEmpty {
            lines.append("\nConfigured flows")
            lines += flows.map { "- \($0.name): \($0.steps.joined(separator: " -> "))" }
        }
        let hubs = try prepare("SELECT s.file,s.qualified_name,COUNT(DISTINCT e.from_id) c FROM edges e JOIN symbols s ON s.id=e.to_id WHERE (e.confidence='semantic' AND e.kind IN ('calls','reads','writes','references','overrides')) OR e.kind IN ('constructs','inherits','conforms','extends') GROUP BY e.to_id ORDER BY c DESC LIMIT 15")
        defer { sqlite3_finalize(hubs) }
        lines.append("\nHubs")
        while sqlite3_step(hubs) == SQLITE_ROW { lines.append("- \(text(hubs, 0)): \(text(hubs, 1)) incoming=\(sqlite3_column_int(hubs, 2))") }
        return lines.joined(separator: "\n")
    }

    func rawCounts() throws -> (Int, Int, Int) {
        func count(_ table: String) throws -> Int {
            let statement = try prepare("SELECT COUNT(*) FROM \(table)"); defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(statement, 0))
        }
        return (try count("files"), try count("symbols"), try count("edges"))
    }

    func indexedPaths() throws -> Set<String> {
        let statement = try prepare("SELECT path FROM files")
        defer { sqlite3_finalize(statement) }
        var paths = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW { paths.insert(text(statement, 0)) }
        return paths
    }

    private func matchingSymbolIDs(_ target: String) throws -> [String] {
        var statement = try prepare("SELECT id FROM symbols WHERE (name=? OR qualified_name=? OR file=?) AND kind!='extension' LIMIT 100")
        bind(statement, [target, target, target])
        var result = [String](); while sqlite3_step(statement) == SQLITE_ROW { result.append(text(statement, 0)) }
        sqlite3_finalize(statement)
        if !result.isEmpty { return result }
        statement = try prepare("SELECT id FROM symbols WHERE name=? OR qualified_name=? OR file=? LIMIT 100")
        bind(statement, [target, target, target])
        while sqlite3_step(statement) == SQLITE_ROW { result.append(text(statement, 0)) }
        sqlite3_finalize(statement)
        if !result.isEmpty { return result }
        statement = try prepare("SELECT id FROM symbols WHERE qualified_name LIKE ? OR file LIKE ? LIMIT 100")
        defer { sqlite3_finalize(statement) }
        bind(statement, ["%\(target)%", "%\(target)%"])
        while sqlite3_step(statement) == SQLITE_ROW { result.append(text(statement, 0)) }
        return result
    }

    private func appendEdges(sql: String, id: String, level: Int, lines: inout [String], next: inout Set<String>, nextColumn: Int32, relationshipKinds: Set<String>?, seen: inout Set<String>, limit: Int) throws {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }; bind(statement, [id])
        while sqlite3_step(statement) == SQLITE_ROW {
            let kind = text(statement, 0)
            if let relationshipKinds, !relationshipKinds.contains(kind) { continue }
            let target = text(statement, 5)
            let key = "\(text(statement, 3)):\(sqlite3_column_int(statement, 2)):\(text(statement, 4)):\(target)"
            guard seen.insert(key).inserted else { continue }
            lines.append("\(level). \(text(statement, 3)):\(sqlite3_column_int(statement, 2)) \(text(statement, 4)) -[\(kind),\(text(statement, 1))]-> \(target)")
            let nextID = text(statement, nextColumn); if !nextID.isEmpty { next.insert(nextID) }
            if lines.count >= limit { break }
        }
    }

    private func searchTerms(_ input: String) -> [String] {
        let expanded = input.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        return expanded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private func entityAnchor(_ input: String) -> String? {
        input.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && $0.dropFirst().contains(where: { $0.isUppercase }) }
            .max(by: { $0.count < $1.count })
    }

    private func inferredRelationshipKinds(_ query: String) -> Set<String>? {
        let lower = query.lowercased()
        if lower.contains("construct") || lower.contains("creat") || lower.contains("instanti") || lower.contains("init") { return ["constructs"] }
        if lower.contains("caller") || lower.contains("callee") || lower.contains("call") { return ["calls"] }
        if lower.contains("read") { return ["reads"] }
        if lower.contains("write") || lower.contains("mutat") { return ["writes"] }
        return nil
    }

    private func inferredDirection(_ query: String) -> String {
        let lower = query.lowercased()
        if lower.contains("construct") || lower.contains("creat") || lower.contains("instanti") || lower.contains("caller") || lower.contains("used by") { return "incoming" }
        if lower.contains("callee") || lower.contains("dependenc") { return "outgoing" }
        return "both"
    }

    private func anchoredDeclarationHits(_ anchor: String) throws -> [GraphHit] {
        let statement = try prepare("""
        SELECT s.file,s.line,s.kind,s.qualified_name,s.signature,s.documentation,f.status
        FROM symbols s JOIN files f ON f.path=s.file
        WHERE (s.name=? AND s.kind IN ('class','actor','struct','enum','protocol'))
           OR (s.kind='initializer' AND s.parent_id IN (
             SELECT id FROM symbols WHERE name=? AND kind IN ('class','actor','struct','enum','protocol')
           ))
        ORDER BY s.file,s.line LIMIT 40
        """)
        defer { sqlite3_finalize(statement) }; bind(statement, [anchor, anchor])
        var hits = [GraphHit]()
        while sqlite3_step(statement) == SQLITE_ROW {
            hits.append(GraphHit(path: text(statement, 0), line: Int(sqlite3_column_int(statement, 1)),
                                 kind: text(statement, 2), name: text(statement, 3), signature: text(statement, 4),
                                 documentation: text(statement, 5), status: text(statement, 6), score: 0))
        }
        return hits
    }

    private func directMemberIDs(of parents: [String]) throws -> [String] {
        var ids = [String]()
        for parent in parents {
            let statement = try prepare("SELECT id FROM symbols WHERE parent_id=? LIMIT 300")
            bind(statement, [parent])
            while sqlite3_step(statement) == SQLITE_ROW { ids.append(text(statement, 0)) }
            sqlite3_finalize(statement)
        }
        return ids
    }

    private func relatedTests(for target: String, query: String, limit: Int) throws -> [String] {
        let statement = try prepare("""
        WITH RECURSIVE selected(id) AS (
          SELECT id FROM symbols WHERE name=? OR qualified_name=?
          UNION SELECT child.id FROM symbols child JOIN selected parent ON child.parent_id=parent.id
        )
        SELECT DISTINCT test.file,test.line,test.qualified_name
        FROM selected JOIN edges e ON e.from_id=selected.id AND e.kind='tested_by'
        JOIN symbols test ON test.id=e.to_id
        """)
        defer { sqlite3_finalize(statement) }; bind(statement, [target, target])
        var candidates = [(String, Int)]()
        let stems = searchTerms(query).filter { $0.count >= 5 }.map { String($0.lowercased().prefix(5)) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let line = "\(text(statement, 0)):\(sqlite3_column_int(statement, 1)) \(text(statement, 2))"
            let lower = line.lowercased(), score = stems.filter { lower.contains($0) }.count
            candidates.append((line, score))
        }
        return candidates.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private func isDocumentationIntent(_ query: String) -> Bool {
        let terms = Set(searchTerms(query).map { $0.lowercased() })
        return !terms.isDisjoint(with: ["release", "signing", "distribution", "status", "plan", "roadmap"])
            || (terms.contains("gate") && terms.contains("documentation"))
    }

}
