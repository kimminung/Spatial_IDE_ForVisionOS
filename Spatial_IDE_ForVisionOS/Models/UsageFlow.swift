import Foundation

/// 사용자가 카드 안에서 탭한 토큰.
struct TokenSelection: Equatable {
    /// 토큰이 들어 있던 노드.
    let nodeID: String
    /// 토큰 텍스트(식별자).
    let text: String
}

/// 선택된 토큰을 기준으로 "쓰임새 흐름"에 포함되는 노드를 계산한다.
///
/// 토큰 텍스트와 이름이 일치하는 노드(예: 토큰 `graph` ↔ 노드 `AppModel.graph`,
/// 토큰 `callDepths` ↔ 노드 `callDepths()`)를 찾고, 토큰이 있던 노드도 함께 포함한다.
/// 결과 집합에 닿는 엣지가 흐름으로 강조된다.
enum UsageFlow {
    static func relatedNodeIDs(for selection: TokenSelection, in graph: CodeGraph) -> Set<String> {
        var related: Set<String> = [selection.nodeID]
        let token = selection.text

        for node in graph.nodes {
            if baseName(of: node.name) == token || lastComponent(of: node.id) == token || node.id == token {
                related.insert(node.id)
            }
        }
        return related
    }

    /// `positions(for:)` → `positions`, `makeEntity(for:)` → `makeEntity`
    private static func baseName(of name: String) -> String {
        if let parenIndex = name.firstIndex(of: "(") {
            return String(name[..<parenIndex])
        }
        return name
    }

    /// `AppModel.graph` → `graph`
    private static func lastComponent(of id: String) -> String {
        id.split(separator: ".").last.map(String.init) ?? id
    }
}
