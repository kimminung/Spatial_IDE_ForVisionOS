import SwiftUI
import RealityKit
import UIKit

// UIKit을 남기는 유일한 지점.
//
// RealityKit의 머티리얼·파티클 색상 타입 `Material.Color` / `ParticleEmitterComponent.ParticleEmitter.Color`는
// visionOS에서 `UIColor`의 typealias이며, SwiftUI `Color`를 직접 받는 API가 없다.
// 색상의 원본 정의는 모두 SwiftUI `Color`(`CodeNodeKind+Style.swift`)에 두고,
// RealityKit에 넘길 때만 여기서 한 번 변환한다.
extension Color {
    /// SwiftUI `Color`를 RealityKit 머티리얼/파티클이 요구하는 색상 타입으로 변환한다.
    var realityKitColor: RealityKit.Material.Color {
        UIColor(self)
    }
}
