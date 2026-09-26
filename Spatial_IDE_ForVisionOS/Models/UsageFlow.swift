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
/// 1. **심볼 해석(v2)**: 토큰이 있던 노드의 `symbolRefs`에서 토큰 텍스트가 가리키는 노드 ID를 찾고,
///    그 선언 노드 + 그 심볼을 참조하는 모든 노드(`GraphIndex.referencingNodes`)를 흐름에 넣는다.
///    같은 이름의 다른 심볼(다른 타입의 `count`, 지역 변수 `data`)은 섞이지 않는다.
/// 2. **이름 일치(v1 폴백)**: 심볼표가 없는 샘플 데이터에서는 예전처럼 노드 이름과 토큰 텍스트를 비교한다.
enum UsageFlow {
    /// 선택 토큰이 가리키는 심볼(노드 ID). 해석되지 않으면 nil.
    static func resolvedSymbolID(for selection: TokenSelection, in index: GraphIndex) -> String? {
        guard let node = index.nodesByID[selection.nodeID], node.hasSymbolTable else { return nil }
        return node.symbolRefs[selection.text]
    }

    static func relatedNodeIDs(for selection: TokenSelection, in index: GraphIndex) -> Set<String> {
        var related: Set<String> = [selection.nodeID]

        if let symbolID = resolvedSymbolID(for: selection, in: index) {
            related.insert(symbolID)
            related.formUnion(index.referencingNodes[symbolID] ?? [])
            return related
        }

        // 심볼표가 있는데 해석되지 않은 토큰(지역 변수, 외부 프레임워크 심볼)은 그 노드 하나만 강조한다.
        if index.nodesByID[selection.nodeID]?.hasSymbolTable == true {
            return related
        }

        let token = selection.text
        for node in index.nodesByID.values {
            if baseName(of: node.name) == token || lastComponent(of: node.id) == token || node.id == token {
                related.insert(node.id)
            }
        }
        return related
    }

    /// `positions(for:)` → `positions`, `makeEntity(for:)` → `makeEntity`
    static func baseName(of name: String) -> String {
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
