import SwiftUI
import RealityKit

/// 노드 하나의 접힘 영역 하나를 가리키는 키. attachment ID와 힌지 피벗 엔티티 이름으로 쓴다.
struct FoldAttachmentKey: Hashable {
    let nodeID: String
    let regionID: Int

    var attachmentID: String { "\(nodeID)#fold\(regionID)" }
}

/// 블록 테두리 엔티티에 붙여 현재 크기를 기억한다(크기가 바뀔 때만 다시 만들기 위해).
struct GroupFrameComponent: Component {
    let center: SIMD2<Float>
    let size: SIMD2<Float>
}

/// RealityKit 씬(노드·엣지·컨텍스트 메시·앵커)을 **현재 보이는 그래프 상태에 맞춰 증분 갱신**하는 컨트롤러.
///
/// 보이는 노드 집합이 바뀔 때마다 새로 보이는 노드·엣지만 만들고 사라진 것만 지운다. 나머지는 위치·회전만 옮긴다.
///
/// 좌표: 레이아웃은 루트 근처가 원점인 로컬 좌표(`NodePlacement`)를 주고, 첫 `sync`에서 그 경계 상자 중심을 `pivotOffset`으로
/// 잡아 모든 자식을 그만큼 옮긴다. 그래서 `root`의 원점(= 확대·회전 피벗)이 처음 보이는 그래프의 중심에 온다.
/// 카드는 호(arc) 위에서 각자 사용자를 향해 회전하므로, 카드 사각형과 관련된 판정(테두리 끝점·주시·회피)은 모두
/// **노드 로컬 좌표**(카드 평면 = z 0, 정면 = +Z)에서 한다.
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
    /// 노드 ID → 카드/칩의 절반 크기(미터). 엣지가 카드 중심이 아니라 **테두리**에서 시작·끝나도록 하는 데 쓴다.
    private var halfSizes: [String: SIMD2<Float>] = [:]
    private let defaultHalfSize = SIMD2<Float>(0.12, 0.05)

    /// 엣지 끝점이 카드 테두리에서 더 떨어지는 여백(미터). 화살촉이 글자에 닿지 않게 한다.
    private let edgeMargin: Float = 0.018

    /// 사용자가 머리를 향하고 있는(= 바라보는 것으로 간주하는) 노드. 이 카드 위를 지나는 엣지는 곡선으로 비켜 간다.
    /// visionOS는 시선 좌표를 주지 않으므로 ARKit 기기 자세의 정면 광선으로 근사한다.
    private(set) var attendedNodeID: String?
    /// 광선이 카드 사각형을 벗어나도 이 여백 안이면 주시를 유지한다(경계에서 깜빡임 방지).
    private let attentionMargin: Float = 0.04
    private let attentionStickyMargin: Float = 0.14
    /// 회피 곡선이 카드 테두리에서 더 확보하는 간격.
    private let avoidanceClearance: Float = 0.05

    /// 컨텍스트 엣지(배치 라인 메시)도 주시 카드를 비켜 가도록, 주시가 바뀌면 메시를 다시 채운다.
    private var contextEdges: [ContextEdge] = []
    private var contextAttended: String?
    /// 주시 전환 후 회피 곡선이 펴지는 진행도(0→1). 1이 되면 메시 갱신을 멈춘다.
    private var contextBend: Float = 1
    private var palette: ScenePalette?

    init() {
        root.name = Self.rootEntityName
        nodesGroup.name = "Nodes"
        edgesGroup.name = "Edges"
        legendAnchor.name = "LegendAnchor"
        searchAnchor.name = "SearchAnchor"
        backdrop.name = "InputBackdrop"

        // 보이지 않는 넓은 입력 판: 빈 공간을 보고 핀치해도 전역 제스처가 RealityView에 전달되게 한다.
        backdrop.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(12, 6, 0.02))]))
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
        placements layoutPlacements: [String: NodePlacement],
        focusEdges: [CodeEdge],
        contextEdges: [ContextEdge],
        foldRegions: (CodeNode) -> [CodeFoldRegion],
        foldHinges: [String: SIMD3<Float>],
        foldSizes: [String: CGSize],
        cardSizes: [String: SIMD2<Float>],
        palette: ScenePalette,
        attachments: RealityViewAttachments
    ) {
        guard !layoutPlacements.isEmpty else { return }
        if pivotOffset == nil {
            pivotOffset = Self.boundingBoxCenter(of: layoutPlacements.values.map(\.position))
        }
        let offset = pivotOffset ?? .zero
        let placements = layoutPlacements.mapValues { NodePlacement(position: $0.position - offset, yaw: $0.yaw) }
        halfSizes = cardSizes.mapValues { $0 / 2 }
        self.palette = palette

        syncNodes(visible: visible, isCard: isCard, placements: placements, foldRegions: foldRegions,
                  foldHinges: foldHinges, foldSizes: foldSizes, palette: palette, attachments: attachments)
        syncFocusEdges(focusEdges, placements: placements, palette: palette)
        self.contextEdges = contextEdges
        rebuildContextMesh()
        placeAnchors(positions: placements.values.map(\.position))
    }

    private func syncNodes(
        visible: [CodeNode],
        isCard: (CodeNode) -> Bool,
        placements: [String: NodePlacement],
        foldRegions: (CodeNode) -> [CodeFoldRegion],
        foldHinges: [String: SIMD3<Float>],
        foldSizes: [String: CGSize],
        palette: ScenePalette,
        attachments: RealityViewAttachments
    ) {
        let visibleIDs = Set(visible.map(\.id))
        for (id, entity) in nodeEntities where !visibleIDs.contains(id) {
            entity.removeFromParent()
            nodeEntities.removeValue(forKey: id)
        }
        if let attended = attendedNodeID, !visibleIDs.contains(attended) { attendedNodeID = nil }

        for node in visible {
            guard let placement = placements[node.id] else { continue }
            let rotation = simd_quatf(angle: placement.yaw, axis: SIMD3<Float>(0, 1, 0))
            let entity: Entity
            if let existing = nodeEntities[node.id] {
                entity = existing
                let moved = simd_distance(existing.position, placement.position) > 0.001
                let turned = abs(existing.orientation.angle - rotation.angle) > 0.005
                if moved || turned {
                    let transform = Transform(scale: .one, rotation: rotation, translation: placement.position)
                    existing.move(to: transform, relativeTo: nodesGroup, duration: 0.25, timingFunction: .easeInOut)
                }
            } else {
                entity = NodeEntityFactory.makeEntity(for: node)
                entity.position = placement.position
                entity.orientation = rotation
                nodesGroup.addChild(entity)
                nodeEntities[node.id] = entity
            }

            if let card = attachments.entity(for: node.id), card.parent !== entity {
                entity.addChild(card)
            }

            syncFolds(of: node, on: entity, isCard: isCard(node), regions: foldRegions,
                      hinges: foldHinges, sizes: foldSizes, attachments: attachments)
            syncGroupFrame(on: entity, frame: placement.groupFrame, nodeID: node.id, palette: palette)
        }
    }

    // MARK: - 블록 테두리

    private static let groupFrameName = "GroupFrame"
    private static let groupFrameThickness: Float = 0.004

    /// 펼친 컨테이너의 블록(자기 카드 + 아래로 쌓인 멤버들)을 감싸는 옅은 형광 테두리. 카드 평면 살짝 뒤에 네 변의 얇은 막대로 그린다.
    /// 컨테이너 엔티티의 자식이라 카드가 호 위에서 회전해도 함께 돈다. 크기가 바뀌면 다시 만든다.
    private func syncGroupFrame(on entity: Entity, frame: GroupFrame?, nodeID: String, palette: ScenePalette) {
        let existing = entity.children.first { $0.name == Self.groupFrameName }
        guard let frame else {
            existing?.removeFromParent()
            return
        }
        if let existing, let current = existing.components[GroupFrameComponent.self],
           simd_distance(current.size, frame.size) < 0.002, simd_distance(current.center, frame.center) < 0.002 {
            return
        }
        existing?.removeFromParent()

        let group = Entity()
        group.name = Self.groupFrameName
        group.position = SIMD3<Float>(frame.center.x, frame.center.y, -0.006)
        group.components.set(GroupFrameComponent(center: frame.center, size: frame.size))

        var material = UnlitMaterial(color: palette.groupFrame(seed: Self.stableHash(nodeID)).realityKitColor)
        material.blending = .transparent(opacity: .init(floatLiteral: palette.groupFrameOpacity))

        let t = Self.groupFrameThickness
        let w = frame.size.x
        let h = frame.size.y
        let bars: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3<Float>(0, h / 2, 0), SIMD3<Float>(w, t, t)),      // 위
            (SIMD3<Float>(0, -h / 2, 0), SIMD3<Float>(w, t, t)),     // 아래
            (SIMD3<Float>(-w / 2, 0, 0), SIMD3<Float>(t, h, t)),     // 왼쪽
            (SIMD3<Float>(w / 2, 0, 0), SIMD3<Float>(t, h, t)),      // 오른쪽
        ]
        for (position, size) in bars {
            let bar = ModelEntity(mesh: .generateBox(size: size, cornerRadius: t / 2), materials: [material])
            bar.position = position
            group.addChild(bar)
        }
        entity.addChild(group)
    }

    /// 실행마다 바뀌지 않는 문자열 해시(색 선택용).
    private static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
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

    private func syncFocusEdges(_ edges: [CodeEdge], placements: [String: NodePlacement], palette: ScenePalette) {
        let wanted = Dictionary(edges.map { ("\($0.from)->\($0.to)", $0) }, uniquingKeysWith: { first, _ in first })
        for (key, entity) in edgeEntities where wanted[key] == nil {
            entity.removeFromParent()
            edgeEntities.removeValue(forKey: key)
        }
        for (key, edge) in wanted where edgeEntities[key] == nil {
            guard let start = placements[edge.from]?.position, let end = placements[edge.to]?.position else { continue }
            let entity = EdgeEntityFactory.makeEdge(edge: edge, from: start, to: end, palette: palette)
            edgesGroup.addChild(entity)
            edgeEntities[key] = entity
        }
    }

    /// 컨텍스트 엣지를 현재 노드 위치·주시 회피 상태로 다시 채운다. 회피 중인 선은 베지어를 따라 8개 선분으로 근사한다.
    private func rebuildContextMesh() {
        guard let palette else { return }
        var segments: [ContextEdgeMesh.Segment] = []
        segments.reserveCapacity(contextEdges.count)
        for edge in contextEdges {
            guard let fromEntity = nodeEntities[edge.from], let toEntity = nodeEntities[edge.to] else { continue }
            let start = fromEntity.position + boundaryOffset(of: edge.from, entity: fromEntity, toward: toEntity.position, kind: .calls, isStart: true)
            let end = toEntity.position + boundaryOffset(of: edge.to, entity: toEntity, toward: fromEntity.position, kind: .calls, isStart: false)
            let deflection = avoidanceDeflection(from: edge.from, to: edge.to, start: start, end: end) * contextBend
            if simd_length(deflection) > 0.004 {
                let control = (start + end) / 2 + deflection
                var previous = start
                for step in 1...8 {
                    let t = Float(step) / 8
                    let u = 1 - t
                    let point = start * (u * u) + control * (2 * u * t) + end * (t * t)
                    segments.append(ContextEdgeMesh.Segment(start: previous, end: point, weight: edge.weight))
                    previous = point
                }
            } else {
                segments.append(ContextEdgeMesh.Segment(start: start, end: end, weight: edge.weight))
            }
        }
        contextMesh.update(segments, palette: palette)
    }

    private func placeAnchors(positions: [SIMD3<Float>]) {
        let minY = positions.map(\.y).min() ?? 0
        let maxY = positions.map(\.y).max() ?? 0
        let minZ = positions.map(\.z).min() ?? 0
        let maxZ = positions.map(\.z).max() ?? 0
        legendAnchor.position = SIMD3<Float>(0, minY - 0.30, maxZ)
        searchAnchor.position = SIMD3<Float>(0, maxY + 0.22, maxZ)
        backdrop.position = SIMD3<Float>(0, 0, minZ - 0.8)
    }

    // MARK: - 매 프레임

    /// 모든 포커스 엣지를 현재 노드 위치에 맞추고, 흐름 펄스를 전진시킨다.
    ///
    /// - 끝점 오프셋의 우선순위: 선택된 토큰 위치(`endpointAnchors`) > 카드 테두리. 토큰이 선택되지 않은 노드에서는
    ///   엣지가 카드 중심(글자 위)이 아니라 상대 노드 쪽 테두리에서 출발·도착하므로 텍스트를 가로지르지 않는다.
    /// - `headTransform`(ARKit 기기 자세, 월드 좌표)이 있으면 정면 광선이 지나는 카드를 주시 노드로 잡고,
    ///   그 카드 위를 지나는 다른 엣지(리치 엣지·컨텍스트 라인 모두)에 회피 곡선을 준다. 시선이 떠나면 직선으로 돌아간다.
    func tick(deltaTime: Float, endpointAnchors: [String: SIMD3<Float>], headTransform: simd_float4x4? = nil) {
        updateAttention(headTransform: headTransform)

        for entity in edgeEntities.values {
            guard let endpoints = entity.components[EdgeEndpointsComponent.self],
                  let fromEntity = nodeEntities[endpoints.fromNodeID],
                  let toEntity = nodeEntities[endpoints.toNodeID] else { continue }
            let start = fromEntity.position
            let end = toEntity.position
            let startTarget = endpointAnchors[endpoints.fromNodeID]
                ?? boundaryOffset(of: endpoints.fromNodeID, entity: fromEntity, toward: end, kind: endpoints.kind, isStart: true)
            let endTarget = endpointAnchors[endpoints.toNodeID]
                ?? boundaryOffset(of: endpoints.toNodeID, entity: toEntity, toward: start, kind: endpoints.kind, isStart: false)
            let deflection = avoidanceDeflection(from: endpoints.fromNodeID, to: endpoints.toNodeID,
                                                 start: start + startTarget, end: end + endTarget)
            EdgeEntityFactory.update(
                entity,
                from: start,
                to: end,
                startTarget: startTarget,
                endTarget: endTarget,
                deflectionTarget: deflection,
                deltaTime: deltaTime
            )
            EdgeEntityFactory.advanceFlow(entity, deltaTime: deltaTime)
        }

        // 컨텍스트 라인: 주시가 바뀐 뒤 약 0.2초 동안 곡선을 펴면서 메시를 다시 채우고, 끝나면 멈춘다.
        if attendedNodeID != contextAttended {
            contextAttended = attendedNodeID
            contextBend = 0
        }
        if contextBend < 1 {
            contextBend = min(1, contextBend + deltaTime * 5)
            rebuildContextMesh()
        }
    }

    // MARK: - 카드 테두리 끝점

    /// 노드 중심에서 카드 테두리(+여백)까지의 오프셋(루트 로컬). 상대 노드 방향으로 사각형을 빠져나가는 점을 잡는다.
    ///
    /// - 소유(`owns`) 엣지는 트리 도식처럼 부모 **아래 변** 가운데에서 나와 자식 **위 변** 가운데로 들어간다.
    /// - 그 외는 상대 방향(카드 평면)으로 사각형 경계와의 교점. 상대가 거의 정면/뒤에 있으면 위·아래 변을 쓴다.
    private func boundaryOffset(of nodeID: String, entity: Entity, toward other: SIMD3<Float>, kind: CodeEdgeKind, isStart: Bool) -> SIMD3<Float> {
        let half = halfSizes[nodeID] ?? defaultHalfSize
        let localOther = entity.convert(position: other, from: root)

        var local: SIMD3<Float>
        if kind == .owns {
            local = SIMD3<Float>(0, isStart ? -(half.y + edgeMargin) : (half.y + edgeMargin), 0)
        } else {
            let planar = SIMD2<Float>(localOther.x, localOther.y)
            let planarLength = simd_length(planar)
            if planarLength < 0.03 {
                let sign: Float = localOther.y >= 0 ? 1 : -1
                local = SIMD3<Float>(0, sign * (half.y + edgeMargin), 0)
            } else {
                let direction = planar / planarLength
                var t = Float.greatestFiniteMagnitude
                if abs(direction.x) > .ulpOfOne { t = min(t, half.x / abs(direction.x)) }
                if abs(direction.y) > .ulpOfOne { t = min(t, half.y / abs(direction.y)) }
                // 두 노드가 가까우면 양쪽 오프셋이 서로를 지나치지 않도록 거리의 40%로 묶는다.
                t = min(t + edgeMargin, simd_length(localOther) * 0.4)
                local = SIMD3<Float>(direction.x * t, direction.y * t, 0)
            }
        }
        return entity.convert(direction: local, to: root)
    }

    // MARK: - 주시(머리 방향) 판정과 회피

    /// 머리 정면 광선이 가장 먼저 지나는 카드를 주시 노드로 잡는다. 현재 주시 노드는 더 큰 여백으로 유지한다.
    private func updateAttention(headTransform: simd_float4x4?) {
        guard let headTransform else {
            attendedNodeID = nil
            return
        }
        let worldOrigin = SIMD3<Float>(headTransform.columns.3.x, headTransform.columns.3.y, headTransform.columns.3.z)
        let worldForward = -SIMD3<Float>(headTransform.columns.2.x, headTransform.columns.2.y, headTransform.columns.2.z)
        let origin = root.convert(position: worldOrigin, from: nil)
        let forward = root.convert(direction: worldForward, from: nil)
        guard simd_length(forward) > .ulpOfOne else { return }

        var best: (id: String, distance: Float)?
        for (id, entity) in nodeEntities {
            // 노드 로컬: 카드 평면은 z = 0, 정면은 +Z.
            let localOrigin = entity.convert(position: origin, from: root)
            let localForward = entity.convert(direction: forward, from: root)
            guard abs(localForward.z) > 1e-4 else { continue }
            let distance = -localOrigin.z / localForward.z
            guard distance > 0.05 else { continue }
            let hit = localOrigin + localForward * distance
            let half = halfSizes[id] ?? defaultHalfSize
            let margin = id == attendedNodeID ? attentionStickyMargin : attentionMargin
            guard abs(hit.x) <= half.x + margin, abs(hit.y) <= half.y + margin else { continue }
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }
        attendedNodeID = best?.id
    }

    /// 주시 카드 위를 지나는 엣지를 카드 바깥으로 밀어내는 제어점 오프셋(루트 로컬). 해당 없으면 0.
    ///
    /// 주시 노드의 로컬 좌표에서, 현(弦) 위 카드 중심에 가장 가까운 점이 카드 사각형(+간격) 안에 있으면 현에 수직이고
    /// 중심에서 바깥을 향하는 방향으로 밀어낸다. 2차 베지어는 매개변수 t에서 제어점 오프셋의 2t(1−t)배만큼 현을 벗어나므로
    /// 그만큼 나눠 준다. 살짝 카드 정면(+Z)으로도 띄운다.
    private func avoidanceDeflection(from fromID: String, to toID: String, start: SIMD3<Float>, end: SIMD3<Float>) -> SIMD3<Float> {
        guard let attended = attendedNodeID, attended != fromID, attended != toID,
              let focusEntity = nodeEntities[attended] else { return .zero }
        let half = halfSizes[attended] ?? defaultHalfSize

        let a = focusEntity.convert(position: start, from: root)
        let b = focusEntity.convert(position: end, from: root)
        let chord = b - a
        let chordLength2 = simd_dot(chord, chord)
        guard chordLength2 > 1e-6 else { return .zero }
        let t = min(max(simd_dot(-a, chord) / chordLength2, 0), 1)
        let nearest = a + chord * t   // 카드 중심(원점) 기준 오프셋

        let reachX = half.x + avoidanceClearance
        let reachY = half.y + avoidanceClearance
        guard abs(nearest.x) < reachX, abs(nearest.y) < reachY, abs(nearest.z) < 0.9 else { return .zero }

        var normal = SIMD3<Float>(-chord.y, chord.x, 0)
        let normalLength = simd_length(normal)
        guard normalLength > 1e-5 else { return .zero }
        normal /= normalLength
        if simd_dot(normal, nearest) < 0 { normal = -normal }

        let extent = abs(normal.x) * reachX + abs(normal.y) * reachY
        let clearance = max(extent - simd_dot(nearest, normal), 0) + 0.02
        let curvature = max(t * (1 - t), 0.08)
        let control = min(clearance / (2 * curvature), 1.2)
        let local = normal * control + SIMD3<Float>(0, 0, 0.04)
        return focusEntity.convert(direction: local, to: root)
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
