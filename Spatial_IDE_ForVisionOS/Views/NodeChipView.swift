import SwiftUI

/// 펼치지 않은 노드를 대신하는 작은 칩. 두 가지 모습이 있다.
///
/// - **컨테이너 칩**(모듈·타입): 종류 아이콘 + 이름 + 안에 접힌 자손 수. 탭하면 자식들이 나타난다.
/// - **시그니처 칩**(함수·긴 프로퍼티): 종류 아이콘 + 선언 첫 줄. 탭하면 본문 카드가 열린다.
///   타입 하나에 멤버가 수십 개여도 한 줄씩이면 눈높이 안에 들어오고, 본문은 보고 싶은 것만 연다.
///
/// 코드 카드와 달리 배경(캡슐)이 있다. "여기 접혀 있다"는 구조 표식이라 시각적으로 구분되어야 하고,
/// 응시 하이라이트가 잡힐 면적도 필요하기 때문이다.
struct NodeChipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let node: CodeNode
    /// 이 안에 접혀 있는 자손 수. 0이면 시그니처 칩으로 그린다.
    let descendantCount: Int
    let isDimmed: Bool
    /// 선택 토큰의 흐름이 이 노드(또는 컨테이너 안쪽 어딘가)에 닿는지.
    let isHighlighted: Bool
    let onTap: () -> Void
    let onSizeChange: (CGSize) -> Void

    private var accent: Color { node.kind.color(for: colorScheme) }
    private var isSignature: Bool { descendantCount == 0 }

    /// 선언 첫 줄. 끝의 여는 중괄호는 뗀다.
    private var signature: String {
        let firstLine = node.codeSnippet?.split(separator: "\n").first.map(String.init) ?? node.name
        var text = firstLine.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("{") { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        return text
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: node.kind.symbolName)
                    .foregroundStyle(accent)
                if isSignature {
                    Text(signature)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 460, alignment: .leading)
                } else {
                    Text(node.name)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                    Text("\(descendantCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
        .accessibilityLabel(isSignature ? "\(node.name), 본문 열기" : "\(node.name), 항목 \(descendantCount)개, 펼치기")
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
