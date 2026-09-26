import SwiftUI

/// 접힌 컨테이너(모듈·타입)를 대신하는 작은 칩. 탭하면 펼쳐져 자기 카드와 자식들이 나타난다.
///
/// 코드 카드와 달리 배경(캡슐)이 있다. 코드가 아니라 "여기 N개가 접혀 있다"는 구조 표식이라
/// 시각적으로 구분되어야 하고, 응시 하이라이트가 잡힐 면적도 필요하기 때문이다.
struct NodeChipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let node: CodeNode
    /// 이 안에 접혀 있는 자손 수.
    let descendantCount: Int
    let isDimmed: Bool
    /// 선택 토큰의 흐름이 이 컨테이너 안쪽 어딘가에 닿는지.
    let isHighlighted: Bool
    let onTap: () -> Void
    let onSizeChange: (CGSize) -> Void

    private var accent: Color { node.kind.color(for: colorScheme) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: node.kind.symbolName)
                    .foregroundStyle(accent)
                Text(node.name)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(1)
                Text("\(descendantCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(isHighlighted ? accent : .clear, lineWidth: 1.5))
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect()
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .opacity(isDimmed ? SceneStyle.dimmedCardOpacity : 1)
        .animation(.easeInOut(duration: 0.2), value: isDimmed)
        .accessibilityLabel("\(node.name), 항목 \(descendantCount)개, 펼치기")
    }
}

extension CodeNodeKind {
    /// 칩·검색 결과에서 종류를 나타내는 SF Symbol.
    var symbolName: String {
        switch self {
        case .module:   "shippingbox"
        case .type:     "cube"
        case .function: "function"
        case .variable: "v.square"
        }
    }
}
