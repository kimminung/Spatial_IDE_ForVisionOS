import Foundation
import SwiftSyntax
import SwiftParser

/// 파일 하나를 순회해 타입/함수/변수 선언과, 각 선언 본문의 참조를 모은다.
///
/// 노드 ID는 `모듈.타입경로.이름(라벨:)` 형태의 안정 식별자다. 파일 경로나 순서에 의존하지 않으므로
/// 코드를 옮겨도 같은 심볼은 같은 ID를 유지한다. (완전한 USR은 IndexStoreDB 연동 시 대체 예정.)
final class DeclarationCollector: SyntaxVisitor {
    private let moduleID: String
    private let relativePath: String
    private let source: String
    private let converter: SourceLocationConverter

    /// 현재 둘러싸고 있는 타입 노드 ID 스택. 비어 있으면 모듈 수준.
    private var typeStack: [String] = []
    /// 확장(`extension Foo`)으로 들어왔는지 표시. 확장은 별도 노드를 만들지 않고 원 타입에 멤버를 합친다.
    private var extensionDepth = 0

    private(set) var declarations: [Declaration] = []
    /// 이 파일에서 확장만 된(선언은 다른 곳에 있는) 타입 이름들.
    private(set) var extendedTypeNames: Set<String> = []

    init(moduleID: String, relativePath: String, source: String, tree: SourceFileSyntax) {
        self.moduleID = moduleID
        self.relativePath = relativePath
        self.source = source
        self.converter = SourceLocationConverter(fileName: relativePath, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    private var currentParentID: String { typeStack.last ?? moduleID }

    private func line(of node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }

    // MARK: - 타입

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { enterType(node.name.text, node, node.memberBlock, keyword: "struct") }
    override func visitPost(_ node: StructDeclSyntax) { leaveType() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { enterType(node.name.text, node, node.memberBlock, keyword: "class") }
    override func visitPost(_ node: ClassDeclSyntax) { leaveType() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { enterType(node.name.text, node, node.memberBlock, keyword: "enum") }
    override func visitPost(_ node: EnumDeclSyntax) { leaveType() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { enterType(node.name.text, node, node.memberBlock, keyword: "actor") }
    override func visitPost(_ node: ActorDeclSyntax) { leaveType() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let kind = enterType(node.name.text, node, node.memberBlock, keyword: "protocol")
        declarations.last?.isProtocolRequirement = true
        return kind
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { leaveType() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // `extension Foo.Bar` → 마지막 구성요소 기준으로 타입 ID를 만든다.
        let typeName = node.extendedType.trimmedDescription
        let typeID = "\(moduleID).\(typeName)"
        extendedTypeNames.insert(typeName)
        typeStack.append(typeID)
        extensionDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeStack.removeLast()
        extensionDepth -= 1
    }

    private func enterType(_ name: String, _ node: some DeclSyntaxProtocol, _ memberBlock: MemberBlockSyntax, keyword: String) -> SyntaxVisitorContinueKind {
        let id = "\(currentParentID).\(name)"
        let decl = Declaration(
            id: id, name: name, kind: .type, parentID: currentParentID,
            file: relativePath, line: line(of: node),
            snippet: typeSnippet(of: node, memberBlock: memberBlock)
        )
        decl.enclosingTypeID = typeStack.last
        declarations.append(decl)
        typeStack.append(id)
        return .visitChildren
    }

    private func leaveType() {
        typeStack.removeLast()
    }

    // MARK: - 함수

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let labels = node.signature.parameterClause.parameters.map { "\($0.firstName.text):" }.joined()
        let name = "\(node.name.text)(\(labels))"
        addCallable(
            name: name, node: node,
            effects: node.signature.effectSpecifiers?.description ?? "",
            body: node.body
        )
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let labels = node.signature.parameterClause.parameters.map { "\($0.firstName.text):" }.joined()
        addCallable(
            name: "init(\(labels))", node: node,
            effects: node.signature.effectSpecifiers?.description ?? "",
            body: node.body
        )
        return .skipChildren
    }

    private func addCallable(name: String, node: some DeclSyntaxProtocol, effects: String, body: CodeBlockSyntax?) {
        var id = "\(currentParentID).\(name)"
        // 같은 이름·라벨의 오버로드(타입만 다른 경우)는 뒤에 번호를 붙여 구분한다.
        var suffix = 2
        while declarations.contains(where: { $0.id == id }) {
            id = "\(currentParentID).\(name)#\(suffix)"
            suffix += 1
        }

        let decl = Declaration(
            id: id, name: name, kind: .function, parentID: currentParentID,
            file: relativePath, line: line(of: node),
            snippet: dedented(node.trimmedDescription, maxLines: 30)
        )
        decl.enclosingTypeID = typeStack.last
        decl.isThrowing = effects.contains("throws")
        decl.isProtocolRequirement = body == nil && isInsideProtocol
        if let body {
            let visitor = ReferenceCollector()
            visitor.walk(body)
            decl.references = visitor.references
            decl.isTerminating = visitor.references.contains { $0.form == .call && terminatingCallNames.contains($0.name) }
        }
        declarations.append(decl)
    }

    /// 프로토콜 본문 안인지(가장 가까운 타입이 프로토콜).
    private var isInsideProtocol: Bool {
        guard let typeID = typeStack.last else { return false }
        return declarations.first { $0.id == typeID }?.isProtocolRequirement == true
    }

    // MARK: - 변수 (타입 멤버 / 모듈 수준만)

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let name = pattern.identifier.text
            let id = "\(currentParentID).\(name)"
            guard !declarations.contains(where: { $0.id == id }) else { continue }

            let decl = Declaration(
                id: id, name: name, kind: .variable, parentID: currentParentID,
                file: relativePath, line: line(of: node),
                snippet: dedented(node.trimmedDescription, maxLines: 24)
            )
            decl.enclosingTypeID = typeStack.last
            decl.typeAnnotation = binding.typeAnnotation?.type.trimmedDescription

            let visitor = ReferenceCollector()
            if let accessors = binding.accessorBlock { visitor.walk(accessors) }
            if let initializer = binding.initializer { visitor.walk(initializer) }
            if let annotation = binding.typeAnnotation { visitor.walk(annotation) }
            decl.references = visitor.references
            declarations.append(decl)
        }
        return .skipChildren
    }

    // MARK: - 스니펫

    /// 타입 카드는 헤더 + 저장 프로퍼티 한 줄 요약 + 멤버 수만 담는다. 함수 본문은 각자 노드가 된다.
    private func typeSnippet(of node: some DeclSyntaxProtocol, memberBlock: MemberBlockSyntax) -> String {
        let start = node.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = memberBlock.leftBrace.endPositionBeforeTrailingTrivia.utf8Offset
        let utf8 = Array(source.utf8)
        let headerBytes = utf8[min(start, utf8.count)..<min(end, utf8.count)]
        var lines = [String(decoding: headerBytes, as: UTF8.self).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")]

        var functionCount = 0
        var propertyCount = 0
        for member in memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                propertyCount += 1
                var firstLine = (variable.trimmedDescription.split(separator: "\n").first.map(String.init) ?? "")
                    .trimmingCharacters(in: .whitespaces)
                // 계산 프로퍼티는 본문을 생략하되 중괄호는 균형을 맞춘다(접힘 검출이 중괄호를 센다).
                if firstLine.hasSuffix("{") { firstLine += " … }" }
                lines.append("    " + firstLine)
            } else if member.decl.is(FunctionDeclSyntax.self) || member.decl.is(InitializerDeclSyntax.self) {
                functionCount += 1
            } else if let enumCase = member.decl.as(EnumCaseDeclSyntax.self) {
                lines.append("    " + enumCase.trimmedDescription.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }!)
            }
        }
        if functionCount > 0 {
            lines.append("    // 함수 \(functionCount)개 — 각각 별도 노드")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}

/// 공통 들여쓰기를 걷어내고 줄 수를 제한한다. 제한을 넘으면 중간을 생략하고 마지막 줄(닫는 중괄호)은 남긴다.
func dedented(_ text: String, maxLines: Int) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let indents = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { $0.prefix { $0 == " " }.count }
    let common = indents.min() ?? 0
    lines = lines.enumerated().map { index, line in
        index == 0 ? line : String(line.dropFirst(min(common, line.prefix { $0 == " " }.count)))
    }
    if lines.count > maxLines {
        let omitted = lines.count - maxLines
        lines = Array(lines.prefix(maxLines - 2)) + ["    // … \(omitted + 1)줄 생략", lines.last ?? "}"]
    }
    return lines.joined(separator: "\n")
}
