import SwiftUI
import Observation

/// 특정 노드의 특정 줄에 걸린 브레이크포인트.
struct Breakpoint: Hashable, Sendable {
    let nodeID: String
    /// 0부터 시작하는 줄 번호.
    let line: Int
}

/// 접힌 컨테이너 사이(또는 카드와 접힌 컨테이너 사이)로 묶인 호출 관계. 배치 라인 메시로 그린다.
struct ContextEdge: Hashable, Sendable {
    let from: String
    let to: String
    /// 이 한 줄에 묶인 원본 엣지 수.
    let weight: Int
}

/// 앱 전역 상태. SwiftUI Environment로 주입되어 씬과 뷰가 공유한다.
///
/// **포커스 모델(시맨틱 줌)**: 그래프 전체를 한 번에 그리지 않는다. 컨테이너(모듈·타입)는 펼치기 전까지
/// 작은 칩 하나로 보이고, 펼치면 자기 카드와 자식들이 나타난다. 동시에 떠 있는 코드 카드는
/// `cardBudget`을 넘지 않도록 가장 오래 전에 펼친 컨테이너부터 자동으로 접는다.
@Observable
final class AppModel {
    /// `ImmersiveSpace(id:)`와 `openImmersiveSpace(id:)`에서 공유하는 식별자.
    static let immersiveSpaceID = "CodeSpaceImmersiveSpace"

    /// 런처 윈도우의 식별자. `WindowGroup(id:)`와 `dismissWindow(id:)`에서 공유한다.
    static let launcherWindowID = "Launcher"

    /// 현재 몰입 스타일. 기본은 `.progressive`로, 디지털 크라운을 돌려 패스스루가 걷히는 범위
    /// (몰입도)를 5%~100% 사이에서 조절할 수 있다. 앱이 열릴 때는 35%에서 시작한다.
    var immersionStyle: ImmersionStyle = .progressive(0.05...1.0, initialAmount: 0.35)

    /// 현재 몰입도(0~1). 크라운 조작에 따라 `onImmersionChange`가 갱신한다. `.mixed`에서는 0.
    var immersionAmount: Double = 0

    /// ImmersiveSpace가 현재 열려 있는지 여부. 중복으로 열기를 시도하지 않도록 막는 데 사용한다.
    var isImmersiveSpaceOpened = false

    // MARK: - 그래프

    /// 공간에 렌더링할 코드 그래프. 바뀌면 조회 캐시를 다시 만든다.
    var graph: CodeGraph {
        didSet { index = GraphIndex(graph: graph) }
    }

    /// 인접 리스트·심볼 참조 캐시.
    private(set) var index: GraphIndex

    /// 노드 배치에 사용하는 레이아웃 파라미터.
    var layout = SpatialLayout()

    // MARK: - 포커스(펼침) 상태

    /// 자식이 보이도록 펼친 컨테이너 노드.
    private(set) var expandedIDs: Set<String> = []
    /// 펼친 순서(오래된 것부터). 예산 초과 시 앞에서부터 접는다.
    private var expansionOrder: [String] = []
    /// 동시에 떠 있을 수 있는 코드 카드 수의 상한. 함수 카드가 약 0.35 m 높이라 16장이면 대략 3줄 × 1 m 안에 들어간다.
    var cardBudget = 16

    /// 카드/칩이 보고한 렌더링 크기(포인트). 레이아웃이 겹침 없이 배치하는 데 쓴다.
    private(set) var cardSizes: [String: CGSize] = [:]

    /// 현재 공간에 존재하는 노드(카드 또는 칩). 루트에서 펼친 컨테이너를 따라 내려가며 모은다.
    /// 짧은 프로퍼티(`isCompactMember`)는 부모 타입 카드 안의 한 줄로만 보이고 자기 노드를 갖지 않는다.
    var visibleNodes: [CodeNode] {
        var result: [CodeNode] = []
        func visit(_ node: CodeNode) {
            result.append(node)
            guard expandedIDs.contains(node.id) else { return }
            for child in index.children(of: node.id) where !isCompactMember(child) { visit(child) }
        }
        for root in index.roots { visit(root) }
        return result
    }

    /// 타입의 짧은 저장/계산 프로퍼티. 인덱서가 타입 카드 스니펫에 이미 한 줄 요약으로 넣어 두므로 별도 카드를 만들지 않는다.
    /// (변수 노드가 전체의 40%가 넘어, 모두 카드로 펼치면 한 타입만 펼쳐도 카드가 수십 장이 된다.)
    /// 그래프 노드로는 남아 있어 심볼 해석·흐름 강조는 그대로 동작한다.
    func isCompactMember(_ node: CodeNode) -> Bool {
        guard node.kind == .variable, let parentID = node.parentID,
              index.nodesByID[parentID]?.kind == .type else { return false }
        let lineCount = node.codeSnippet?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
        return lineCount <= 3
    }

    var visibleNodeIDs: Set<String> { Set(visibleNodes.map(\.id)) }

