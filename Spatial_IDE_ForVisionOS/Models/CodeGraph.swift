import Foundation

/// 코드 구조 요소의 종류. 3D 노드의 형태와 색상을 결정한다.
enum CodeNodeKind: String, Codable, CaseIterable, Sendable {
    case module
    case type
    case function
    case variable
}

/// 공간에 배치되는 하나의 코드 노드 (클래스, 함수, 변수 등).
struct CodeNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: CodeNodeKind
    /// 소유 관계상의 부모 노드 ID. 루트(모듈)는 nil.
    let parentID: String?
    /// 코드 카드에 표시할 소스 코드 스니펫. 없으면 "코드 없음"으로 표시한다.
    var codeSnippet: String?
    /// 처음부터 브레이크포인트가 걸려 있는 줄 번호(0부터). 카드 거터를 탭해 런타임에 토글할 수도 있다.
    var breakpointLines: [Int] = []
    /// (스키마 v2) 선언이 있는 소스 파일의 상대 경로. 인덱서가 채운다.
    var file: String? = nil
    /// (스키마 v2) 선언이 시작하는 줄(1부터).
    var line: Int? = nil
    /// (스키마 v2) 이 노드의 스니펫 안에서 쓰인 식별자 → 그것이 가리키는 노드 ID.
    /// 토큰을 선택했을 때 이름 문자열 일치 대신 이 표로 선언·참조 노드를 찾는다(오탐 방지).
    var symbolRefs: [String: String] = [:]

    /// 인덱서가 만든 노드인지(심볼표가 있음). v1 샘플 데이터는 false.
    var hasSymbolTable: Bool { !symbolRefs.isEmpty }
}

/// 엣지의 의미. 흐름 애니메이션의 색·방향·속도가 이 값에 따라 달라진다.
enum CodeEdgeKind: String, Codable, Sendable, CaseIterable {
    /// 구조적 소유(모듈 → 타입, 타입 → 멤버). 실행 흐름이 아니므로 흐리고 느리게 표현.
    case owns
    /// 일반 호출. 기본 펄스가 호출 방향으로 흐른다.
    case calls
    /// 오류 전파. 호출된 쪽에서 호출한 쪽으로 **역방향**의 빨간 펄스가 흐른다.
    case throwsError
    /// 종료로 이어지는 경로(fatalError, exit 등). 짙은 빨간 펄스가 끝에서 감속·소멸한다.
    case terminates
}

/// 두 노드 사이의 관계. `from`이 `to`를 소유/호출한다.
struct CodeEdge: Hashable, Sendable {
    let from: String
    let to: String
    var kind: CodeEdgeKind = .calls
}

// MARK: - Codable (이전 JSON과의 호환: kind, breakpointLines가 없으면 기본값)

extension CodeNode: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, kind, parentID, codeSnippet, breakpointLines, file, line, symbolRefs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(CodeNodeKind.self, forKey: .kind)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        codeSnippet = try c.decodeIfPresent(String.self, forKey: .codeSnippet)
        breakpointLines = try c.decodeIfPresent([Int].self, forKey: .breakpointLines) ?? []
        file = try c.decodeIfPresent(String.self, forKey: .file)
        line = try c.decodeIfPresent(Int.self, forKey: .line)
        symbolRefs = try c.decodeIfPresent([String: String].self, forKey: .symbolRefs) ?? [:]
    }
}

extension CodeEdge: Codable {
    private enum CodingKeys: String, CodingKey { case from, to, kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        kind = try c.decodeIfPresent(CodeEdgeKind.self, forKey: .kind) ?? .calls
    }
}

/// 노드와 엣지의 집합. 인덱서(`Tools/CodeSpaceIndexer`)가 만든 `CodeSpaceGraph.json` 또는 v1 샘플에서 디코딩된다.
/// 조회는 `GraphIndex`(인접 리스트·심볼 참조 캐시)를 통해 하고, 이 구조체는 원본 데이터만 담는다.
struct CodeGraph: Codable, Sendable {
    var nodes: [CodeNode]
    var edges: [CodeEdge]

    private enum CodingKeys: String, CodingKey { case nodes, edges }

    /// ID로 노드를 빠르게 찾기 위한 사전. 반복 조회는 `GraphIndex.nodesByID`를 쓴다.
    var nodesByID: [String: CodeNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    /// 들어오는 엣지가 없는 노드들. 호출 깊이 계산의 시작점.
    var rootNodes: [CodeNode] {
        let targets = Set(edges.map(\.to))
        return nodes.filter { !targets.contains($0.id) }
    }

    /// 각 노드의 호출 깊이(Call Depth)를 BFS로 계산한다.
    /// 루트는 0, 루트가 직접 호출하는 노드는 1, ... 형태로 최단 거리를 사용한다.
    /// 어떤 루트에서도 도달할 수 없는 고립 노드는 깊이 0으로 취급한다.
    func callDepths() -> [String: Int] {
        var adjacency: [String: [String]] = [:]
        for edge in edges {
            adjacency[edge.from, default: []].append(edge.to)
        }

        var depths: [String: Int] = [:]
        var queue: [String] = []

        for root in rootNodes {
            depths[root.id] = 0
            queue.append(root.id)
        }

        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            let currentDepth = depths[current] ?? 0

            for next in adjacency[current] ?? [] where depths[next] == nil {
                depths[next] = currentDepth + 1
                queue.append(next)
            }
        }

        // 순환 등으로 도달하지 못한 노드는 최상위 레벨로 둔다.
        for node in nodes where depths[node.id] == nil {
            depths[node.id] = 0
        }

        return depths
    }
}
