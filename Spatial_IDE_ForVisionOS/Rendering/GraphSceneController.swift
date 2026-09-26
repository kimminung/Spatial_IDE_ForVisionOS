import SwiftUI
import RealityKit

/// 노드 하나의 접힘 영역 하나를 가리키는 키. attachment ID와 힌지 피벗 엔티티 이름으로 쓴다.
struct FoldAttachmentKey: Hashable {
    let nodeID: String
    let regionID: Int

    var attachmentID: String { "\(nodeID)#fold\(regionID)" }
}

/// RealityKit 씬(노드·엣지·컨텍스트 메시·앵커)을 **현재 보이는 그래프 상태에 맞춰 증분 갱신**하는 컨트롤러.
///
/// 예전 `CodeGraphSceneBuilder`는 그래프 전체를 한 번 만들고 끝났다. 포커스 모델에서는 보이는 노드 집합이
/// 계속 바뀌므로, 매 `sync`마다 새로 보이는 노드·엣지만 만들고 사라진 것만 지운다. 나머지는 위치만 옮긴다.
///
/// 좌표: 레이아웃은 루트 노드가 (0,0,0)인 로컬 좌표를 주고, 첫 `sync`에서 그 경계 상자 중심을 `pivotOffset`으로
/// 잡아 모든 자식을 그만큼 옮긴다. 그래서 `root`의 원점(= 확대·회전 피벗)이 처음 보이는 그래프의 중심에 온다.
@MainActor
final class GraphSceneController {
    static let rootEntityName = "CodeGraphRoot"

    let root = Entity()
    let legendAnchor = Entity()
    let searchAnchor = Entity()

    private let nodesGroup = Entity()
    private let edgesGroup = Entity()
    private let contextMesh = ContextEdgeMesh()
    private let backdrop = Entity()

    private var pivotOffset: SIMD3<Float>?
    private var nodeEntities: [String: Entity] = [:]
    private var edgeEntities: [String: Entity] = [:]

