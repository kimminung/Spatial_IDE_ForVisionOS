import SwiftUI
import RealityKit
import simd

/// 엣지(호출/소유/오류/종료) 엔티티에 붙는 상태.
struct EdgeEndpointsComponent: Component {
    let fromNodeID: String
    let toNodeID: String
    let kind: CodeEdgeKind
    /// 현재 엣지 길이(미터). 자식 실린더의 Y 스케일에 그대로 쓰인다.
    var length: Float = 0
    /// 0~1 사이를 반복하는 흐름 진행도. 일시정지 상태에서는 점멸 타이머로 쓴다.
    var flowPhase: Float = 0
    /// 시작 노드에 브레이크포인트가 걸려 실행이 멈춘 상태인지.
    var isPaused = false
    /// 소유 체인 모드: 직선 대신 사용자 쪽으로 불룩한 파란 곡선으로 그리고, 화살촉이 담는 쪽을 향한다.
    var isContainment = false
    /// 끝점이 노드 중심에서 벗어난 현재 오프셋(미터). 토큰이 선택되면 그 토큰 위치로, 아니면 카드 테두리로 부드럽게 이동한다.
    var startOffset: SIMD3<Float> = .zero
    var endOffset: SIMD3<Float> = .zero
    /// **주시 회피** 곡선의 제어점 오프셋(루트 로컬, 현 중점 기준). 사용자가 바라보는 카드 위를 지나는 엣지가
    /// 그 카드를 비켜 가도록 `GraphSceneController`가 매 프레임 목표를 주고, 여기서 부드럽게 따라간다. 0이면 직선.
    var deflection: SIMD3<Float> = .zero
    /// 강조 상태에 따라 펄스/머리를 보여야 하는지(`setEmphasis`가 정한다). 곡선↔직선 전환 시 되살릴 때 쓴다.
    var showsFlow = true
    var showsHead = true

    /// 곡선으로 그려야 하는 상태인지(소유 체인, 또는 주시 회피 중).
    var isCurved: Bool { isContainment || simd_length(deflection) > 0.004 }
}

/// 토큰 선택에 따른 엣지 강조 상태.
enum EdgeEmphasis {
    case normal
    case highlighted
    case dimmed
    /// 선택 토큰의 소유 체인에 속한 `owns` 엣지: 짙은 파란 곡선.
    case containment
}

/// `CodeEdge`를 시각화하는 엔티티를 생성·갱신한다.
///
/// 엣지 하나는 컨테이너 아래에 다음으로 구성된다.
/// - 선(line) / 펄스(pulse) / 머리(head): 직선 표현. 종류에 따라 색·방향·속도·감속이 다르다.
/// - 곡선 그룹(curve): 세그먼트 실린더 N개 + 머리 + 펄스. 두 경우에 직선을 대신한다.
///   1. **소유 체인**(`owns`, containment): 사용자 쪽(+Z)으로 불룩한 파란 곡선, 담기는 쪽 → 담는 쪽으로 펄스.
///   2. **주시 회피**(모든 종류): 사용자가 바라보는 카드 위를 지나는 엣지가 그 카드 바깥으로 휘어 글자를 가리지 않는다.
///      색·방향·속도는 직선일 때와 같고, 시선이 떠나면 제어점이 0으로 돌아가 다시 직선이 된다.
///
/// 종류별 흐름 언어:
/// - `owns`  구조적 소유. 흐리고 느린 작은 펄스. 소유 체인 모드에서는 파란 곡선.
/// - `calls` 일반 호출. 기본 펄스가 호출 방향으로 흐른다.
/// - `throwsError` 오류 전파. 빨간 펄스가 **역방향**(호출된 쪽 → 호출한 쪽)으로 빠르게 흐른다.
/// - `terminates` 종료. 짙은 빨간 펄스가 끝으로 갈수록 감속·축소하며 소멸하고, 끝에는 정지 막대.
/// - 브레이크포인트로 일시정지된 엣지: 펄스가 출발점에 멈춘 채 빨갛게 점멸.
@MainActor
enum EdgeEntityFactory {

    // 카드 텍스트(footnote ≈ 12 pt ≈ 9 mm)를 가리지 않도록 선은 1 mm대, 화살촉은 글자 한 자보다 작게 둔다.
    private static let baseRadius: Float = 0.0011
    private static let pulseRadius: Float = 0.0022
    private static let headHeight: Float = 0.012
    private static let headRadius: Float = 0.0042
    private static let headInset: Float = 0.004