    /// 코드 카드로 그릴 노드인지. **펼친 노드만** 카드다. 나머지는 칩이다:
    /// - 컨테이너(모듈·타입) 칩: 이름 + 안에 접힌 자손 수. 탭 → 자식들이 나타난다.
    /// - 잎(함수·긴 프로퍼티) 칩: 선언 첫 줄(시그니처) 한 줄. 탭 → 본문 카드가 열린다.
    /// 한 타입에 멤버가 수십 개여도 시그니처 한 줄씩이면 눈높이 안에 들어오고, 본문은 보고 싶은 것만 연다.
    func isCard(_ node: CodeNode) -> Bool {
        expandedIDs.contains(node.id)
    }

    /// 펼칠 수 있는 노드: 자식이 있거나(컨테이너), 본문이 있는 잎(함수·프로퍼티).
    func isExpandable(_ id: String) -> Bool {
        if index.hasChildren(id) { return true }
        guard let node = index.nodesByID[id] else { return false }
        return node.codeSnippet?.isEmpty == false
    }

    var cardCount: Int { visibleNodes.filter(isCard).count }

    func toggleExpansion(_ id: String) {
        if expandedIDs.contains(id) { collapse(id) } else { expand(id) }
    }

    func expand(_ id: String) {
        guard isExpandable(id), !expandedIDs.contains(id) else { return }
        expandedIDs.insert(id)
        expansionOrder.removeAll { $0 == id }
        expansionOrder.append(id)
        enforceCardBudget(protecting: Set(index.ancestors(of: id) + [id]))
    }

    /// 자신과 그 아래 펼쳐진 것들을 모두 접는다.
    func collapse(_ id: String) {
        guard expandedIDs.contains(id) else { return }
        var stack = [id]
        while let current = stack.popLast() {
            expandedIDs.remove(current)
            expansionOrder.removeAll { $0 == current }
            for child in index.children(of: current) where expandedIDs.contains(child.id) {
                stack.append(child.id)
            }
        }
    }

    /// 특정 노드가 공간에 보이도록 조상들을 모두 펼친다(검색 결과, 흐름 따라가기).
    func reveal(_ id: String) {
        for ancestor in index.ancestors(of: id).reversed() {
            expand(ancestor)
        }
    }

    private func enforceCardBudget(protecting protected: Set<String>) {
        var candidates = expansionOrder.filter { !protected.contains($0) }
        while cardCount > cardBudget, !candidates.isEmpty {
            collapse(candidates.removeFirst())
        }
    }

    func setCardSize(nodeID: String, size: CGSize) {
        if cardSizes[nodeID] != size { cardSizes[nodeID] = size }
    }

    // MARK: - 엣지 집합

    /// 보이는 노드 사이의 엣지(리치 엔티티로 그림)와, 접힌 컨테이너로 묶인 컨텍스트 엣지(배치 라인 메시).
    ///
    /// - 소유(`owns`) 엣지는 자식이 **카드**(본문이 열린 노드)일 때만 그린다. 칩은 부모 근처에 배치되어 소유가 레이아웃으로
    ///   드러나므로 칩마다 실린더 엣지를 다는 것은 낭비다.
    /// - 호출 계열 엣지의 끝점 중 하나라도 숨겨져 있으면, 각 끝점을 가장 가까운 보이는 조상으로 치환해 한 줄로 묶는다.
    var edgeSets: (focus: [CodeEdge], context: [ContextEdge]) {
        let visible = visibleNodeIDs
        let cards = Set(visibleNodes.filter(isCard).map(\.id))

        var focus: [CodeEdge] = []
        var weights: [ContextKey: Int] = [:]
        for edge in graph.edges {
            let fromVisible = visible.contains(edge.from)
            let toVisible = visible.contains(edge.to)
            if fromVisible && toVisible {
                if edge.kind != .owns || cards.contains(edge.to) { focus.append(edge) }
                continue
            }
            guard edge.kind != .owns,
                  let a = representative(of: edge.from, visible: visible),
                  let b = representative(of: edge.to, visible: visible),
                  a != b else { continue }
            weights[ContextKey(from: a, to: b), default: 0] += 1
        }
        let context = weights.map { ContextEdge(from: $0.key.from, to: $0.key.to, weight: $0.value) }
            .sorted { ($0.from, $0.to) < ($1.from, $1.to) }
        return (focus, context)
    }

    private struct ContextKey: Hashable { let from: String; let to: String }

    /// 노드 자신이 보이면 자신, 아니면 가장 가까운 보이는 조상.
    private func representative(of id: String, visible: Set<String>) -> String? {
        var current: String? = id
        while let node = current {
            if visible.contains(node) { return node }
            current = index.nodesByID[node]?.parentID
        }
        return nil
    }

    // MARK: - 검색

