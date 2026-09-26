import Foundation

struct ProjectConfig: Codable {
    struct DocumentRule: Codable {
        let pathPrefix: String
        let status: String
    }

    struct Subsystem: Codable {
        let name: String
        let paths: [String]
        let description: String
    }

    struct ArchitectureFlow: Codable {
        let name: String
        let steps: [String]
    }

    let schemaVersion: Int
    let projectName: String
    let projectID: String
    let sourceRoots: [String]
    let testRoots: [String]
    let documentRoots: [String]
    let scriptRoots: [String]
    let excludePathComponents: [String]
    let includeGlobs: [String]?
    let excludeGlobs: [String]?
    let xcodeProjects: [String]
    let schemes: [String]
    let packages: [String]
    let testPlans: [String]?
    let testTargets: [String]?
    let indexStorePaths: [String]?
    let verificationCommands: [String]
    let documentRules: [DocumentRule]
    let subsystems: [Subsystem]
    let architectureFlows: [ArchitectureFlow]?
    let searchSynonyms: [String: [String]]

    static func load(from url: URL) throws -> ProjectConfig {
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(ProjectConfig.self, from: data)
        guard config.schemaVersion == 1 else {
            throw ToolError.configuration("Unsupported project.json schema \(config.schemaVersion).")
        }
        return config
    }
}

struct SymbolRecord: Codable, Hashable {
    let id: String
    let file: String
    let name: String
    let qualifiedName: String
    let kind: String
    let signature: String
    let documentation: String
    let access: String
    let line: Int
    let endLine: Int
    let parentID: String?
}

struct EdgeRecord: Codable, Hashable {
    let sourceFile: String
    let fromID: String
    let toName: String
    let toID: String?
    let kind: String
    let confidence: String
    let line: Int
}

struct ParsedFile {
    let path: String
    let fingerprint: String
    let kind: String
    let status: String
    let content: String
    let imports: [String]
    let symbols: [SymbolRecord]
    let edges: [EdgeRecord]
}

struct BuildSummary: Codable {
    let project: String
    let changedFiles: Int
    let removedFiles: Int
    let totalFiles: Int
    let symbols: Int
    let edges: Int
    let semanticIndex: String
    let elapsedMilliseconds: Int
}

enum ToolError: Error, LocalizedError {
    case usage(String)
    case configuration(String)
    case database(String)
    case stale
    case pathOutsideRoot(String)

    var errorDescription: String? {
        switch self {
        case .usage(let value), .configuration(let value), .database(let value): value
        case .stale: "SwiftProjectGraph is stale; run `tools/SwiftProjectGraph/run.sh build`."
        case .pathOutsideRoot(let path): "Path is outside the configured project root: \(path)"
        }
    }
}

func stableHash(_ data: Data) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}

func compactWhitespace(_ value: String, limit: Int = 500) -> String {
    let compact = value.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    return compact.count <= limit ? compact : String(compact.prefix(limit - 1)) + "…"
}
