import Foundation
import simd

/// 펼친 블록을 묶는 테두리. 컨테이너 카드의 **노드 로컬** 좌표(미터)로 표현한다.
struct GroupFrame: Equatable {
    /// 컨테이너 카드 중심 기준 테두리 중심 오프셋.
    var center: SIMD2<Float>
    /// 테두리 전체 폭·높이.
    var size: SIMD2<Float>
}

/// 노드 하나의 배치 결과: 루트 로컬 위치, Y축 회전(사용자를 향하도록), 그리고 펼친 컨테이너라면 블록 테두리.
struct NodePlacement: Equatable {
    var position: SIMD3<Float>
    /// Y축 회전(라디안). 호 위의 각도만큼 반대로 돌려 카드 정면이 사용자를 향한다.
    var yaw: Float
    /// 펼친 컨테이너(타입·모듈)일 때, 자기 카드와 아래로 쌓인 멤버들을 묶는 테두리.
    var groupFrame: GroupFrame? = nil
}

/// 계층 레이아웃. **보이는 노드만** 배치한다.
///
/// 공간은 사용자를 중심으로 한 **호(arc)** 위에 펼쳐진다. 가로로 죽 늘어놓은 "언롤(unrolled)" 좌표 (u, y)를 계산한 뒤
/// u를 각도로, 깊이를 반지름으로 바꿔 3D 위치를 만든다. 카드는 각자 사용자를 향해 회전한다.
///
/// - **지도 층**: 루트(모듈) 카드가 눈높이 정면에, 그 자식(타입 칩)들이 뒤쪽 호 위에 눈높이를 중심으로 위아래로 줄을 채운다.
///   칩의 반지름은 **의존 층**(`depthLevels`: 진입점 0 → 피호출 쪽으로 커짐)에 따라 `levelDepth`씩 커져 호출 관계가 깊이로 드러난다.
/// - **펼침(제자리, 한 열, 길이 제한 없음)**: 타입 칩을 펼치면 그 **칩 자리에서** 타입 카드가 나타나고, 열린 본문 → 시그니처 칩 순으로
///   아래로 한 열로 쌓인다. 길이를 제한하거나 옆으로 열을 나누지 않는다(사용자 결정). 블록 아래가 바닥에 닿으면 블록을
///   천장(`ceiling`)까지만 밀어 올리고, 그래도 넘치면 바닥 아래로 내려간다. 대신 블록마다 **옅은 형광 테두리**(`GroupFrame`)로 묶어
///   많이 펼쳐도 어디까지가 한 타입인지 구분된다. 펼친 타입이 여럿이면 블록끼리 `blockMargin` 이상 떨어지도록 호를 따라 밀어낸다.
///
/// 결과는 루트가 (0,0,0) 근처에 오는 **레이아웃 로컬 좌표**다. 씬 컨트롤러가 세계 위치·피벗을 정한다. 모든 단위는 미터(m).
struct SpatialLayout: Sendable {
    /// 그래프 루트가 놓이는 세계 위치. 기본값은 눈높이 근처, 사용자 정면 1.6m. 호의 중심은 사용자(원점 뒤 1.6m)다.
    var origin: SIMD3<Float> = [0, 1.35, -1.6]

    /// 지도 층 줄의 최대 폭(언롤 좌표). 좁게 잡아 줄 수를 늘리면 그리드가 세로로도 자라 납작해 보이지 않는다.
    var rowWidth: Float = 2.8
    /// 사용자에서 의존 층 0 칩까지의 반지름.
    var arcRadius: Float = 2.2
    /// 의존 층이 하나 깊어질 때 늘어나는 반지름.
    var levelDepth: Float = 0.35
    /// 줄이 하나 내려갈 때 늘어나는 반지름.
    var rowDepth: Float = 0.06
    /// 루트(모듈) 카드가 칩보다 앞에 있는 정도(반지름 감소).
    var rootLift: Float = 0.45
    /// 펼친 블록이 칩보다 앞으로 나오는 정도(반지름 감소).
    var expandedLift: Float = 0.12