    init() {
        root.name = Self.rootEntityName
        nodesGroup.name = "Nodes"
        edgesGroup.name = "Edges"
        legendAnchor.name = "LegendAnchor"
        searchAnchor.name = "SearchAnchor"
        backdrop.name = "InputBackdrop"

        // 보이지 않는 넓은 입력 판: 빈 공간을 보고 핀치해도 전역 제스처가 RealityView에 전달되게 한다.
        backdrop.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(10, 6, 0.02))]))
        backdrop.components.set(InputTargetComponent())

        root.addChild(nodesGroup)
        root.addChild(edgesGroup)
        root.addChild(contextMesh.entity)
        root.addChild(backdrop)
        root.addChild(legendAnchor)
        root.addChild(searchAnchor)
    }

    // MARK: - 동기화

    /// 보이는 노드·엣지를 현재 상태에 맞춘다. 보이는 집합, 레이아웃, 카드 크기, 접힘 정보가 바뀔 때 호출된다.
    func sync(
        visible: [CodeNode],
        isCard: (CodeNode) -> Bool,
        positions layoutPositions: [String: SIMD3<Float>],
        focusEdges: [CodeEdge],
        contextEdges: [ContextEdge],
        foldRegions: (CodeNode) -> [CodeFoldRegion],
        foldHinges: [String: SIMD3<Float>],
        foldSizes: [String: CGSize],
        palette: ScenePalette,
        attachments: RealityViewAttachments
    ) {
        guard !layoutPositions.isEmpty else { return }
        if pivotOffset == nil {
            pivotOffset = Self.boundingBoxCenter(of: Array(layoutPositions.values))
        }
        let offset = pivotOffset ?? .zero
        let positions = layoutPositions.mapValues { $0 - offset }

        syncNodes(visible: visible, isCard: isCard, positions: positions, foldRegions: foldRegions,
                  foldHinges: foldHinges, foldSizes: foldSizes, attachments: attachments)
        syncFocusEdges(focusEdges, positions: positions, palette: palette)
        syncContextEdges(contextEdges, positions: positions, palette: palette)
        placeAnchors(positions: positions)
    }

    private func syncNodes(
        visible: [CodeNode],
        isCard: (CodeNode) -> Bool,
        positions: [String: SIMD3<Float>],
        foldRegions: (CodeNode) -> [CodeFoldRegion],
        foldHinges: [String: SIMD3<Float>],
        foldSizes: [String: CGSize],
        attachments: RealityViewAttachments
    ) {
        let visibleIDs = Set(visible.map(\.id))
        for (id, entity) in nodeEntities where !visibleIDs.contains(id) {
            entity.removeFromParent()
            nodeEntities.removeValue(forKey: id)
        }

        for node in visible {
            guard let target = positions[node.id] else { continue }
            let entity: Entity
            if let existing = nodeEntities[node.id] {
                entity = existing
                if simd_distance(existing.position, target) > 0.001 {
                    var transform = existing.transform
                    transform.translation = target
                    existing.move(to: transform, relativeTo: nodesGroup, duration: 0.25, timingFunction: .easeInOut)
                }
            } else {
                entity = NodeEntityFactory.makeEntity(for: node)
                entity.position = target
                nodesGroup.addChild(entity)
                nodeEntities[node.id] = entity
            }

            if let card = attachments.entity(for: node.id), card.parent !== entity {
                entity.addChild(card)
            }

            syncFolds(of: node, on: entity, isCard: isCard(node), regions: foldRegions,
                      hinges: foldHinges, sizes: foldSizes, attachments: attachments)
        }
    }

    /// 카드 노드의 접힘 블록: 힌지 피벗(Y축 회전) 아래에 attachment를 붙이고 위치를 맞춘다. 칩이 되면 걷어낸다.
    private func syncFolds(
        of node: CodeNode,
        on entity: Entity,
        isCard: Bool,
        regions: (CodeNode) -> [CodeFoldRegion],
        hinges: [String: SIMD3<Float>],
        sizes: [String: CGSize],
        attachments: RealityViewAttachments
    ) {
        guard isCard else {
            for child in entity.children where child.name.contains("#fold") { child.removeFromParent() }
            return
        }
        for region in regions(node) {
            let key = FoldAttachmentKey(nodeID: node.id, regionID: region.id)
            guard let block = attachments.entity(for: key.attachmentID) else { continue }
            let pivot: Entity
            if let existing = entity.findEntity(named: key.attachmentID) {
                pivot = existing
            } else {
                pivot = Entity()
                pivot.name = key.attachmentID
                pivot.orientation = simd_quatf(angle: SceneStyle.foldAngle, axis: SIMD3<Float>(0, 1, 0))
                entity.addChild(pivot)
            }
            if block.parent !== pivot { pivot.addChild(block) }
            if let hinge = hinges[key.attachmentID] { pivot.position = hinge }
            if let size = sizes[key.attachmentID] {
                // attachment는 중심 기준이므로 (+w/2, -h/2)만큼 옮겨 왼쪽 위 모서리를 힌지에 맞춘다.
                block.position = SIMD3<Float>(
                    Float(size.width / 2) / SceneStyle.pointsPerMeter,
                    -Float(size.height / 2) / SceneStyle.pointsPerMeter,
                    0
                )
            }
        }
    }

    private func syncFocusEdges(_ edges: [CodeEdge], positions: [String: SIMD3<Float>], palette: ScenePalette) {
        let wanted = Dictionary(edges.map { ("\($0.from)->\($0.to)", $0) }, uniquingKeysWith: { first, _ in first })
        for (key, entity) in edgeEntities where wanted[key] == nil {
            entity.removeFromParent()
            edgeEntities.removeValue(forKey: key)
        }
        for (key, edge) in wanted where edgeEntities[key] == nil {
            guard let start = positions[edge.from], let end = positions[edge.to] else { continue }
            let entity = EdgeEntityFactory.makeEdge(edge: edge, from: start, to: end, palette: palette)
            edgesGroup.addChild(entity)
            edgeEntities[key] = entity
        }
    }

    private func syncContextEdges(_ edges: [ContextEdge], positions: [String: SIMD3<Float>], palette: ScenePalette) {
        let segments = edges.compactMap { edge -> ContextEdgeMesh.Segment? in
            guard let start = positions[edge.from], let end = positions[edge.to] else { return nil }
            return ContextEdgeMesh.Segment(start: start, end: end, weight: edge.weight)
        }
        contextMesh.update(segments, palette: palette)
    }

    private func placeAnchors(positions: [String: SIMD3<Float>]) {
        let values = Array(positions.values)
        let minY = values.map(\.y).min() ?? 0
        let maxY = values.map(\.y).max() ?? 0
        let minZ = values.map(\.z).min() ?? 0
        let maxZ = values.map(\.z).max() ?? 0
        legendAnchor.position = SIMD3<Float>(0, minY - 0.30, maxZ)
        searchAnchor.position = SIMD3<Float>(0, maxY + 0.22, maxZ)
        backdrop.position = SIMD3<Float>(0, 0, minZ - 0.8)
    }

    // MARK: - 매 프레임

    /// 모든 포커스 엣지를 현재 노드 위치(또는 선택된 토큰 위치)에 맞추고, 흐름 펄스를 전진시킨다.
    func tick(deltaTime: Float, endpointAnchors: [String: SIMD3<Float>]) {
        for entity in edgeEntities.values {
            guard let endpoints = entity.components[EdgeEndpointsComponent.self],
                  let start = nodeEntities[endpoints.fromNodeID]?.position,
                  let end = nodeEntities[endpoints.toNodeID]?.position else { continue }
            EdgeEntityFactory.update(
                entity,
                from: start,
                to: end,
                startTarget: endpointAnchors[endpoints.fromNodeID] ?? .zero,
                endTarget: endpointAnchors[endpoints.toNodeID] ?? .zero,
                deltaTime: deltaTime
            )
            EdgeEntityFactory.advanceFlow(entity, deltaTime: deltaTime)
        }
    }

    // MARK: - 강조

    /// 토큰 선택, 브레이크포인트, 현재 외관 팔레트에 따라 엣지 강조·색·일시정지를 갱신한다.
    func applyEmphasis(highlighted: Set<String>?, containment: Set<String>?, pausedNodeIDs: Set<String>, palette: ScenePalette) {
        for entity in edgeEntities.values {
            guard let endpoints = entity.components[EdgeEndpointsComponent.self] else { continue }
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
            EdgeEntityFactory.setEmphasis(entity, emphasis, isPaused: isPaused, palette: palette)
        }
        contextMesh.applyPalette(palette)
    }

    // MARK: - 기하

    private static func boundingBoxCenter(of points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard let first = points.first else { return .zero }
        var minPoint = first
        var maxPoint = first
        for point in points.dropFirst() {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }
        return (minPoint + maxPoint) / 2
    }
}
