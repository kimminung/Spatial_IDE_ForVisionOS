import SwiftUI

/// 노드 종류별 표시 색상. 두 외관 모두에서 충분한 대비를 갖도록 라이트/다크 값을 따로 둔다.
extension CodeNodeKind {
    func color(for scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.module, .dark):     Color(red: 0.98, green: 0.62, blue: 0.20)
        case (.module, _):         Color(red: 0.80, green: 0.42, blue: 0.00)
        case (.type, .dark):       Color(red: 0.36, green: 0.62, blue: 1.00)
        case (.type, _):           Color(red: 0.05, green: 0.38, blue: 0.85)
        case (.function, .dark):   Color(red: 0.30, green: 0.85, blue: 0.65)
        case (.function, _):       Color(red: 0.00, green: 0.55, blue: 0.40)
        case (.variable, .dark):   Color(red: 0.80, green: 0.55, blue: 0.95)
        case (.variable, _):       Color(red: 0.50, green: 0.20, blue: 0.75)
        }
    }
}

/// 코드 토큰 종류별 구문 강조 색. 식별자·구두점은 시스템 적응형 색(`.primary`)을 써서
/// 외관이 바뀌면 자동으로 따라간다.
extension CodeTokenKind {
    func color(for scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.identifier, _):      .primary
        case (.punctuation, _):     .primary.opacity(0.75)
        case (.whitespace, _):      .clear
        case (.keyword, .dark):     Color(red: 1.00, green: 0.48, blue: 0.70)
        case (.keyword, _):         Color(red: 0.66, green: 0.05, blue: 0.57)
        case (.typeName, .dark):    Color(red: 0.62, green: 0.86, blue: 1.00)
        case (.typeName, _):        Color(red: 0.05, green: 0.35, blue: 0.70)
        case (.number, .dark):      Color(red: 1.00, green: 0.90, blue: 0.55)
        case (.number, _):          Color(red: 0.55, green: 0.32, blue: 0.00)
        case (.string, .dark):      Color(red: 1.00, green: 0.62, blue: 0.45)
        case (.string, _):          Color(red: 0.77, green: 0.10, blue: 0.09)
        case (.comment, .dark):     Color(white: 0.62)
        case (.comment, _):         Color(red: 0.36, green: 0.45, blue: 0.38)
        }
    }
}

/// 3D 씬(RealityKit 머티리얼)에서 쓰는 색·불투명도 팔레트. 시스템 외관(라이트/다크)에 따라 만든다.
///
/// RealityKit 머티리얼은 SwiftUI처럼 환경값을 따라 자동으로 바뀌지 않으므로,
/// `colorScheme`이 바뀔 때 이 팔레트를 새로 만들어 머티리얼에 다시 적용한다.
struct ScenePalette: Equatable {
    let scheme: ColorScheme