    /// 블록 아래가 닿을 수 있는 바닥 여유(세계 y). 닿으면 블록을 위로 밀어 올린다.
    var floorMargin: Float = 0.15
    /// 블록 윗부분(타입 카드)이 올라갈 수 있는 상한(세계 y). 머리 위로 카드를 보내지 않기 위한 값. 이보다 길면 바닥 아래로 내려간다.
    var ceiling: Float = 1.9
    /// 서로 다른 블록 사이에 확보하는 가로 여백.
    var blockMargin: Float = 0.30
    /// 블록 테두리가 카드들 바깥으로 남기는 여백.
    var groupPadding: Float = 0.05

    /// 코드 카드 사이 간격(가로/세로). 엣지·화살촉이 글자와 겹치지 않고 지나갈 여백.
    var cardGap = SIMD2<Float>(0.32, 0.20)
    /// 지도 층 칩 사이 간격(가로/세로).
    var chipGap = SIMD2<Float>(0.30, 0.14)
    /// 블록 안 시그니처 칩 사이 간격(세로 목록이라 촘촘해도 된다).
    var listChipGap = SIMD2<Float>(0.16, 0.045)

    /// 크기가 아직 보고되지 않은 카드/칩의 추정 크기.
    var defaultCardSize = SIMD2<Float>(0.34, 0.14)
    var defaultChipSize = SIMD2<Float>(0.22, 0.05)