    private static let curveSegments = 8
    private static let curveRadius: Float = 0.0013

    static let lineName = "line"
    static let pulseName = "pulse"
    static let headName = "head"
    static let curveName = "curve"
    static let curveHeadName = "curveHead"
    static let curvePulseName = "curvePulse"

    // MARK: - 생성

    static func makeEdge(edge: CodeEdge, from start: SIMD3<Float>, to end: SIMD3<Float>, palette: ScenePalette) -> Entity {
        let container = Entity()
        container.name = "edge:\(edge.from)->\(edge.to)"
        container.components.set(EdgeEndpointsComponent(fromNodeID: edge.from, toNodeID: edge.to, kind: edge.kind))

        let line = ModelEntity(mesh: .generateCylinder(height: 1, radius: baseRadius), materials: [UnlitMaterial()])
        line.name = lineName
        container.addChild(line)

        let pulse = ModelEntity(mesh: .generateCylinder(height: 1, radius: pulseRadius), materials: [UnlitMaterial()])
        pulse.name = pulseName
        container.addChild(pulse)

        let head = ModelEntity(mesh: headMesh(for: edge.kind), materials: [UnlitMaterial()])
        head.name = headName
        if edge.kind == .throwsError {
            head.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        }
        container.addChild(head)

        container.addChild(makeCurveGroup(kind: edge.kind))

        setEmphasis(container, .normal, isPaused: false, palette: palette)
        update(container, from: start, to: end)
        return container
    }

    private static func headMesh(for kind: CodeEdgeKind) -> MeshResource {
        switch kind {
        case .terminates:
            .generateBox(width: headRadius * 2.4, height: 0.0025, depth: headRadius * 2.4, cornerRadius: 0.0008)
        default:
            .generateCone(height: headHeight, radius: headRadius)
        }
    }

    /// 곡선 그룹: 세그먼트 실린더 N개 + 머리 + 펄스. 처음엔 꺼져 있다.
    private static func makeCurveGroup(kind: CodeEdgeKind) -> Entity {
        let group = Entity()
        group.name = curveName
        group.isEnabled = false

        for index in 0..<curveSegments {
            let segment = ModelEntity(mesh: .generateCylinder(height: 1, radius: curveRadius), materials: [UnlitMaterial()])
            segment.name = "seg\(index)"
            group.addChild(segment)
        }

        // 소유 체인 곡선은 원뿔, 그 외 종류는 직선일 때와 같은 머리를 쓴다.
        let head = ModelEntity(mesh: kind == .owns ? .generateCone(height: headHeight, radius: headRadius) : headMesh(for: kind),
                               materials: [UnlitMaterial()])
        head.name = curveHeadName
        group.addChild(head)

        let pulse = ModelEntity(mesh: .generateCylinder(height: 1, radius: pulseRadius), materials: [UnlitMaterial()])
        pulse.name = curvePulseName
        group.addChild(pulse)

        return group
    }

    // MARK: - 배치

    /// 컨테이너의 위치·방향·길이를 두 끝점에 맞추고, 끝점 오프셋과 회피 곡선을 목표값으로 부드럽게 옮긴다. 매 프레임 호출한다.
    static func update(
        _ container: Entity,
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        startTarget: SIMD3<Float> = .zero,
        endTarget: SIMD3<Float> = .zero,
        deflectionTarget: SIMD3<Float> = .zero,
        deltaTime: Float = 0
    ) {
        guard var endpoints = container.components[EdgeEndpointsComponent.self] else { return }

        let blend = deltaTime > 0 ? 1 - exp(-deltaTime * 12) : 1
        endpoints.startOffset = simd_mix(endpoints.startOffset, startTarget, SIMD3(repeating: blend))
        endpoints.endOffset = simd_mix(endpoints.endOffset, endTarget, SIMD3(repeating: blend))
        // 회피 곡선은 조금 느리게 따라가 시선이 스치는 순간마다 튀지 않게 한다.
        let bendBlend = deltaTime > 0 ? 1 - exp(-deltaTime * 7) : 1
        endpoints.deflection = simd_mix(endpoints.deflection, deflectionTarget, SIMD3(repeating: bendBlend))
        if simd_length(endpoints.deflection) < 0.002 { endpoints.deflection = .zero }

        let (length, midpoint, rotation) = geometry(from: start + endpoints.startOffset, to: end + endpoints.endOffset)

        container.position = midpoint
        container.orientation = rotation
        endpoints.length = length
        container.components.set(endpoints)

        container.findEntity(named: lineName)?.scale = SIMD3<Float>(1, max(length, 0.001), 1)

        if let head = container.findEntity(named: headName) {
            let inset = headHeight / 2 + headInset
            let atEnd = endpoints.kind != .throwsError
            head.position = SIMD3<Float>(0, (atEnd ? 1 : -1) * (length / 2 - inset), 0)
        }

        layoutPulse(in: container, endpoints: endpoints)

        if endpoints.isCurved {
            layoutCurve(in: container, endpoints: endpoints)
        }
        applyMode(container, endpoints: endpoints)
    }

