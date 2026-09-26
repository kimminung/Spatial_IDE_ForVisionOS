import RealityKit
import Metal
import SwiftUI

/// 접힌 컨테이너로 묶인 컨텍스트 엣지(수백~수천 개)를 **하나의 메시**로 그린다.
///
/// 포커스 안의 엣지는 종류별 흐름 애니메이션이 있는 리치 엔티티(`EdgeEntityFactory`)로 그리지만,
/// 그 밖의 관계는 정보량이 "어디와 어디가 얼마나 연결됐나" 수준이라 얇은 선으로 충분하다.
/// 엣지마다 엔티티를 만들면 드로우 콜과 엔티티 갱신 비용이 엣지 수에 비례하므로, 여기서는
/// `LowLevelMesh`에 선분 정점을 채워 넣고 가중치(묶인 엣지 수) 구간별로 파트를 나눠 불투명도만 달리한다.
@MainActor
final class ContextEdgeMesh {
    struct Segment {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        /// 이 선분에 묶인 원본 엣지 수. 많을수록 진하게.
        let weight: Int
    }

    let entity = ModelEntity()

    private var mesh: LowLevelMesh?
    private var vertexCapacity = 0
    private static let bucketOpacities: [Float] = [0.14, 0.30, 0.55]

    init() {
        entity.name = "ContextEdges"
        entity.isEnabled = false
    }

    /// 선분 집합을 통째로 교체한다. 보이는 노드 집합이 바뀔 때만 호출되므로 매 프레임 비용은 없다.
    func update(_ segments: [Segment], palette: ScenePalette) {
        guard !segments.isEmpty else {
            entity.isEnabled = false
            return
        }

        let neededVertices = segments.count * 2
        if mesh == nil || neededVertices > vertexCapacity {
            var capacity = max(64, vertexCapacity)
            while capacity < neededVertices { capacity *= 2 }
            guard let newMesh = try? Self.makeMesh(vertexCapacity: capacity),
                  let resource = try? MeshResource(from: newMesh) else { return }
            mesh = newMesh
            vertexCapacity = capacity
            entity.model = ModelComponent(mesh: resource, materials: Self.materials(palette))
        }
        guard let mesh else { return }

        // 가중치 구간별로 정렬해 각 구간이 연속된 인덱스 범위(= 파트 하나)가 되게 한다.
        let sorted = segments.sorted { Self.bucket($0.weight) < Self.bucket($1.weight) }

        var minPoint = sorted[0].start
        var maxPoint = sorted[0].start
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { buffer in
            let vertices = buffer.bindMemory(to: SIMD3<Float>.self)
            for (index, segment) in sorted.enumerated() {
                vertices[index * 2] = segment.start
                vertices[index * 2 + 1] = segment.end
                minPoint = simd_min(minPoint, simd_min(segment.start, segment.end))
                maxPoint = simd_max(maxPoint, simd_max(segment.start, segment.end))
            }
        }
        mesh.withUnsafeMutableIndices { buffer in
            let indices = buffer.bindMemory(to: UInt32.self)
            for index in 0..<neededVertices { indices[index] = UInt32(index) }
        }

        let bounds = BoundingBox(min: minPoint - 0.01, max: maxPoint + 0.01)
        var parts: [LowLevelMesh.Part] = []
        var indexStart = 0
        for bucket in 0..<Self.bucketOpacities.count {
            let count = sorted.filter { Self.bucket($0.weight) == bucket }.count * 2
            guard count > 0 else { continue }
            parts.append(LowLevelMesh.Part(
                indexOffset: indexStart * MemoryLayout<UInt32>.stride,
                indexCount: count,
                topology: .line,
                materialIndex: bucket,
                bounds: bounds
            ))
            indexStart += count
        }
        mesh.parts.replaceAll(parts)

        entity.model?.materials = Self.materials(palette)
        entity.isEnabled = true
    }

    /// 외관이 바뀌었을 때 색만 다시 적용한다.
    func applyPalette(_ palette: ScenePalette) {
        entity.model?.materials = Self.materials(palette)
    }

    // MARK: - 내부

    private static func bucket(_ weight: Int) -> Int {
        switch weight {
        case ..<2: 0
        case 2..<5: 1
        default: 2
        }
    }

    private static func materials(_ palette: ScenePalette) -> [UnlitMaterial] {
        bucketOpacities.map { opacity in
            var material = UnlitMaterial(color: palette.edge.realityKitColor)
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            return material
        }
    }

    private static func makeMesh(vertexCapacity: Int) throws -> LowLevelMesh {
        let attributes = [LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: 0)]
        let layouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)]
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: vertexCapacity,
            vertexAttributes: attributes,
            vertexLayouts: layouts,
            indexCapacity: vertexCapacity
        )
        return try LowLevelMesh(descriptor: descriptor)
    }
}
