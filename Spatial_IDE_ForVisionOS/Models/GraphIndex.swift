import Foundation

/// `CodeGraph`를 한 번 훑어 만든 조회 캐시. 그래프가 바뀔 때만 다시 만든다.
///
/// 이전에는 선택·강조마다 `graph.nodes`/`graph.edges`를 전부 순회했는데, 노드 수백 개부터는
/// 매 상태 변화가 O(N+E)가 되어 부담이 된다. 여기서 인접 리스트, 부모→자식, 심볼 → 참조 노드를 미리 묶어 둔다.
struct GraphIndex: Sendable {
    let nodesByID: [String: CodeNode]
    /// 부모 ID → 자식 노드들(선언 줄 순서, 없으면 이름 순).
    private let childrenByParent: [String: [CodeNode]]
    /// 노드 ID → 나가는 엣지 / 들어오는 엣지.
    let outgoing: [String: [CodeEdge]]
    let incoming: [String: [CodeEdge]]
    /// 심볼(노드 ID) → 그 심볼을 스니펫 안에서 참조하는 노드 ID들.
    let referencingNodes: [String: Set<String>]
    /// 부모가 없는 노드(모듈).
    let roots: [CodeNode]

    init(graph: CodeGraph) {
        nodesByID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var children: [String: [CodeNode]] = [:]
        var roots: [CodeNode] = []
        for node in graph.nodes {
            if let parentID = node.parentID, nodesByID[parentID] != nil {
                children[parentID, default: []].append(node)
            } else {
                roots.append(node)
            }
        }
        childrenByParent = children.mapValues { siblings in
            siblings.sorted { a, b in
                switch (a.line, b.line) {
                case let (la?, lb?) where la != lb: la < lb
                case (nil, .some): false
                case (.some, nil): true
                default: a.name < b.name
                }
            }
        }
        self.roots = roots.sorted { $0.id < $1.id }

        var outgoing: [String: [CodeEdge]] = [:]
        var incoming: [String: [CodeEdge]] = [:]
        for edge in graph.edges {
            outgoing[edge.from, default: []].append(edge)
            incoming[edge.to, default: []].append(edge)
        }
        self.outgoing = outgoing
        self.incoming = incoming

        var referencing: [String: Set<String>] = [:]
        for node in graph.nodes {
            for symbolID in Set(node.symbolRefs.values) where symbolID != node.id {
                referencing[symbolID, default: []].insert(node.id)
            }
        }
        referencingNodes = referencing
    }

    func children(of id: String) -> [CodeNode] {
        childrenByParent[id] ?? []
    }

    func hasChildren(_ id: String) -> Bool {
        !(childrenByParent[id]?.isEmpty ?? true)
    }

    /// 자식·손자를 모두 센다(칩에 표시).
    func descendantCount(of id: String) -> Int {
        children(of: id).reduce(0) { $0 + 1 + descendantCount(of: $1.id) }
    }

    /// 부모에서 루트까지의 조상 ID(가까운 순).
    func ancestors(of id: String) -> [String] {
        var result: [String] = []
        var current = nodesByID[id]?.parentID
        while let parent = current, !result.contains(parent) {
            result.append(parent)
            current = nodesByID[parent]?.parentID
        }
        return result
    }
}