    /// 직선 부품과 곡선 그룹 중 현재 상태에 맞는 쪽만 보이게 한다.
    private static func applyMode(_ container: Entity, endpoints: EdgeEndpointsComponent) {
        let curved = endpoints.isCurved
        let kind = endpoints.kind
        container.findEntity(named: lineName)?.isEnabled = !curved
        container.findEntity(named: pulseName)?.isEnabled = !curved && endpoints.showsFlow
        container.findEntity(named: headName)?.isEnabled = !curved && endpoints.showsHead && kind != .owns
        if let group = container.findEntity(named: curveName) {
            group.isEnabled = curved
            if curved {
                let head = group.findEntity(named: curveHeadName)
                let pulse = group.findEntity(named: curvePulseName)
                head?.isEnabled = endpoints.isContainment || (endpoints.showsHead && kind != .owns)
                if !endpoints.showsFlow { pulse?.isEnabled = false }
            }
        }
    }

    // MARK: - 곡선

    /// 컨테이너 로컬 프레임에서의 2차 베지어 제어점. 시작(-L/2) → 끝(+L/2).
    /// - 소유 체인: 제어점이 세계 +Z(사용자 쪽)로 불룩.
    /// - 주시 회피: 제어점 = 루트 로컬 `deflection`을 컨테이너 로컬로 가져온 것.
    private static func curveControlPoints(in container: Entity, endpoints: EdgeEndpointsComponent) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let length = endpoints.length
        let p0 = SIMD3<Float>(0, -length / 2, 0)
        let p2 = SIMD3<Float>(0, length / 2, 0)

