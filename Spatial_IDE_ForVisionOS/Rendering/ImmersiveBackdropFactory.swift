import RealityKit

/// 사용자를 감싸는 몰입 배경(스카이 돔).
///
/// `.progressive` 몰입 스타일에서 디지털 크라운을 돌리면 패스스루가 걷히는 포털 영역이 커지는데,
/// 그 안에는 앱이 그린 것만 보인다. 배경이 없으면 그 영역이 검게 비어 보이므로, 사용자를 중심으로
/// 큰 구체를 두고 안쪽 면을 단색으로 채워 코드가 잘 읽히는 배경을 만든다.
/// 색은 시스템 외관(라이트/다크)에 따라 `ScenePalette`에서 가져오며, 외관이 바뀌면 `apply`로 갈아입힌다.
/// 이 구체는 그래프 루트가 아니라 씬에 직접 추가되어, 그래프를 확대·회전·이동해도 함께 움직이지 않는다.
@MainActor
enum ImmersiveBackdropFactory {
    static let entityName = "ImmersiveBackdrop"

    static func makeSkyDome(palette: ScenePalette, radius: Float = 30) -> ModelEntity {
        let dome = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material(for: palette)])
        dome.name = entityName
        return dome
    }

    /// 외관이 바뀌었을 때 돔의 색을 새 팔레트로 교체한다.
    static func apply(_ palette: ScenePalette, to dome: Entity) {
        (dome as? ModelEntity)?.model?.materials = [material(for: palette)]
    }

    private static func material(for palette: ScenePalette) -> UnlitMaterial {
        var material = UnlitMaterial(color: palette.immersiveBackdrop.realityKitColor)
        // 구체의 안쪽에서 보므로 바깥을 향한 면(front)을 컬링하고 안쪽 면만 그린다.
        material.faceCulling = .front
        return material
    }
}