    /// 크라운으로 패스스루를 걷어낸 영역에 보이는 몰입 배경(스카이 돔) 색.
    var immersiveBackdrop: Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.06, blue: 0.10)   // 짙은 남색
            : Color(red: 0.93, green: 0.94, blue: 0.97)   // 옅은 회청색
    }

    /// 엣지 기본 선 색.
    var edge: Color {
        scheme == .dark ? Color(white: 0.85) : Color(white: 0.20)
    }

    /// 엣지를 따라 흘러가는 펄스(밝은 구간) 색.
    var edgePulse: Color {
        scheme == .dark
            ? Color(red: 0.75, green: 1.00, blue: 0.95)
            : Color(red: 0.00, green: 0.50, blue: 0.45)
    }

    /// 오류 전파·브레이크포인트 일시정지 펄스의 빨강.
    var errorFlow: Color {
        scheme == .dark ? Color(red: 1.00, green: 0.36, blue: 0.36) : Color(red: 0.85, green: 0.10, blue: 0.10)
    }

    /// 종료 경로의 짙은 빨강.
    var terminateFlow: Color {
        scheme == .dark ? Color(red: 0.80, green: 0.08, blue: 0.12) : Color(red: 0.58, green: 0.00, blue: 0.04)
    }

    /// 선택 토큰이 "무엇에 담겨 있는지"를 보여주는 소유 체인(곡선 엣지)의 짙은 파랑.
    var containmentFlow: Color {
        scheme == .dark ? Color(red: 0.22, green: 0.45, blue: 1.00) : Color(red: 0.03, green: 0.20, blue: 0.68)
    }

    /// 엣지 종류별 기본 선 색.
    func lineColor(for kind: CodeEdgeKind) -> Color {
        switch kind {
        case .owns:        edge.opacity(0.6)
        case .calls:       edge
        case .throwsError: errorFlow
        case .terminates:  terminateFlow
        }
    }

    /// 엣지 종류별 펄스(흐름 구간) 색.
    func pulseColor(for kind: CodeEdgeKind) -> Color {
        switch kind {
        case .owns:        edge
        case .calls:       edgePulse
        case .throwsError: errorFlow
        case .terminates:  terminateFlow
        }
    }

    /// 선택이 없을 때 / 흐름에 포함될 때 / 흐름 밖일 때의 엣지 선 불투명도.
    func edgeOpacityNormal(for kind: CodeEdgeKind) -> Float {
        let base: Float = scheme == .dark ? 0.35 : 0.45
        return kind == .owns ? base * 0.5 : base
    }
    var edgeOpacityHighlighted: Float { 0.9 }
    var edgeOpacityDimmed: Float { 0.06 }

    /// 펄스 불투명도.
    var edgePulseOpacity: Float { 0.95 }

    /// 카드 거터의 브레이크포인트 표식 색(Xcode 관례를 따라 파랑).
    var breakpointMarker: Color {
        scheme == .dark ? Color(red: 0.25, green: 0.56, blue: 1.00) : Color(red: 0.00, green: 0.40, blue: 0.90)
    }

    /// 가장 최근에 펼친 카드의 테두리(형광 핑크). 축소해서 전체를 볼 때 방금 열었던 곳을 찾는 표식이다.
    var recentExpansion: Color {
        scheme == .dark ? Color(red: 1.00, green: 0.25, blue: 0.70) : Color(red: 0.95, green: 0.10, blue: 0.60)
    }

    /// 펼친 블록(타입 카드 + 멤버들)을 묶는 형광 테두리 색. 최근 펼침 표식(형광 핑크)과 같은 채도·밝기로, 블록마다 색조만 돌려 써서
    /// 이웃 블록과 구분된다. `seed`는 블록 컨테이너 ID의 해시 등 안정적인 정수.
    func groupFrame(seed: Int) -> Color {
        let hues: [Double] = [0.52, 0.30, 0.09, 0.76, 0.16, 0.62]   // 시안, 라임, 오렌지, 바이올렛, 옐로, 블루(핑크는 최근 표식에 양보)
        let hue = hues[abs(seed) % hues.count]
        return scheme == .dark
            ? Color(hue: hue, saturation: 0.80, brightness: 1.0)
            : Color(hue: hue, saturation: 0.90, brightness: 0.80)
    }
    /// 그룹 테두리 불투명도. 형광 핑크 표식과 같은 수준으로 또렷하게.
    var groupFrameOpacity: Float { 0.95 }

    /// Z축으로 접힌 블록의 힌지 표식 색. 접힌 것이 예외·탈출 경로이므로 엣지의 빨강 계열을 재사용한다.
    func foldHinge(for kind: CodeFoldRegion.Kind) -> Color {
        switch kind {
        case .catchBlock: errorFlow
        case .guardElse:  terminateFlow
        }
    }
}

/// 외관과 무관한 공용 치수·상수.
enum SceneStyle {
    /// visionOS에서 SwiftUI 포인트 ↔ 미터 변환 비율. RealityView attachment도 이 비율로 렌더링된다.
    static let pointsPerMeter: Float = 1360

    /// 흐름 밖 카드의 텍스트 불투명도.
    static let dimmedCardOpacity: Double = 0.3

    /// 접힌 코드 블록이 카드 평면에서 뒤(-Z)로 꺾이는 각도(라디안). 90°가 아니라 78°로 두어
    /// 정면에서도 얇은 띠가 남아 "여기 뭔가 접혀 있다"는 단서가 보이게 한다.
    static let foldAngle: Float = .pi * 78 / 180
}