        let p1: SIMD3<Float>
        if endpoints.isContainment {
            // 세계 +Z를 로컬로 가져와 현(弦) 방향(Y) 성분을 제거하면 현에 수직인 불룩 방향이 된다.
            var bulge = container.orientation.inverse.act(SIMD3<Float>(0, 0, 1))
            bulge.y = 0
            if simd_length(bulge) < 0.05 { bulge = SIMD3<Float>(1, 0, 0) }
            p1 = simd_normalize(bulge) * max(0.08, length * 0.28)
        } else {
            p1 = container.orientation.inverse.act(endpoints.deflection)
        }
        return (p0, p1, p2)
    }

    private static func bezier(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let u = 1 - t
        return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
    }

    private static func bezierTangent(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let d = (p1 - p0) * (2 * (1 - t)) + (p2 - p1) * (2 * t)
        let len = simd_length(d)
        return len > .ulpOfOne ? d / len : SIMD3<Float>(0, 1, 0)
    }

    private static func layoutCurve(in container: Entity, endpoints: EdgeEndpointsComponent) {
        guard let group = container.findEntity(named: curveName) else { return }
        let (p0, p1, p2) = curveControlPoints(in: container, endpoints: endpoints)

        for index in 0..<curveSegments {
            guard let segment = group.findEntity(named: "seg\(index)") else { continue }
            let a = bezier(p0, p1, p2, Float(index) / Float(curveSegments))
            let b = bezier(p0, p1, p2, Float(index + 1) / Float(curveSegments))
            let (len, mid, rot) = geometry(from: a, to: b)
            segment.position = mid
            segment.orientation = rot
            segment.scale = SIMD3<Float>(1, max(len, 0.001), 1)
        }

        if let head = group.findEntity(named: curveHeadName) {
            let inset = headHeight / 2 + headInset
            if endpoints.isContainment || endpoints.kind == .throwsError {
                // 담는 쪽 / 호출한 쪽(p0)에서 곡선 밖을 향한다.
                let outward = -bezierTangent(p0, p1, p2, 0)
                head.orientation = simd_quatf(from: [0, 1, 0], to: outward)
                head.position = p0 - outward * inset
            } else {
                let forward = bezierTangent(p0, p1, p2, 1)
                head.orientation = simd_quatf(from: [0, 1, 0], to: forward)
                head.position = p2 - forward * inset
            }
        }

        layoutCurvePulse(in: group, endpoints: endpoints, p0: p0, p1: p1, p2: p2)
    }

    private static func layoutCurvePulse(in group: Entity, endpoints: EdgeEndpointsComponent, p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>) {
        guard let pulse = group.findEntity(named: curvePulseName) else { return }
        let phase = endpoints.flowPhase
        let pulseLength = min(0.045, max(endpoints.length * 0.2, 0.01))

        // 곡선 위 위치(t): 소유 체인과 오류 전파는 역방향, 종료는 감속, 그 외는 정방향.
        let t: Float
        var visible = true
        if endpoints.isPaused {
            t = 0.05
            visible = phase < 0.5
        } else if endpoints.isContainment || endpoints.kind == .throwsError {
            t = 1 - phase
        } else if endpoints.kind == .terminates {
            t = 1 - pow(1 - phase, 3)
            visible = phase < 0.92
        } else {
            t = phase
        }

        pulse.position = bezier(p0, p1, p2, t)
        pulse.orientation = simd_quatf(from: [0, 1, 0], to: bezierTangent(p0, p1, p2, t))
        pulse.scale = SIMD3<Float>(1, pulseLength, 1)
        // 양 끝 근처에서는 카드 텍스트와 겹치므로 잠깐 숨긴다.
        pulse.isEnabled = visible && endpoints.showsFlow && t > 0.06 && t < 0.94
    }

    // MARK: - 흐름

    static func advanceFlow(_ container: Entity, deltaTime: Float) {
        guard var endpoints = container.components[EdgeEndpointsComponent.self], endpoints.length > 0,
              endpoints.showsFlow else { return }   // 연결만 나타내는 엣지(소유, 흐림 상태)는 애니메이션하지 않는다

        if endpoints.isPaused {
            endpoints.flowPhase = (endpoints.flowPhase + deltaTime * 1.4).truncatingRemainder(dividingBy: 1)
        } else {
            let speed = endpoints.isContainment ? 0.35 : flowSpeed(for: endpoints.kind)
            endpoints.flowPhase = (endpoints.flowPhase + deltaTime * speed / endpoints.length).truncatingRemainder(dividingBy: 1)
        }

        container.components.set(endpoints)

        if endpoints.isCurved {
            if let group = container.findEntity(named: curveName) {
                let (p0, p1, p2) = curveControlPoints(in: container, endpoints: endpoints)
                layoutCurvePulse(in: group, endpoints: endpoints, p0: p0, p1: p1, p2: p2)
            }
        } else {
            layoutPulse(in: container, endpoints: endpoints)
        }
    }

    private static func flowSpeed(for kind: CodeEdgeKind) -> Float {
        switch kind {
        case .owns:        0.15
        case .calls:       0.45
        case .throwsError: 0.70
        case .terminates:  0.50
        }
    }

    private static func layoutPulse(in container: Entity, endpoints: EdgeEndpointsComponent) {
        guard let pulse = container.findEntity(named: pulseName) else { return }
        let length = endpoints.length
        let phase = endpoints.flowPhase

        var pulseLength = min(0.06, max(length * 0.25, 0.01))
        if endpoints.kind == .owns { pulseLength *= 0.5 }
        let travel = max(length - pulseLength, 0)

        if endpoints.isPaused {
            pulse.scale = SIMD3<Float>(1.15, pulseLength, 1.15)
            pulse.position = SIMD3<Float>(0, -travel / 2, 0)
            pulse.isEnabled = !endpoints.isCurved && endpoints.showsFlow && phase < 0.5
            return
        }

        var visible = true
        switch endpoints.kind {
        case .throwsError:
            pulse.scale = SIMD3<Float>(1, pulseLength, 1)
            pulse.position = SIMD3<Float>(0, travel / 2 - travel * phase, 0)
        case .terminates:
            let eased = 1 - pow(1 - phase, 3)
            pulse.scale = SIMD3<Float>(1, pulseLength * max(1 - phase * 0.7, 0.15), 1)
            pulse.position = SIMD3<Float>(0, -travel / 2 + travel * eased, 0)
            visible = phase < 0.92
        default:
            pulse.scale = SIMD3<Float>(1, pulseLength, 1)
            pulse.position = SIMD3<Float>(0, -travel / 2 + travel * phase, 0)
        }
        pulse.isEnabled = visible && !endpoints.isCurved && endpoints.showsFlow
    }

    // MARK: - 강조·색

    /// 강조 상태, 일시정지 여부, 외관 팔레트에 맞춰 선·펄스·머리·곡선의 색과 표시를 갱신한다.
    static func setEmphasis(_ container: Entity, _ emphasis: EdgeEmphasis, isPaused: Bool, palette: ScenePalette) {
        guard var endpoints = container.components[EdgeEndpointsComponent.self] else { return }
        let isContainment = emphasis == .containment && endpoints.kind == .owns
        let kind = endpoints.kind

        let lineOpacity: Float
        let showsFlow: Bool
        switch emphasis {
        case .normal:      (lineOpacity, showsFlow) = (palette.edgeOpacityNormal(for: kind), true)
        case .highlighted: (lineOpacity, showsFlow) = (palette.edgeOpacityHighlighted, true)
        case .dimmed:      (lineOpacity, showsFlow) = (palette.edgeOpacityDimmed, false)
        case .containment: (lineOpacity, showsFlow) = (0, true)
        }

        endpoints.isPaused = isPaused
        endpoints.isContainment = isContainment
        // 소유(`owns`)는 "연결"만 나타내므로 흐름 펄스를 두지 않는다. 담김 곡선도 화살촉만으로 방향을 보인다.
        endpoints.showsFlow = kind != .owns && showsFlow
        endpoints.showsHead = kind != .owns
        container.components.set(endpoints)

        let lineColor = isPaused ? palette.errorFlow : palette.lineColor(for: kind)
        let pulseColor = isPaused ? palette.errorFlow : palette.pulseColor(for: kind)
        let headOpacity: Float = emphasis == .dimmed ? palette.edgeOpacityDimmed : 0.9

        if let line = container.findEntity(named: lineName) as? ModelEntity {
            line.model?.materials = [unlit(lineColor, opacity: lineOpacity)]
        }
        if let pulse = container.findEntity(named: pulseName) as? ModelEntity {
            pulse.model?.materials = [unlit(pulseColor, opacity: palette.edgePulseOpacity)]
        }
        if let head = container.findEntity(named: headName) as? ModelEntity {
            head.model?.materials = [unlit(pulseColor, opacity: headOpacity)]
        }

        // 곡선 그룹: 소유 체인이면 파랑, 주시 회피면 직선과 같은 색.
        if let group = container.findEntity(named: curveName) {
            let segmentMaterial = isContainment
                ? unlit(palette.containmentFlow, opacity: 0.95)
                : unlit(lineColor, opacity: max(lineOpacity, emphasis == .dimmed ? palette.edgeOpacityDimmed : palette.edgeOpacityNormal(for: kind)))
            let accentMaterial = isContainment ? unlit(palette.containmentFlow, opacity: 0.95) : unlit(pulseColor, opacity: palette.edgePulseOpacity)
            for child in group.children {
                guard let model = child as? ModelEntity else { continue }
                model.model?.materials = [child.name == curveHeadName || child.name == curvePulseName ? accentMaterial : segmentMaterial]
            }
            if let head = group.findEntity(named: curveHeadName) as? ModelEntity, !isContainment {
                head.model?.materials = [unlit(pulseColor, opacity: headOpacity)]
            }
        }

        if endpoints.isCurved {
            layoutCurve(in: container, endpoints: endpoints)
        }
        applyMode(container, endpoints: endpoints)
    }

    private static func unlit(_ color: SwiftUI.Color, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color.realityKitColor)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    // MARK: - 기하

    static func geometry(from start: SIMD3<Float>, to end: SIMD3<Float>) -> (length: Float, midpoint: SIMD3<Float>, rotation: simd_quatf) {
        let delta = end - start
        let length = simd_length(delta)
        let midpoint = (start + end) / 2

        guard length > .ulpOfOne else {
            return (0, midpoint, simd_quatf(angle: 0, axis: [0, 1, 0]))
        }

        let direction = delta / length
        return (length, midpoint, simd_quatf(from: [0, 1, 0], to: direction))
    }
}
