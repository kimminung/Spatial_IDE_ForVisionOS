import Foundation
import simd

/// Z축 깊이 기반 공간 레이아웃.
///
/// - X: 같은 호출 깊이의 노드를 중앙 정렬로 균등 분포
/// - Y: 노드 종류(kind)별 고정 오프셋 (모듈은 위, 변수는 아래)
/// - Z: 호출 깊이가 깊어질수록 사용자에서 멀어지는 방향(-Z)으로 배치
///
/// 모든 단위는 미터(m). ImmersiveSpace 원점은 앱 실행 시 사용자 발밑이다.
struct SpatialLayout: Sendable {
    /// 깊이 0 레벨의 중심 위치. 기본값은 눈높이 근처, 사용자 정면 1.5m.
    var origin: SIMD3<Float> = [0, 1.3, -1.5]

    /// 같은 깊이 레벨 내 노드 간 X축 간격.
    var horizontalSpacing: Float = 0.35

    /// 깊이 1단계당 Z축 후퇴 거리.
    var depthSpacing: Float = 0.5

    /// 노드 종류별 Y축 오프셋.
    func verticalOffset(for kind: CodeNodeKind) -> Float {
        switch kind {
        case .module: 0.25
        case .type: 0.10
        case .function: 0.0
        case .variable: -0.15
        }
    }

    /// 그래프의 모든 노드에 대해 3D 좌표를 계산한다.
    /// - Returns: 노드 ID → 위치(SIMD3<Float>) 사전.
    func positions(for graph: CodeGraph) -> [String: SIMD3<Float>] {
        let depths = graph.callDepths()

        // 깊이별로 노드를 묶고, 결정적(deterministic) 배치를 위해 ID로 정렬한다.
        var nodesByDepth: [Int: [CodeNode]] = [:]
        for node in graph.nodes {
            nodesByDepth[depths[node.id] ?? 0, default: []].append(node)
        }

        var result: [String: SIMD3<Float>] = [:]

        for (depth, nodes) in nodesByDepth {
            let sorted = nodes.sorted { $0.id < $1.id }
            let count = Float(sorted.count)
            let z = origin.z - Float(depth) * depthSpacing

            for (index, node) in sorted.enumerated() {
                // (index - (count-1)/2) 로 중앙 정렬
                let x = origin.x + (Float(index) - (count - 1) / 2) * horizontalSpacing
                let y = origin.y + verticalOffset(for: node.kind)
                result[node.id] = SIMD3<Float>(x, y, z)
            }
        }

        return result
    }
}
