import SwiftUI
import Observation

/// 특정 노드의 특정 줄에 걸린 브레이크포인트.
struct Breakpoint: Hashable, Sendable {
    let nodeID: String
    /// 0부터 시작하는 줄 번호.
    let line: Int
}

/// 앱 전역 상태. SwiftUI Environment로 주입되어 씬과 뷰가 공유한다.
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

    /// 카드 안에서 탭한 토큰. 같은 토큰을 다시 탭하면 nil로 돌아간다.
    var selectedToken: TokenSelection?

    /// 선택된 토큰의 쓰임새 흐름에 포함되는 노드 집합. 선택이 없으면 nil.
    var highlightedNodeIDs: Set<String>? {
        selectedToken.map { UsageFlow.relatedNodeIDs(for: $0, in: graph) }
    }

    /// 선택 토큰이 "무엇에 담겨 있는지"를 보여줄 소유 체인: 흐름에 포함된 노드들과 그 조상(부모→…→루트).
    /// 이 집합의 노드로 들어오는 `owns` 엣지가 짙은 파란 곡선으로 그려진다. 선택이 없으면 nil.
    var containmentNodeIDs: Set<String>? {
        guard let highlighted = highlightedNodeIDs else { return nil }
        let byID = graph.nodesByID
        var result = highlighted
        for id in highlighted {
            var current = byID[id]?.parentID
            while let parent = current, !result.contains(parent) {
                result.insert(parent)
                current = byID[parent]?.parentID
            }
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

    /// 현재 걸려 있는 브레이크포인트. 그래프 데이터의 `breakpointLines`로 초기화되고,
    /// 카드 거터를 탭하면 토글된다.
    var breakpoints: Set<Breakpoint>

    /// 브레이크포인트가 하나라도 걸린 노드. 이 노드에서 나가는 엣지의 흐름은 "일시정지"로 표시된다.
    var pausedNodeIDs: Set<String> {
        Set(breakpoints.map(\.nodeID))
    }

    /// 공간에 렌더링할 코드 그래프.
    /// `SampleGraph.json`(더미 AST JSON)에서 로드하며, 실패 시 `CodeGraph.sample`로 대체한다.
    var graph: CodeGraph

    /// 노드 배치에 사용하는 레이아웃 파라미터.
    var layout = SpatialLayout()

    init() {
        let graph = GraphLoader.loadBundledSample()
        self.graph = graph
        self.breakpoints = Set(graph.nodes.flatMap { node in
            node.breakpointLines.map { Breakpoint(nodeID: node.id, line: $0) }
        })
    }

    func toggleSelection(_ selection: TokenSelection) {
        selectedToken = (selectedToken == selection) ? nil : selection
        tokenAnchors = [:]   // 카드들이 새 선택에 맞는 위치를 다시 보고한다.
    }

    func toggleBreakpoint(_ breakpoint: Breakpoint) {
        if breakpoints.contains(breakpoint) {
            breakpoints.remove(breakpoint)
        } else {
            breakpoints.insert(breakpoint)
        }
    }
}
