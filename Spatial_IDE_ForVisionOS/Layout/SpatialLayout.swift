import Foundation
import simd

/// 계층 레이아웃. **보이는 노드만** 배치한다.
///
/// 두 층으로 나뉜다.
/// - **지도 층(뒤)**: 루트(모듈) 카드와 그 자식(타입 칩)이 줄을 채우며(row packing) 놓인다. 칩 사이를 넉넉히 띄우고
///   줄이 내려갈수록 `mapStepDepth`씩 크게 물러나는 계단형이어서, 정면에서 봐도 엣지가 옆으로 퍼지지 않고 뒤로 뻗는다.
///   펼치기와 무관하게 자리가 바뀌지 않아 공간 기억의 기준이 된다.
/// - **열람 층(앞)**: 타입을 펼치면 그 타입 카드와 멤버 칩/카드들이 타입의 그리드 자리에서 사용자 쪽(+Z)으로 `forwardStep`만큼
///   **앞으로 나와**, 그리드 윗선에 맞춰 **아래로 길게** 한 열로 쌓인다(몰입 공간이니 아래로 밀어 펼친다). 열 높이가
///   `maxColumnHeight`를 넘으면 오른쪽에 다음 열을 만든다. 펼친 타입이 여럿이면 블록끼리 `blockMargin` 이상 떨어지도록
///   옆으로 밀어내 겹치지 않게 한다.
///
/// 카드 사이 간격(`cardGap`)은 칩 사이 간격(`chipGap`)보다 넓다. 카드는 글자가 빽빽해 엣지·화살촉이 오갈 여백이 필요하다.
/// 결과는 루트 노드가 (0,0,0)에 오는 **레이아웃 로컬 좌표**다. 씬 컨트롤러가 세계 위치·피벗을 정한다. 모든 단위는 미터(m).
struct SpatialLayout: Sendable {
    /// 그래프 루트가 놓이는 세계 위치. 기본값은 눈높이 근처, 사용자 정면 1.6m.
    var origin: SIMD3<Float> = [0, 1.35, -1.6]

    /// 지도 층 줄의 최대 폭.
    var rowWidth: Float = 4.0
    /// 열람 층 한 열의 최대 높이. 그리드 윗선(눈높이 약 1.25 m)에서 바닥 근처까지. 넘으면 오른쪽에 새 열.
    var maxColumnHeight: Float = 1.35

    /// 코드 카드 사이 간격(가로/세로).
    var cardGap = SIMD2<Float>(0.32, 0.20)
    /// 지도 층 칩 사이 간격(가로/세로). 넉넉해야 정면에서 엣지가 칩 사이로 뒤로 뻗는 것이 보인다.
    var chipGap = SIMD2<Float>(0.30, 0.10)
    /// 열람 층 시그니처 칩 사이 간격(세로 목록이라 촘촘해도 된다).
    var listChipGap = SIMD2<Float>(0.16, 0.06)

    /// 지도 층: 루트 아래 첫 줄이 물러나는 거리, 줄이 하나 늘 때마다 추가로 물러나는 거리.
    var depthStep: Float = 0.45
    var mapStepDepth: Float = 0.28
    /// 열람 층이 지도 층보다 사용자 쪽으로 나오는 거리, 열이 하나 늘 때마다 물러나는 거리.
    var forwardStep: Float = 0.6
    var columnStepDepth: Float = 0.12
    /// 서로 다른 열람 블록 사이에 확보하는 가로 여백.
    var blockMargin: Float = 0.30

    /// 크기가 아직 보고되지 않은 카드/칩의 추정 크기.
    var defaultCardSize = SIMD2<Float>(0.34, 0.14)
    var defaultChipSize = SIMD2<Float>(0.22, 0.05)

