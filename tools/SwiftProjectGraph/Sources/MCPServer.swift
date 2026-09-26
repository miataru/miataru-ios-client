import Foundation

final class MCPServer {
    private let root: URL
    private let config: ProjectConfig
    private let database: GraphDatabase
    init(root: URL, config: ProjectConfig, database: GraphDatabase) {
        self.root = root; self.config = config; self.database = database
    }

    func serve() throws {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = line.data(using: .utf8),
                  let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = request["method"] as? String else { continue }
            if method.hasPrefix("notifications/") { continue }
            guard let id = request["id"] else { continue }
            do {
                let result: Any
                switch method {
                case "initialize":
                    let params = request["params"] as? [String: Any]
                    result = ["protocolVersion": params?["protocolVersion"] as? String ?? "2025-06-18", "capabilities": ["tools": [:]],
                              "serverInfo": ["name": "swift_project_graph", "version": "1.0.0"],
                              "instructions": "Use compact graph tools before broad source inspection. Source files remain authoritative."]
                case "ping": result = [:]
                case "tools/list": result = ["tools": toolDefinitions()]
                case "tools/call": result = try call(request)
                default: throw ToolError.usage("Unsupported MCP method \(method).")
                }
                write(["jsonrpc": "2.0", "id": id, "result": result])
            } catch {
                write(["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": error.localizedDescription]])
            }
        }
    }

    private func call(_ request: [String: Any]) throws -> [String: Any] {
        guard let params = request["params"] as? [String: Any], let name = params["name"] as? String else { throw ToolError.usage("Missing MCP tool name.") }
        let args = params["arguments"] as? [String: Any] ?? [:]
        let isFresh = try database.isFresh(root: root, config: config)
        if name != "swift_graph_freshness" && !isFresh { throw ToolError.stale }
        let text: String
        switch name {
        case "swift_graph_context": text = try database.context(string(args, "query"), tokenBudget: integer(args, "token_budget", 3_000), includeSource: args["include_source"] as? Bool ?? false, config: config).text
        case "swift_graph_find_code": text = render(try database.findCode(string(args, "query"), limit: integer(args, "limit", 20)))
        case "swift_graph_file_api": text = try database.fileAPI(string(args, "path"))
        case "swift_graph_trace":
            let kinds = (args["relationship_types"] as? [String]).map(Set.init)
            text = try database.trace(string(args, "symbol"), direction: args["direction"] as? String ?? "outgoing", depth: integer(args, "depth", 2), relationshipKinds: kinds)
        case "swift_graph_find_all":
            text = try database.findAll(string(args, "pattern"), limit: integer(args, "limit", 200), pathFilter: args["path"] as? String, statusFilter: args["status"] as? String)
        case "swift_graph_repo_map": text = try database.repoMap(config: config)
        case "swift_graph_impact": text = try database.impact(string(args, "target"), config: config, root: root)
        case "swift_graph_freshness": text = "syntax=\(isFresh ? "fresh" : "stale") \(try database.graphFreshness())"
        default: throw ToolError.usage("Unknown MCP tool \(name).")
        }
        let omitted = captureOmitted(text)
        let suffix = "\nfreshness=\(try database.graphFreshness()) estimated_tokens=\(max(1, text.count / 4)) omitted=\(omitted)"
        return ["content": [["type": "text", "text": text + suffix]], "isError": false]
    }

    private func toolDefinitions() -> [[String: Any]] {
        func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
        let string: [String: Any] = ["type": "string"]
        let integer: [String: Any] = ["type": "integer", "minimum": 1]
        return [
            tool("swift_graph_context", "Smallest context for ambiguous behavior or multi-hop analysis; prefer exact text search for a single known literal.", schema(["query": string, "token_budget": integer, "include_source": ["type": "boolean"]], required: ["query"])),
            tool("swift_graph_find_code", "Ranked symbol, behavior, path and concept search.", schema(["query": string, "limit": integer], required: ["query"])),
            tool("swift_graph_file_api", "Signature-only API for a file without method bodies.", schema(["path": string], required: ["path"])),
            tool("swift_graph_trace", "Incoming or outgoing graph relationships, optionally restricted to relationship types.", schema(["symbol": string, "direction": ["type": "string", "enum": ["incoming", "outgoing", "both"]], "depth": integer, "relationship_types": ["type": "array", "items": string]], required: ["symbol"])),
            tool("swift_graph_find_all", "Complete regex search with optional path and document-status filters; rg is faster for one exact known literal.", schema(["pattern": string, "limit": integer, "path": string, "status": string], required: ["pattern"])),
            tool("swift_graph_repo_map", "Subsystems, hubs, targets and configured runtime areas.", schema([:])),
            tool("swift_graph_impact", "Blast radius, related tests and verification commands.", schema(["target": string], required: ["target"])),
            tool("swift_graph_freshness", "Read-only repository and semantic-index freshness check.", schema([:]))
        ]
    }

    private func tool(_ name: String, _ description: String, _ schema: [String: Any]) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": schema]
    }
    private func string(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else { throw ToolError.usage("Missing \(key).") }; return value
    }
    private func integer(_ args: [String: Any], _ key: String, _ fallback: Int) -> Int { args[key] as? Int ?? fallback }
    private func render(_ hits: [GraphHit]) -> String { hits.map { "\($0.path):\($0.line) [\($0.status)] \($0.kind) \($0.signature.isEmpty ? $0.name : $0.signature)" }.joined(separator: "\n") }
    private func captureOmitted(_ text: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: "omitted=(\\d+)") else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.matches(in: text, range: range).last,
              let valueRange = Range(match.range(at: 1), in: text) else { return 0 }
        return Int(text[valueRange]) ?? 0
    }
    private func write(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value), var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"; FileHandle.standardOutput.write(Data(line.utf8))
    }
}