    /// 이름·ID에 질의가 포함된 노드. 접두 일치를 먼저, 그다음 짧은 ID 순.
    func searchNodes(_ query: String, limit: Int = 12) -> [CodeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 2 else { return [] }
        let matches = graph.nodes.filter { $0.name.lowercased().contains(trimmed) || $0.id.lowercased().contains(trimmed) }
        return matches.sorted { a, b in
            let aPrefix = a.name.lowercased().hasPrefix(trimmed)
            let bPrefix = b.name.lowercased().hasPrefix(trimmed)
            if aPrefix != bPrefix { return aPrefix }
            return a.id.count < b.id.count
        }.prefix(limit).map { $0 }
    }

    // MARK: - 토큰 선택 / 흐름

    /// 카드 안에서 탭한 토큰. 같은 토큰을 다시 탭하면 nil로 돌아간다.
    var selectedToken: TokenSelection?

    /// 선택된 토큰의 쓰임새 흐름에 포함되는 노드 집합. 선택이 없으면 nil.
    var highlightedNodeIDs: Set<String>? {
        selectedToken.map { UsageFlow.relatedNodeIDs(for: $0, in: index) }
    }

    /// 선택 토큰이 "무엇에 담겨 있는지"를 보여줄 소유 체인: 흐름에 포함된 노드들과 그 조상(부모→…→루트).
    /// 이 집합의 노드로 들어오는 `owns` 엣지가 짙은 파란 곡선으로 그려진다. 선택이 없으면 nil.
    var containmentNodeIDs: Set<String>? {
        guard let highlighted = highlightedNodeIDs else { return nil }
        var result = highlighted
        for id in highlighted {
            result.formUnion(index.ancestors(of: id))
        }
        return result
    }

    /// 선택된 토큰 텍스트가 각 카드 안에서 놓인 위치(노드 중심 기준 오프셋, 미터).
    /// 카드(SwiftUI)가 레이아웃을 측정해 보고한다. 선택이 바뀌면 비워진다.
    var tokenAnchors: [String: SIMD3<Float>] = [:]

    /// 엣지 끝점에 실제로 적용할 오프셋: 선택이 있을 때, 흐름에 포함된 노드의 토큰 위치만.
    /// 선택이 없으면 비어 있어 엣지가 노드 중심에 붙는다.
    var activeEdgeAnchors: [String: SIMD3<Float>] {
        guard let highlighted = highlightedNodeIDs else { return [:] }
        return tokenAnchors.filter { highlighted.contains($0.key) }
    }

    func setTokenAnchor(nodeID: String, offset: SIMD3<Float>?) {
        if let offset {
            if tokenAnchors[nodeID] != offset { tokenAnchors[nodeID] = offset }
        } else if tokenAnchors[nodeID] != nil {
            tokenAnchors.removeValue(forKey: nodeID)
        }
    }

    /// 토큰 선택 토글. 새로 선택한 토큰이 가리키는 선언이 접혀 있으면 그 자리까지 펼쳐 흐름의 목적지가 보이게 한다.
    func toggleSelection(_ selection: TokenSelection) {
        if selectedToken == selection {
            selectedToken = nil
        } else {
            selectedToken = selection
            if let symbolID = UsageFlow.resolvedSymbolID(for: selection, in: index), !visibleNodeIDs.contains(symbolID) {
                reveal(symbolID)
            }
        }
        tokenAnchors = [:]   // 카드들이 새 선택에 맞는 위치를 다시 보고한다.
    }

    /// 검색 결과 등에서 노드 자체를 선택: 그 노드를 드러내고 본문을 열며, 이름 토큰을 선택한 것과 같게 취급한다.
    func focus(on nodeID: String) {
        guard let node = index.nodesByID[nodeID] else { return }
        reveal(nodeID)
        if !isCompactMember(node) { expand(nodeID) }
        selectedToken = TokenSelection(nodeID: nodeID, text: UsageFlow.baseName(of: node.name))
        tokenAnchors = [:]
    }

    // MARK: - 브레이크포인트

    /// 현재 걸려 있는 브레이크포인트. 그래프 데이터의 `breakpointLines`로 초기화되고,
    /// 카드 거터를 탭하면 토글된다.
    var breakpoints: Set<Breakpoint>

    /// 브레이크포인트가 하나라도 걸린 노드. 이 노드에서 나가는 엣지의 흐름은 "일시정지"로 표시된다.
    var pausedNodeIDs: Set<String> {
        Set(breakpoints.map(\.nodeID))
    }

    func toggleBreakpoint(_ breakpoint: Breakpoint) {
        if breakpoints.contains(breakpoint) {
            breakpoints.remove(breakpoint)
        } else {
            breakpoints.insert(breakpoint)
        }
    }

    // MARK: - 초기화

    init() {
        let graph = GraphLoader.loadBundledGraph()
        self.graph = graph
        self.index = GraphIndex(graph: graph)
        self.breakpoints = Set(graph.nodes.flatMap { node in
            node.breakpointLines.map { Breakpoint(nodeID: node.id, line: $0) }
        })
        // 처음에는 루트(모듈)만 펼쳐서 최상위 타입들이 칩으로 보이게 한다.
        for root in index.roots where index.hasChildren(root.id) {
            expandedIDs.insert(root.id)
            expansionOrder.append(root.id)
        }
    }
}
