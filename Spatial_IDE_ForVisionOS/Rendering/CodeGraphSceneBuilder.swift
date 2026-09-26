import RealityKit

/// `CodeGraph`와 `SpatialLayout`을 결합해 RealityKit 엔티티 트리를 만든다.
@MainActor
enum CodeGraphSceneBuilder {

    static let rootEntityName = "CodeGraphRoot"
    static let nodesGroupName = "Nodes"
    static let edgesGroupName = "Edges"
    static let backdropName = "InputBackdrop"

    /// 그래프의 모든 노드와 엣지를 자식으로 가진 루트 엔티티를 만든다.
    ///
    /// 루트 자체를 **모든 노드의 경계 상자 중심**에 두고, 자식은 그 기준 상대 좌표로 배치한다.
    /// 확대·회전은 루트의 로컬 원점을 피벗으로 일어나므로, 이렇게 해야 그래프가 자기 중심을 축으로
    /// 돈다. (`layout.origin`은 깊이 0 레이어의 위치라, 거기를 피벗으로 쓰면 앞쪽 main 노드를 축으로
    /// 뒤쪽 노드들이 크게 휘둘린다.)
    static func makeRootEntity(graph: CodeGraph, layout: SpatialLayout, palette: ScenePalette) -> Entity {
        let absolutePositions = layout.positions(for: graph)
        let center = boundingBoxCenter(of: Array(absolutePositions.values)) ?? layout.origin

        let root = Entity()
        root.name = rootEntityName
        root.position = center

        let positions = absolutePositions.mapValues { $0 - center }

        let nodesGroup = Entity()
        nodesGroup.name = nodesGroupName
        for node in graph.nodes {
            let entity = NodeEntityFactory.makeEntity(for: node)
            entity.position = positions[node.id] ?? .zero
            nodesGroup.addChild(entity)
        }
        root.addChild(nodesGroup)

        let edgesGroup = Entity()
        edgesGroup.name = edgesGroupName
        for edge in graph.edges {
            guard let start = positions[edge.from], let end = positions[edge.to] else { continue }
            edgesGroup.addChild(EdgeEntityFactory.makeEdge(edge: edge, from: start, to: end, palette: palette))
        }
        root.addChild(edgesGroup)

        root.addChild(makeInputBackdrop(behind: Array(positions.values)))

        // 범례(SwiftUI attachment)가 붙을 자리: 그래프 아래, 가장 앞쪽 노드 높이.
        let legendAnchor = Entity()
        legendAnchor.name = legendAnchorName
        let minY = positions.values.map(\.y).min() ?? 0
        let maxZ = positions.values.map(\.z).max() ?? 0
        legendAnchor.position = SIMD3<Float>(0, minY - 0.22, maxZ)
        root.addChild(legendAnchor)

        return root
    }

    /// 범례 어태치먼트 앵커 엔티티 이름.
    static let legendAnchorName = "LegendAnchor"

    /// 점 집합의 축 정렬 경계 상자 중심. 비어 있으면 nil.
    private static func boundingBoxCenter(of points: [SIMD3<Float>]) -> SIMD3<Float>? {
        guard let first = points.first else { return nil }
        var minPoint = first
        var maxPoint = first
        for point in points.dropFirst() {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }
        return (minPoint + maxPoint) / 2
    }

    /// 보이지 않는 넓은 입력 판. 그래프 뒤쪽에 놓여, 사용자가 카드가 아닌 빈 공간을 보고 핀치해도
    /// 그 입력이 `RealityView`에 전달되어 전역 제스처(확대·회전·이동)가 동작하게 한다.
    /// 메시·Hover 효과가 없으므로 시각적으로는 존재하지 않는다.
    private static func makeInputBackdrop(behind nodePositions: [SIMD3<Float>]) -> Entity {
        let minZ = nodePositions.map(\.z).min() ?? 0
        let backdrop = Entity()
        backdrop.name = backdropName
        backdrop.position = SIMD3<Float>(0, 0, minZ - 0.8)
        backdrop.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(10, 6, 0.02))]))
        backdrop.components.set(InputTargetComponent())
        return backdrop
    }

    /// 매 프레임 호출: 모든 엣지를 현재 노드 위치에 맞춰 다시 배치하고, 흐름 펄스를 전진시킨다.
    ///
    /// - `endpointAnchors`: 노드 ID → 노드 중심 기준 오프셋(미터). 토큰이 선택되어 있으면 해당 노드에
    ///   붙는 엣지 끝점이 노드 중심 대신 그 토큰 위치로 이동한다. 비어 있으면(전체 흐름 보기) 노드 중심.
    static func tick(root: Entity, deltaTime: Float, endpointAnchors: [String: SIMD3<Float>] = [:]) {
        guard let nodesGroup = root.findEntity(named: nodesGroupName),
              let edgesGroup = root.findEntity(named: edgesGroupName) else { return }

        var positions: [String: SIMD3<Float>] = [:]
        for node in nodesGroup.children {
            positions[node.name] = node.position
        }

        for edge in edgesGroup.children {
            guard let endpoints = edge.components[EdgeEndpointsComponent.self],
                  let start = positions[endpoints.fromNodeID],
                  let end = positions[endpoints.toNodeID] else { continue }
            EdgeEntityFactory.update(
                edge,
                from: start,
                to: end,
                startTarget: endpointAnchors[endpoints.fromNodeID] ?? .zero,
                endTarget: endpointAnchors[endpoints.toNodeID] ?? .zero,
                deltaTime: deltaTime
            )
            EdgeEntityFactory.advanceFlow(edge, deltaTime: deltaTime)
        }
    }

    /// 토큰 선택, 브레이크포인트, 현재 외관 팔레트에 따라 엣지 강조·색·일시정지를 갱신한다.
    /// - `highlighted`: nil이면 선택이 없는 상태.
    /// - `pausedNodeIDs`: 브레이크포인트가 걸린 노드. 여기서 나가는 엣지는 출발점에서 멈춰 점멸한다.
    /// - `containment`: 선택 토큰의 소유 체인. 이 집합의 노드로 들어오는 `owns` 엣지는 파란 곡선으로 그린다.
    static func applyEmphasis(
        root: Entity,
        highlighted: Set<String>?,
        containment: Set<String>?,
        pausedNodeIDs: Set<String>,
        palette: ScenePalette
    ) {
        guard let edgesGroup = root.findEntity(named: edgesGroupName) else { return }
        for edge in edgesGroup.children {
            guard let endpoints = edge.components[EdgeEndpointsComponent.self] else { continue }
            let emphasis: EdgeEmphasis
            if endpoints.kind == .owns, let containment, containment.contains(endpoints.toNodeID) {
                emphasis = .containment
            } else if let highlighted {
                let touches = highlighted.contains(endpoints.fromNodeID) || highlighted.contains(endpoints.toNodeID)
                emphasis = touches ? .highlighted : .dimmed
            } else {
                emphasis = .normal
            }
            // 소유 관계는 실행 흐름이 아니므로 브레이크포인트에 영향받지 않는다.
            let isPaused = endpoints.kind != .owns && pausedNodeIDs.contains(endpoints.fromNodeID)
            EdgeEntityFactory.setEmphasis(edge, emphasis, isPaused: isPaused, palette: palette)
        }
    }
}
