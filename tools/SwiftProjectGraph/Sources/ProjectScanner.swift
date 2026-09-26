import Foundation

struct ProjectScanner {
    let root: URL
    let config: ProjectConfig

    private var allowedRoots: [(String, String)] {
        config.sourceRoots.map { ($0, "source") }
            + config.testRoots.map { ($0, "test") }
            + config.documentRoots.map { ($0, "document") }
            + config.scriptRoots.map { ($0, "script") }
            + config.xcodeProjects.map { ($0, "project") }
            + config.packages.map { ($0, "project") }
            + (config.testPlans ?? []).map { ($0, "project") }
    }

    func files() throws -> [(URL, String, String)] {
        var result = [String: (URL, String, String)]()
        // Root documentation is commonly the repository's canonical source of
        // truth. Index it even when a copied project.json forgot to enumerate it.
        let rootItems = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )
        for url in rootItems where url.pathExtension.lowercased() == "md" {
            let path = relative(url)
            if accepts(url, path: path) { result[path] = (url, "document", status(for: path)) }
        }
        for (relativeRoot, configuredKind) in allowedRoots {
            let directory = try containedURL(relativeRoot)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                let path = relative(directory)
                if accepts(directory, path: path) { result[path] = (directory, configuredKind, status(for: path)) }
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                let path = relative(url)
                if excluded(path) {
                    enumerator.skipDescendants()
                    continue
                }
                guard accepts(url, path: path), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let kind = url.pathExtension == "swift" ? (configuredKind == "test" ? "test" : "swift") : configuredKind
                result[path] = (url, kind, status(for: path))
            }
        }
        return result.keys.sorted().compactMap { result[$0] }
    }

    func documentationCoverageIssues(indexedPaths: Set<String>) throws -> [String] {
        let roots = try files().filter { $0.1 == "document" && !relative($0.0).contains("/") }
        var issues = [String]()
        for (url, _, _) in roots {
            let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let expression = try NSRegularExpression(pattern: #"(?:\[[^\]]+\]\(|`)([^`)#]+\.md)(?:#[^)]+)?(?:\)|`)"#, options: [.caseInsensitive])
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: source) else { continue }
                let raw = String(source[valueRange])
                guard !raw.contains("://") else { continue }
                let target = url.deletingLastPathComponent().appendingPathComponent(raw).standardizedFileURL
                guard target.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: target.path) else { continue }
                let path = relative(target)
                if !indexedPaths.contains(path) { issues.append("referenced documentation is not indexed: \(path)") }
            }
        }
        return Array(Set(issues)).sorted()
    }

    func containedURL(_ relativePath: String) throws -> URL {
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            throw ToolError.pathOutsideRoot(relativePath)
        }
        return candidate
    }

    func relative(_ url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
    }

    private func excluded(_ path: String) -> Bool {
        let components = Set(path.split(separator: "/").map(String.init))
        return !components.isDisjoint(with: config.excludePathComponents)
    }

    private func accepts(_ url: URL, path: String) -> Bool {
        let typeAccepted = ["swift", "c", "h", "md", "sh", "json", "yml", "yaml", "pbxproj", "xctestplan"].contains(url.pathExtension.lowercased())
            || url.lastPathComponent == "Package.swift"
            || url.lastPathComponent == "AGENTS.md"
        guard typeAccepted else { return false }
        if let excludes = config.excludeGlobs, excludes.contains(where: { glob($0, matches: path) }) { return false }
        guard let includes = config.includeGlobs, !includes.isEmpty else { return true }
        return includes.contains { glob($0, matches: path) }
    }

    private func glob(_ pattern: String, matches path: String) -> Bool {
        var expression = "^", index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    let afterDouble = pattern.index(after: next)
                    if afterDouble < pattern.endIndex, pattern[afterDouble] == "/" {
                        expression += "(?:.*/)?"; index = pattern.index(after: afterDouble)
                    } else { expression += ".*"; index = afterDouble }
                }
                else { expression += "[^/]*"; index = next }
            } else if character == "?" { expression += "[^/]"; index = pattern.index(after: index) }
            else {
                if ".+()[]{}^$|\\".contains(character) { expression += "\\" }
                expression.append(character); index = pattern.index(after: index)
            }
        }
        return path.range(of: expression + "$", options: .regularExpression) != nil
    }

    private func status(for path: String) -> String {
        config.documentRules
            .filter { path == $0.pathPrefix || path.hasPrefix($0.pathPrefix + "/") }
            .max { $0.pathPrefix.count < $1.pathPrefix.count }?
            .status ?? "Current"
    }
}
