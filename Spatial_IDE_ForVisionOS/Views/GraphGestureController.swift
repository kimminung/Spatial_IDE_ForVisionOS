import SwiftUI
import RealityKit
import simd

/// 그래프 전체에 대한 전역 제스처(확대/축소, 회전, 이동)를 처리한다.
///
/// 특정 엔티티를 응시할 필요 없이 어디를 보고 있어도 동작한다. 단, 서로 다른 제스처가 한 동작에
/// 동시에 반응해 혼란스럽지 않도록, 임계값을 먼저 넘은 제스처 하나만 활성화하고 나머지는
/// 그 제스처가 끝날 때까지 무시한다(모드 잠금).
///
/// - 두 손 핀치 후 벌리기/모으기 → 확대/축소 (Apple HIG 표준)
/// - 두 손 핀치 후 돌리기 → 축 제한 없는 자유 회전. 피벗은 루트 엔티티의 원점(= 그래프 중심)이다.
/// - 한 손 핀치 후 끌기 → 그래프 이동
@Observable
@MainActor
final class GraphGestureController {
    enum Mode { case none, magnify, rotate, drag }

    /// 조작 대상 루트 엔티티. 씬이 만들어질 때 주입된다.
    var root: Entity?

    private(set) var mode: Mode = .none

    private var committedScale: Float = 1
    private var committedOrientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var committedPosition: SIMD3<Float> = .zero

    /// 활성화 임계값: 배율 편차, 회전 각도(라디안).
    private let magnifyThreshold: Float = 0.06
    private let rotateThreshold: Float = .pi / 30   // 6°

    // MARK: Magnify

    func magnifyChanged(_ magnification: Float) {
        guard let root else { return }
        if mode == .none, abs(magnification - 1) > magnifyThreshold {
            mode = .magnify
            committedScale = root.scale.x
        }
        guard mode == .magnify else { return }
        root.scale = SIMD3(repeating: max(0.2, min(5, committedScale * magnification)))
    }

    func magnifyEnded() {
        guard mode == .magnify else { return }
        mode = .none
    }

    // MARK: Rotate (free, all axes)

    func rotateChanged(_ rotation: Rotation3D) {
        guard let root else { return }
        let delta = realityKitQuaternion(from: rotation)
        if mode == .none, abs(delta.angle) > rotateThreshold {
            mode = .rotate
            committedOrientation = root.orientation
        }
        guard mode == .rotate else { return }
        // 제스처 회전은 사용자(세계) 기준 프레임에서 주어지므로, 기존 회전 앞에 곱해(pre-multiply)
        // 그래프가 현재 어떤 자세이든 손이 도는 방향 그대로 돌게 한다.
        root.orientation = simd_normalize(delta * committedOrientation)
    }

    func rotateEnded() {
        guard mode == .rotate else { return }
        mode = .none
    }

    // MARK: Drag (translate)

    /// - Parameter translation: ImmersiveSpace 좌표계 기준 이동량(포인트).
    func dragChanged(_ translation: Vector3D) {
        guard let root else { return }
        if mode == .none {
            mode = .drag
            committedPosition = root.position
        }
        guard mode == .drag else { return }
        let meters = SIMD3<Float>(
            Float(translation.x),
            -Float(translation.y),   // SwiftUI는 +y가 아래, RealityKit은 +y가 위
            Float(translation.z)
        ) / SceneStyle.pointsPerMeter
        root.position = committedPosition + meters
    }

    func dragEnded() {
        guard mode == .drag else { return }
        mode = .none
    }

    // MARK: Helpers

    /// SwiftUI 3D 좌표계(+y 아래)의 회전을 RealityKit 좌표계(+y 위)의 회전으로 바꾼다.
    ///
    /// 두 좌표계는 Y축 반사 관계라 손잡이(handedness)가 반대다. 반사 M = diag(1,-1,1)로 회전을 공액하면
    /// (M R M) 축은 M·axis, 각도 부호는 반전된다. 쿼터니언으로는 허수부 (ix, iy, iz) → (-ix, iy, -iz).
    /// (세로축(Y) 회전 성분은 그대로 유지되고, X/Z 축 회전은 방향이 뒤집힌다.)
    private func realityKitQuaternion(from rotation: Rotation3D) -> simd_quatf {
        let q = rotation.quaternion
        return simd_normalize(simd_quatf(
            ix: -Float(q.imag.x),
            iy: Float(q.imag.y),
            iz: -Float(q.imag.z),
            r: Float(q.real)
        ))
    }
}

/// 전역 그래프 제스처를 뷰에 붙인다. `RealityView`와 각 코드 카드(attachment)에 모두 적용해,
/// 카드를 보고 있든 빈 공간(입력 판)을 보고 있든 같은 제스처가 동작하게 한다.
struct GraphGesturesModifier: ViewModifier {
    let controller: GraphGestureController

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { controller.magnifyChanged(Float($0.magnification)) }
                    .onEnded { _ in controller.magnifyEnded() }
            )
            .simultaneousGesture(
                RotateGesture3D(constrainedToAxis: nil, minimumAngleDelta: .degrees(2))
                    .onChanged { controller.rotateChanged($0.rotation) }
                    .onEnded { _ in controller.rotateEnded() }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .immersiveSpace)
                    .onChanged { controller.dragChanged($0.translation3D) }
                    .onEnded { _ in controller.dragEnded() }
            )
    }
}

extension View {
    func graphGestures(_ controller: GraphGestureController) -> some View {
        modifier(GraphGesturesModifier(controller: controller))
    }
}
