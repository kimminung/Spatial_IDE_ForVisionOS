import Foundation
import SwiftSyntax

/// 1차 패스에서 수집한 선언 하나.
final class Declaration {
    enum Kind: String { case module, type, function, variable }

    let id: String
    let name: String
    let kind: Kind
    var parentID: String?
    let file: String?
    let line: Int?
    var snippet: String

    /// 함수/이니셜라이저가 `throws`인지.
    var isThrowing = false
    /// 본문에 fatalError/exit 등 종료 호출이 있는지.
    var isTerminating = false
    /// 프로토콜 요구사항(본문 없음)인지. 이름 해석 시 구체 구현보다 우선순위가 낮다.
    var isProtocolRequirement = false
    /// 선언이 속한 타입 노드 ID(멤버라면). 모듈 수준이면 nil.
    var enclosingTypeID: String?
    /// 변수의 타입 주석 텍스트(`let appModel: AppModel` → "AppModel"). 멤버 호출 해석에 쓴다.
    var typeAnnotation: String?

    /// 본문에서 발견한 참조들. 2차 패스에서 노드 ID로 해석된다.
    var references: [Reference] = []

    init(id: String, name: String, kind: Kind, parentID: String?, file: String?, line: Int?, snippet: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parentID = parentID
        self.file = file
        self.line = line
        self.snippet = snippet
    }
}

/// 함수 본문(또는 변수 접근자/초기값) 안의 식별자 참조.
struct Reference {
    enum Form {
        /// `foo(...)`, `bar.foo(...)`, `Type.foo(...)` — 호출.
        case call
        /// `foo`, `self.foo`, `bar.foo` — 값 참조(호출 아님).
        case value
        /// `Foo` 타입 이름(타입 위치 또는 `Foo(...)` 생성).
        case type
    }

    let name: String
    let form: Form
    /// `bar.foo`에서 `bar`. 없으면 nil. `self`는 nil로 정규화한다.
    let base: String?
    /// `try` 표현식 안에 있었는지(오류 전파 엣지 판단).
    let insideTry: Bool
}

/// 종료로 이어지는 호출 이름.
let terminatingCallNames: Set<String> = ["fatalError", "exit", "abort", "preconditionFailure", "assertionFailure"]
