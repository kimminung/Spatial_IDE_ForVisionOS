import Foundation
import SwiftSyntax

/// 함수 본문 안의 호출·값·타입 참조를 모은다. 이름만 모으고, 어느 노드인지는 `SymbolResolver`가 정한다.
final class ReferenceCollector: SyntaxVisitor {
    private(set) var references: [Reference] = []
    private var tryDepth = 0

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        tryDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: TryExprSyntax) {
        tryDepth -= 1
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let insideTry = tryDepth > 0
        if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            if name.first?.isUppercase == true {
                references.append(Reference(name: name, form: .type, base: nil, insideTry: insideTry))
            } else {
                references.append(Reference(name: name, form: .call, base: nil, insideTry: insideTry))
            }
        } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let base = member.base?.trimmedDescription
            references.append(Reference(
                name: member.declName.baseName.text, form: .call,
                base: base == "self" ? nil : base, insideTry: insideTry
            ))
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // 호출의 피호출자는 위에서 처리했다. 값 참조(`appModel.graph`, `self.layout`)만 여기서 다룬다.
        if let parent = node.parent, let call = parent.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id {
            return .visitChildren
        }
        let base = node.base?.trimmedDescription
        references.append(Reference(
            name: node.declName.baseName.text, form: .value,
            base: base == "self" ? nil : base, insideTry: tryDepth > 0
        ))
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        // `foo.bar` 의 `bar`(declName)는 MemberAccess에서 처리됐고, 여기선 단독 식별자와 base만 다룬다.
        if let parent = node.parent {
            if let member = parent.as(MemberAccessExprSyntax.self), member.declName.id == node.id { return .skipChildren }
            if let call = parent.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id { return .skipChildren }
        }
        let name = node.baseName.text
        guard name != "self", name != "Self" else { return .skipChildren }
        references.append(Reference(
            name: name, form: name.first?.isUppercase == true ? .type : .value,
            base: nil, insideTry: tryDepth > 0
        ))
        return .skipChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        references.append(Reference(name: node.name.text, form: .type, base: nil, insideTry: false))
        return .visitChildren
    }
}