    func positions(
        visible: [CodeNode],
        index: GraphIndex,
        expanded: Set<String>,
        sizes: [String: SIMD2<Float>],
        isCard: (CodeNode) -> Bool
    ) -> [String: SIMD3<Float>] {
        let visibleIDs = Set(visible.map(\.id))
        var result: [String: SIMD3<Float>] = [:]

        func size(_ node: CodeNode) -> SIMD2<Float> {
            sizes[node.id] ?? (isCard(node) ? defaultCardSize : defaultChipSize)
        }
        /// 열람 층 안에서의 간격: 카드는 넓게, 시그니처 칩은 촘촘하게.
        func listGap(_ node: CodeNode) -> SIMD2<Float> {
            isCard(node) ? cardGap : listChipGap
        }
        func visibleChildren(_ node: CodeNode) -> [CodeNode] {
            guard expanded.contains(node.id) else { return [] }
            return index.children(of: node.id).filter { visibleIDs.contains($0.id) }
        }
        func isRoot(_ node: CodeNode) -> Bool {
            guard let parentID = node.parentID else { return true }
            return index.nodesByID[parentID] == nil
        }
        func isPulledForward(_ node: CodeNode) -> Bool {
            expanded.contains(node.id) && index.hasChildren(node.id)
        }

        // MARK: 열람 블록 치수

        struct Block {
            let container: CodeNode
            let includeContainer: Bool
            let columns: [[CodeNode]]
            let width: Float
            var x: Float
            let z: Float
        }

        func makeBlock(_ container: CodeNode, includeContainer: Bool, anchorX: Float, z: Float) -> Block? {
            let members = visibleChildren(container)
            guard !members.isEmpty || includeContainer else { return nil }
            let items = includeContainer ? [container] + members : members
            let columns = pack(items, along: \.y, limit: maxColumnHeight, size, listGap)
            var width: Float = 0
            for (position, column) in columns.enumerated() {
                width += metrics(column, size, listGap).maxX
                if position + 1 < columns.count { width += cardGap.x }
            }
            return Block(container: container, includeContainer: includeContainer, columns: columns, width: width, x: anchorX, z: z)
        }

        /// 중첩 블록의 시작 높이(그 타입 카드의 윗변).
        var nestedTops: [String: Float] = [:]

        /// 블록을 `top` 높이에서 아래로 쌓아 배치한다. 멤버 중 펼친 중첩 타입은 그 카드 앞에 자기 블록을 만든다.
        func placeBlock(_ block: Block, top: Float) {
            var x = block.x - block.width / 2
            var z = block.z
            var nested: [Block] = []
            for column in block.columns {
                let m = metrics(column, size, listGap)
                var y = top
                for child in column {
                    let s = size(child)
                    let center = SIMD3<Float>(x + m.maxX / 2, y - s.y / 2, z)
                    result[child.id] = center
                    if child.id != block.container.id, isPulledForward(child),
                       let inner = makeBlock(child, includeContainer: false, anchorX: center.x, z: center.z + forwardStep) {
                        nested.append(inner)
                        nestedTops[child.id] = center.y + s.y / 2
                    }
                    y -= s.y + listGap(child).y
                }
                x += m.maxX + cardGap.x
                z -= columnStepDepth
            }
            for inner in separate(nested) {
                placeBlock(inner, top: nestedTops[inner.container.id] ?? top)
            }
        }

        /// 블록들이 가로로 겹치지 않도록 왼쪽부터 차례로 밀어낸다.
        func separate(_ blocks: [Block]) -> [Block] {
            var sorted = blocks.sorted { $0.x < $1.x }
            for i in 1..<max(sorted.count, 1) {
                let previous = sorted[i - 1]
                let minX = previous.x + previous.width / 2 + blockMargin + sorted[i].width / 2
                if sorted[i].x < minX { sorted[i].x = minX }
            }
            // 밀어낸 만큼 전체를 되돌려 원래 무게중심 근처에 두면 한쪽으로 치우치지 않는다.
            if !blocks.isEmpty {
                let shift = (blocks.map(\.x).reduce(0, +) - sorted.map(\.x).reduce(0, +)) / Float(blocks.count)
                for i in sorted.indices { sorted[i].x += shift }
            }
            return sorted
        }

        // MARK: 지도 층

        func placeMap(root: CodeNode, topCenter: SIMD3<Float>) {
            let own = size(root)
            result[root.id] = SIMD3<Float>(topCenter.x, topCenter.y - own.y / 2, topCenter.z)

            // 펼친 컨테이너는 그리드에 칩 크기 자리만 남기고, 자기 카드는 멤버들과 함께 열람 층으로 나간다.
            func footprint(_ child: CodeNode) -> SIMD2<Float> { isPulledForward(child) ? defaultChipSize : size(child) }
            func mapGap(_ child: CodeNode) -> SIMD2<Float> { chipGap }

            let gridTop = topCenter.y - own.y
            var y = gridTop
            var z = topCenter.z - depthStep
            // 열람 블록은 어느 줄의 타입을 펼치든 같은 읽기 거리(그리드 첫 줄보다 forwardStep 앞)에 놓는다.
            let browseZ = topCenter.z - depthStep + forwardStep
            var blocks: [Block] = []
            for line in pack(visibleChildren(root), along: \.x, limit: rowWidth, footprint, mapGap) {
                let m = metrics(line, footprint, mapGap)
                y -= m.gapY
                var x = topCenter.x - m.spanX / 2
                for (position, child) in line.enumerated() {
                    let s = footprint(child)
                    let center = SIMD3<Float>(x + s.x / 2, y - s.y / 2, z)
                    if isPulledForward(child) {
                        if let block = makeBlock(child, includeContainer: true, anchorX: center.x, z: browseZ) {
                            blocks.append(block)
                        }
                    } else {
                        result[child.id] = center
                    }
                    x += s.x
                    if position + 1 < line.count { x += chipGap.x }
                }
                y -= m.maxY
                z -= mapStepDepth
            }

            // 열람 블록은 그리드 윗선에서 시작해 아래로 뻗는다. 블록끼리는 겹치지 않게 옆으로 밀어낸다.
            for block in separate(blocks) {
                placeBlock(block, top: gridTop)
            }
        }

        // 루트들은 한 줄로 나란히.
        let roots = visible.filter(isRoot)
        let rootsMetrics = metrics(roots, size, { _ in cardGap })
        var x = -rootsMetrics.spanX / 2
        for (position, root) in roots.enumerated() {
            let s = size(root)
            placeMap(root: root, topCenter: SIMD3<Float>(x + s.x / 2, 0, 0))
            x += s.x
            if position + 1 < roots.count { x += cardGap.x }
        }
        return result
    }

