import ARKit
import QuartzCore
import OSLog

/// 기기(머리) 자세를 ARKit `WorldTrackingProvider`로 읽는다.
///
/// visionOS는 시선(눈) 위치를 앱에 주지 않으므로, "사용자가 바라보는 곳"은 **머리가 향한 방향**으로 근사한다.
/// 이 광선이 지나는 카드를 `GraphSceneController`가 "주시 노드"로 잡아, 그 카드 위를 지나는 엣지를 곡선으로 비켜 준다.
/// 월드 트래킹은 별도 권한 요청이 없고, 시뮬레이터에서도 가상 머리 자세가 나온다.
@MainActor
final class HeadPoseTracker {
    private static let logger = Logger(subsystem: "CodeSpace", category: "HeadPose")

    private let session = ARKitSession()
    private let provider = WorldTrackingProvider()
    private(set) var isRunning = false

    func start() async {
        guard WorldTrackingProvider.isSupported, !isRunning else { return }
        do {
            try await session.run([provider])
            isRunning = true
        } catch {
            Self.logger.error("월드 트래킹 시작 실패: \(error.localizedDescription). 주시 회피 없이 동작합니다.")
        }
    }

    func stop() {
        guard isRunning else { return }
        session.stop()
        isRunning = false
    }

    /// 현재(예측) 기기 자세. 원점은 ImmersiveSpace의 월드 원점과 같다. 추적 중이 아니면 nil.
    var deviceTransform: simd_float4x4? {
        guard isRunning, provider.state == .running,
              let anchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        return anchor.originFromAnchorTransform
    }
}
