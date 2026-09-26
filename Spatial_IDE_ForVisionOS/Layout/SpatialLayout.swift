import Foundation
import simd

/// 계층(군집) 레이아웃. **보이는 노드만** 배치한다.
///
/// - 각 컨테이너의 자식들은 컨테이너 카드 바로 아래에, 실제 렌더링 크기로 줄을 채우며(flow packing) 놓인다.
/// - 자식 군집은 부모보다 `depthStep`만큼 뒤(-Z)에 있어, 모듈 → 타입 → 멤버로 내려갈수록 한 층씩 들어간다.
/// - 펼친 컨테이너는 "자기 카드 + 자식 블록"을 하나의 덩어리로 취급해 형제와 겹치지 않게 자리를 확보한다.
/// - 결과는 루트 노드가 (0,0,0)에 오는 **레이아웃 로컬 좌표**다. 씬 컨트롤러가 세계 위치·피벗을 정한다.
///
/// 모든 단위는 미터(m).
struct SpatialLayout: Sendable {
    /// 그래프 루트가 놓이는 세계 위치. 기본값은 눈높이 근처, 사용자 정면 1.6m.
    var origin: SIMD3<Float> = [0, 1.35, -1.6]

    /// 한 줄에 채울 최대 폭. 넓을수록 군집이 아래로 덜 자란다(카드가 눈높이 아래로 내려가는 것을 막는다).
    var rowWidth: Float = 3.0
    /// 형제 사이 간격.
    var gapX: Float = 0.10
    var gapY: Float = 0.10
    /// 자식 군집이 부모보다 뒤로 물러나는 거리.
    var depthStep: Float = 0.35

    /// 크기가 아직 보고되지 않은 카드/칩의 추정 크기.
    var defaultCardSize = SIMD2<Float>(0.34, 0.14)
    var defaultChipSize = SIMD2<Float>(0.22, 0.05)

    /// - Parameters:
    ///   - visible: 현재 공간에 있는 노드(`AppModel.visibleNodes`).
    ///   - expanded: 펼친 컨테이너.
    ///   - sizes: 노드 ID → 렌더링 크기(미터). 없으면 기본값.
    ///   - isCard: 노드가 카드인지(아니면 칩).
    func positions(
        visible: [CodeNode],
        index: GraphIndex,
        expanded: Set<String>,
        sizes: [String: SIMD2<Float>],
        isCard: (CodeNode) -> Bool
    ) -> [String: SIMD3<Float>] {
        let visibleIDs = Set(visible.map(\.id))
        var result: [String: SIMD3<Float>] = [:]

        func ownSize(_ node: CodeNode) -> SIMD2<Float> {
            sizes[node.id] ?? (isCard(node) ? defaultCardSize : defaultChipSize)
        }

        func visibleChildren(_ node: CodeNode) -> [CodeNode] {
            guard expanded.contains(node.id) else { return [] }
            return index.children(of: node.id).filter { visibleIDs.contains($0.id) }
        }

        /// 노드 카드 + (펼쳐졌다면) 자식 블록을 합친 크기. 깊이가 얕아(모듈→타입→멤버) 재계산 비용은 작다.
        func blockSize(_ node: CodeNode) -> SIMD2<Float> {
            let own = ownSize(node)
            let children = visibleChildren(node)
            guard !children.isEmpty else { return own }
            let rows = pack(children, blockSize)
            let width = rows.map { rowMetrics($0, blockSize).width }.max() ?? 0
            let height = rows.reduce(Float(0)) { $0 + rowMetrics($1, blockSize).height } + gapY * Float(rows.count)
            return SIMD2<Float>(max(own.x, width), own.y + height)
        }

        /// 노드를 `topCenter` 아래에 두고, 자식 블록을 그 아래 한 층 뒤에 채운다.
        func place(_ node: CodeNode, topCenter: SIMD3<Float>) {
            let own = ownSize(node)
            result[node.id] = SIMD3<Float>(topCenter.x, topCenter.y - own.y / 2, topCenter.z)

            let children = visibleChildren(node)
            guard !children.isEmpty else { return }
            var y = topCenter.y - own.y - gapY
            let z = topCenter.z - depthStep
            for line in pack(children, blockSize) {
                let (rowHeight, width) = rowMetrics(line, blockSize)
                var x = topCenter.x - width / 2
                for child in line {
                    let size = blockSize(child)
                    place(child, topCenter: SIMD3<Float>(x + size.x / 2, y, z))
                    x += size.x + gapX
                }
                y -= rowHeight + gapY
            }
        }

        // 루트들은 한 줄로 나란히.
        let roots = visible.filter { node in
            guard let parentID = node.parentID else { return true }
            return index.nodesByID[parentID] == nil
        }
        let rootsWidth = rowMetrics(roots, blockSize).width
        var x = -rootsWidth / 2
        for root in roots {
            let size = blockSize(root)
            place(root, topCenter: SIMD3<Float>(x + size.x / 2, 0, 0))
            x += size.x + gapX
        }
        return result
    }

    /// 한 줄의 높이(가장 큰 블록)와 전체 폭(블록 폭 합 + 간격).
    private func rowMetrics(_ nodes: [CodeNode], _ size: (CodeNode) -> SIMD2<Float>) -> (height: Float, width: Float) {
        let height = nodes.map { size($0).y }.max() ?? 0
        let width = nodes.reduce(Float(0)) { $0 + size($1).x } + gapX * Float(max(nodes.count - 1, 0))
        return (height, width)
    }

    /// 폭 제한(`rowWidth`) 안에서 왼쪽부터 채워 줄을 나눈다.
    private func pack(_ nodes: [CodeNode], _ size: (CodeNode) -> SIMD2<Float>) -> [[CodeNode]] {
        var rows: [[CodeNode]] = []
        var current: [CodeNode] = []
        var width: Float = 0
        for node in nodes {
            let w = size(node).x
            if !current.isEmpty, width + gapX + w > rowWidth {
                rows.append(current)
                current = []
                width = 0
            }
            width += (current.isEmpty ? 0 : gapX) + w
            current.append(node)
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}