    // MARK: - 묶음 치수

    private struct GroupMetrics {
        /// 가로로 이어 붙였을 때의 전체 폭 / 세로로 쌓았을 때의 전체 높이(간격 포함).
        var spanX: Float = 0
        var spanY: Float = 0
        /// 가장 넓은/높은 항목.
        var maxX: Float = 0
        var maxY: Float = 0
        /// 묶음 안에서 가장 큰 간격.
        var gapX: Float = 0
        var gapY: Float = 0
    }

    private func metrics(
        _ nodes: [CodeNode],
        _ size: (CodeNode) -> SIMD2<Float>,
        _ gap: (CodeNode) -> SIMD2<Float>
    ) -> GroupMetrics {
        var m = GroupMetrics()
        for (position, node) in nodes.enumerated() {
            let s = size(node)
            let g = gap(node)
            m.spanX += s.x
            m.spanY += s.y
            m.maxX = max(m.maxX, s.x)
            m.maxY = max(m.maxY, s.y)
            m.gapX = max(m.gapX, g.x)
            m.gapY = max(m.gapY, g.y)
            if position + 1 < nodes.count {
                let next = gap(nodes[position + 1])
                m.spanX += max(g.x, next.x)
                m.spanY += max(g.y, next.y)
            }
        }
        return m
    }

    /// 한 축의 길이 제한 안에서 앞에서부터 채워 묶음을 나눈다(`axis`가 `.x`면 줄, `.y`면 열).
    private func pack(
        _ nodes: [CodeNode],
        along axis: KeyPath<SIMD2<Float>, Float>,
        limit: Float,
        _ size: (CodeNode) -> SIMD2<Float>,
        _ gap: (CodeNode) -> SIMD2<Float>
    ) -> [[CodeNode]] {
        var groups: [[CodeNode]] = []
        var current: [CodeNode] = []
        var used: Float = 0
        for node in nodes {
            let extent = size(node)[keyPath: axis]
            let spacing = current.last.map { max(gap($0)[keyPath: axis], gap(node)[keyPath: axis]) } ?? 0
            if !current.isEmpty, used + spacing + extent > limit {
                groups.append(current)
                current = []
                used = 0
            }
            used += (current.isEmpty ? 0 : spacing) + extent
            current.append(node)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}