    func placements(
        visible: [CodeNode],
        index: GraphIndex,
        expanded: Set<String>,
        sizes: [String: SIMD2<Float>],
        isCard: (CodeNode) -> Bool,
        depthLevels: [String: Int]
    ) -> [String: NodePlacement] {
        let visibleIDs = Set(visible.map(\.id))
        var result: [String: NodePlacement] = [:]
        let userDistance = -origin.z   // 루트에서 사용자까지(+Z)

        func size(_ node: CodeNode) -> SIMD2<Float> {
            sizes[node.id] ?? (isCard(node) ? defaultCardSize : defaultChipSize)
        }
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

        /// 언롤 좌표 (u, y)와 반지름 증분을 호 위의 3D 위치로 바꿔 기록한다.
        func place(_ id: String, u: Float, y: Float, extraRadius: Float) {
            let radius = arcRadius + extraRadius
            let theta = u / arcRadius
            let position = SIMD3<Float>(radius * sin(theta), y, userDistance - radius * cos(theta))
            result[id] = NodePlacement(position: position, yaw: -theta)
        }

        // MARK: 펼친 블록

        struct Block {
            let container: CodeNode
            let items: [CodeNode]
            let width: Float
            var u: Float
            let top: Float
            let extraRadius: Float
        }

        /// 컨테이너 카드 + 멤버들. **열린 본문(카드)을 먼저**, 시그니처 칩을 그 뒤에 둔다. 방금 연 코드가 타입 카드 바로 아래
        /// 눈높이 근처에 오고, 아직 열지 않은 목록은 아래로 내려간다. 펼친 중첩 타입은 그 자리에 자기 카드와 멤버를 이어 붙인다.
        func flatten(_ container: CodeNode) -> [CodeNode] {
            let children = visibleChildren(container)
            let opened = children.filter { isCard($0) }
            let closed = children.filter { !isCard($0) }
            return [container] + opened.flatMap { child in isPulledForward(child) ? flatten(child) : [child] } + closed
        }

        /// 블록은 한 열이고 길이 제한이 없다. 바닥에 닿으면 천장까지만 밀어 올린다.
        func makeBlock(_ container: CodeNode, u: Float, top: Float, extraRadius: Float) -> Block {
            let items = flatten(container)
            let m = metrics(items, size, listGap)
            var blockTop = top
            let bottomWorld = origin.y + blockTop - m.spanY
            if bottomWorld < floorMargin {
                blockTop = min(blockTop + (floorMargin - bottomWorld), ceiling - origin.y)
            }
            return Block(container: container, items: items, width: m.maxX, u: u, top: blockTop, extraRadius: extraRadius)
        }

        /// 열을 아래로 쌓고, 블록의 컨테이너(및 펼친 중첩 타입)마다 자기 항목들을 감싸는 테두리를 기록한다.
        func placeBlock(_ block: Block) {
            var y = block.top
            var tops: [String: Float] = [:]      // 항목 윗변
            var bottoms: [String: Float] = [:]   // 항목 아랫변
            for child in block.items {
                let s = size(child)
                place(child.id, u: block.u, y: y - s.y / 2, extraRadius: block.extraRadius)
                tops[child.id] = y
                bottoms[child.id] = y - s.y
                y -= s.y + listGap(child).y
            }

            // 테두리: 컨테이너 카드 윗변부터 그 마지막 항목 아랫변까지. 중첩 타입은 자기 범위만.
            func frame(for container: CodeNode) {
                let members = flatten(container)
                guard let top = tops[container.id], let last = members.last, let bottom = bottoms[last.id] else { return }
                let containerSize = size(container)
                let width = members.map { size($0).x }.max() ?? containerSize.x
                let height = top - bottom
                let containerCenterY = top - containerSize.y / 2
                let frameCenterY = (top + bottom) / 2
                result[container.id]?.groupFrame = GroupFrame(
                    center: SIMD2<Float>(0, frameCenterY - containerCenterY),
                    size: SIMD2<Float>(width + groupPadding * 2, height + groupPadding * 2)
                )
                for child in visibleChildren(container) where isPulledForward(child) { frame(for: child) }
            }
            frame(for: block.container)
        }

        /// 블록들이 호를 따라 겹치지 않도록 왼쪽부터 차례로 밀어내고, 밀린 만큼 전체를 되돌려 무게중심을 유지한다.
        func separate(_ blocks: [Block]) -> [Block] {
            var sorted = blocks.sorted { $0.u < $1.u }
            for i in 1..<max(sorted.count, 1) {
                let previous = sorted[i - 1]
                let minU = previous.u + previous.width / 2 + groupPadding * 2 + blockMargin + sorted[i].width / 2
                if sorted[i].u < minU { sorted[i].u = minU }
            }
            if !blocks.isEmpty {
                let shift = (blocks.map(\.u).reduce(0, +) - sorted.map(\.u).reduce(0, +)) / Float(blocks.count)
                for i in sorted.indices { sorted[i].u += shift }
            }
            return sorted
        }

        // MARK: 지도 층

        /// 루트 카드는 눈높이(y 0) 정면에, 자식 칩 그리드는 그 뒤에서 **눈높이를 중심으로 위아래로** 펼친다.
        func placeMap(root: CodeNode, u rootU: Float, center: Float) {
            place(root.id, u: rootU, y: center, extraRadius: -rootLift)

            // 펼친 컨테이너는 그리드에 칩 크기 자리만 차지한다(카드는 그 자리에서 블록으로 열린다).
            func footprint(_ child: CodeNode) -> SIMD2<Float> { isPulledForward(child) ? defaultChipSize : size(child) }
            func mapGap(_ child: CodeNode) -> SIMD2<Float> { chipGap }

            let rows = pack(visibleChildren(root), along: \.x, limit: rowWidth, footprint, mapGap)
            let gridHeight = rows.reduce(Float(0)) { $0 + metrics($1, footprint, mapGap).maxY } + chipGap.y * Float(max(rows.count - 1, 0))
            var y = center + gridHeight / 2 + chipGap.y
            var blocks: [Block] = []
            for (rowIndex, line) in rows.enumerated() {
                let m = metrics(line, footprint, mapGap)
                y -= m.gapY
                var u = rootU - m.spanX / 2
                for (position, child) in line.enumerated() {
                    let s = footprint(child)
                    let level = Float(depthLevels[child.id] ?? 0)
                    let extra = level * levelDepth + Float(rowIndex) * rowDepth
                    if isPulledForward(child) {
                        blocks.append(makeBlock(child, u: u + s.x / 2, top: y, extraRadius: extra - expandedLift))
                    } else {
                        place(child.id, u: u + s.x / 2, y: y - s.y / 2, extraRadius: extra)
                    }
                    u += s.x
                    if position + 1 < line.count { u += chipGap.x }
                }
                y -= m.maxY
            }

            for block in separate(blocks) {
                placeBlock(block)
            }
        }

        // 루트들은 한 줄로 나란히.
        let roots = visible.filter(isRoot)
        let rootsMetrics = metrics(roots, size, { _ in cardGap })
        var u = -rootsMetrics.spanX / 2
        for (position, root) in roots.enumerated() {
            let s = size(root)
            placeMap(root: root, u: u + s.x / 2, center: 0)
            u += s.x
            if position + 1 < roots.count { u += cardGap.x }
        }
        return result
    }

    // MARK: - 묶음 치수

    private struct GroupMetrics {
        var spanX: Float = 0
        var spanY: Float = 0
        var maxX: Float = 0
        var maxY: Float = 0
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
