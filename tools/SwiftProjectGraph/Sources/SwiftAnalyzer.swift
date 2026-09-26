import Foundation
import SwiftParser
import SwiftSyntax

final class DeclarationVisitor: SyntaxVisitor {
    private let path: String
    private let converter: SourceLocationConverter
    private var containers = [SymbolRecord]()
    private(set) var symbols = [SymbolRecord]()
    private(set) var edges = [EdgeRecord]()
    private(set) var imports = Set<String>()

    init(path: String, tree: SourceFileSyntax) {
        self.path = path
        converter = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    private func lines(_ node: some SyntaxProtocol) -> (Int, Int) {
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia).line
        return (start, max(start, end))
    }

    private func documentation(_ node: some SyntaxProtocol) -> String {
        let text = node.leadingTrivia.description
        let lines = text.split(separator: "\n").compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("///") { return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("/**") || line.hasPrefix("*") || line.hasSuffix("*/") {
                return line.replacingOccurrences(of: "/**", with: "")
                    .replacingOccurrences(of: "*/", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            }
            return nil
        }
        return compactWhitespace(lines.joined(separator: " "), limit: 800)
    }

    private func access(_ modifiers: DeclModifierListSyntax) -> String {
        let values = Set(modifiers.map { $0.name.text })
        return ["open", "public", "package", "internal", "fileprivate", "private"]
            .first(where: values.contains) ?? "internal"
    }

    @discardableResult
    private func add(
        name: String,
        kind: String,
        signature: String,
        modifiers: DeclModifierListSyntax,
        node: some SyntaxProtocol,
        container: Bool = false
    ) -> SymbolRecord {
        let range = lines(node)
        let qualified = (containers.map(\.name) + [name]).joined(separator: ".")
        let id = "\(path)#\(qualified):\(kind):\(range.0)"
        let symbol = SymbolRecord(
            id: id,
            file: path,
            name: name,
            qualifiedName: qualified,
            kind: kind,
            signature: compactWhitespace(signature),
            documentation: documentation(node),
            access: access(modifiers),
            line: range.0,
            endLine: range.1,
            parentID: containers.last?.id
        )
        symbols.append(symbol)
        if let parent = containers.last {
            edges.append(EdgeRecord(sourceFile: path, fromID: parent.id, toName: qualified, toID: id, kind: "contains", confidence: "syntax", line: range.0))
        }
        if container { containers.append(symbol) }
        return symbol
    }

    private func addInheritance(_ clause: InheritanceClauseSyntax?, from symbol: SymbolRecord) {
        guard let clause else { return }
        for inherited in clause.inheritedTypes {
            let target = compactWhitespace(inherited.type.description)
            let protocolLike = target.hasSuffix("Protocol") || ["Sendable", "Codable", "Hashable", "Equatable", "Observable"].contains(target)
            edges.append(EdgeRecord(
                sourceFile: path,
                fromID: symbol.id,
                toName: target,
                toID: nil,
                kind: protocolLike ? "conforms" : "inherits",
                confidence: "syntax",
                line: symbol.line
            ))
        }
    }

    private func leaveContainer() { _ = containers.popLast() }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        imports.insert(node.path.trimmedDescription)
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = add(name: node.name.text, kind: "class", signature: node.trimmedDescription.components(separatedBy: "{").first ?? node.name.text, modifiers: node.modifiers, node: node, container: true)
        addInheritance(node.inheritanceClause, from: symbol)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { leaveContainer() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = add(name: node.name.text, kind: "actor", signature: node.trimmedDescription.components(separatedBy: "{").first ?? node.name.text, modifiers: node.modifiers, node: node, container: true)
        addInheritance(node.inheritanceClause, from: symbol)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { leaveContainer() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = add(name: node.name.text, kind: "struct", signature: node.trimmedDescription.components(separatedBy: "{").first ?? node.name.text, modifiers: node.modifiers, node: node, container: true)
        addInheritance(node.inheritanceClause, from: symbol)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { leaveContainer() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = add(name: node.name.text, kind: "enum", signature: node.trimmedDescription.components(separatedBy: "{").first ?? node.name.text, modifiers: node.modifiers, node: node, container: true)
        addInheritance(node.inheritanceClause, from: symbol)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { leaveContainer() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = add(name: node.name.text, kind: "protocol", signature: node.trimmedDescription.components(separatedBy: "{").first ?? node.name.text, modifiers: node.modifiers, node: node, container: true)
        addInheritance(node.inheritanceClause, from: symbol)
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { leaveContainer() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = compactWhitespace(node.extendedType.description)
        let symbol = add(name: name, kind: "extension", signature: node.trimmedDescription.components(separatedBy: "{").first ?? name, modifiers: node.modifiers, node: node, container: true)
        edges.append(EdgeRecord(sourceFile: path, fromID: symbol.id, toName: name, toID: nil, kind: "extends", confidence: "syntax", line: symbol.line))
        addInheritance(node.inheritanceClause, from: symbol)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { leaveContainer() }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = add(name: node.name.text, kind: "function", signature: "func \(node.name.text)\(node.signature.trimmedDescription)", modifiers: node.modifiers, node: node, container: true)
        if node.modifiers.contains(where: { $0.name.text == "override" }) {
            edges.append(EdgeRecord(sourceFile: path, fromID: symbol.id, toName: node.name.text, toID: nil, kind: "overrides", confidence: "syntax", line: symbol.line))
        }
        return .visitChildren
    }
    override func visitPost(_ node: FunctionDeclSyntax) { leaveContainer() }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        _ = add(name: "init", kind: "initializer", signature: "init\(node.signature.trimmedDescription)", modifiers: node.modifiers, node: node, container: true)
        return .visitChildren
    }
    override func visitPost(_ node: InitializerDeclSyntax) { leaveContainer() }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        _ = add(name: "subscript", kind: "subscript", signature: "subscript\(node.parameterClause.trimmedDescription) -> \(node.returnClause.type.trimmedDescription)", modifiers: node.modifiers, node: node, container: true)
        return .visitChildren
    }
    override func visitPost(_ node: SubscriptDeclSyntax) { leaveContainer() }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            let name = compactWhitespace(binding.pattern.description, limit: 120)
            let type = binding.typeAnnotation.map { ": \($0.type.trimmedDescription)" } ?? ""
            _ = add(name: name, kind: node.bindingSpecifier.text, signature: "\(node.bindingSpecifier.text) \(name)\(type)", modifiers: node.modifiers, node: binding)
        }
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        _ = add(name: node.name.text, kind: "typealias", signature: node.trimmedDescription, modifiers: node.modifiers, node: node)
        return .skipChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let called = compactWhitespace(node.calledExpression.description, limit: 180)
        let name = called.split(separator: ".").last.map(String.init) ?? called
        if let owner = containers.last, !name.isEmpty {
            let line = lines(node).0
            let isConstruction = name.first?.isUppercase == true
            edges.append(EdgeRecord(sourceFile: path, fromID: owner.id, toName: name, toID: nil, kind: isConstruction ? "constructs" : "calls", confidence: "syntax", line: line))
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard let owner = containers.last else { return .skipChildren }
        let name = node.baseName.text
        guard !name.isEmpty, name != "self", name != "super" else { return .skipChildren }
        edges.append(EdgeRecord(sourceFile: path, fromID: owner.id, toName: name, toID: nil,
                                kind: "references", confidence: "syntax", line: lines(node).0))
        return .skipChildren
    }
}

enum SourceAnalyzer {
    static func parseSwift(path: String, data: Data, status: String) -> ParsedFile {
        let source = String(decoding: data, as: UTF8.self)
        let tree = Parser.parse(source: source)
        let visitor = DeclarationVisitor(path: path, tree: tree)
        visitor.walk(tree)
        return ParsedFile(
            path: path,
            fingerprint: stableHash(data),
            kind: "swift",
            status: status,
            content: source,
            imports: visitor.imports.sorted(),
            symbols: visitor.symbols,
            edges: visitor.edges
        )
    }

    static func parseText(path: String, data: Data, kind: String, status: String) -> ParsedFile {
        let content = String(decoding: data, as: UTF8.self)
        var symbols = [SymbolRecord](), edges = [EdgeRecord](), current: SymbolRecord?
        let heading = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$")
        let shellFunction = try? NSRegularExpression(pattern: "^([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\)\\s*\\{")
        let references = try? NSRegularExpression(pattern: "`([A-Za-z_][A-Za-z0-9_.]+)`")
        for (offset, rawLine) in content.components(separatedBy: .newlines).enumerated() {
            let line = offset + 1, range = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            let match = heading?.firstMatch(in: rawLine, range: range) ?? (kind == "script" ? shellFunction?.firstMatch(in: rawLine, range: range) : nil)
            if let match, match.numberOfRanges >= 2, let nameRange = Range(match.range(at: match.numberOfRanges - 1), in: rawLine) {
                let name = compactWhitespace(String(rawLine[nameRange]), limit: 180)
                let symbolKind = kind == "script" ? "script-function" : "heading"
                let symbol = SymbolRecord(id: "\(path)#\(name):\(symbolKind):\(line)", file: path, name: name,
                                          qualifiedName: name, kind: symbolKind, signature: compactWhitespace(rawLine),
                                          documentation: "", access: "internal", line: line, endLine: line, parentID: nil)
                symbols.append(symbol); current = symbol
            }
            guard let owner = current, let references else { continue }
            for match in references.matches(in: rawLine, range: range) {
                guard let refRange = Range(match.range(at: 1), in: rawLine) else { continue }
                edges.append(EdgeRecord(sourceFile: path, fromID: owner.id, toName: String(rawLine[refRange]), toID: nil,
                                        kind: "references", confidence: "syntax", line: line))
            }
        }
        return ParsedFile(path: path, fingerprint: stableHash(data), kind: kind, status: status, content: content,
                          imports: [], symbols: symbols, edges: edges)
    }
}
