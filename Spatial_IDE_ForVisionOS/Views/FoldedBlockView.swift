import SwiftUI

/// 카드에서 떼어 내어 Z축으로 접힌 코드 블록(`catch` 본문, `guard … else` 본문).
///
/// 카드 평면과 같은 규칙(`CodeLinesView`)으로 코드를 그리되, 왼쪽에 접힘 종류 색의 얇은
/// 힌지 바를 둔다. 이 뷰는 `CodeSpaceImmersiveView`가 힌지 피벗 엔티티 아래에 attachment로
/// 붙이며, 피벗이 Y축으로 회전해 있어 본문이 카드 뒤(-Z)로 뻗어 나간다. 정면에서는 얇은
/// 띠로만 보이고, 그래프를 기울이면 본문이 드러난다.
///
/// 접힌 본문 안의 토큰·거터도 카드와 똑같이 동작한다(선택 → 쓰임새 흐름, 거터 → 브레이크포인트).
struct FoldedBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    let node: CodeNode
    let region: CodeFoldRegion
    let lines: [CodeLine]
    let selectedToken: TokenSelection?
    let isDimmed: Bool
    let breakpointLines: Set<Int>
    let onTapToken: (String) -> Void
    let onToggleBreakpoint: (Int) -> Void
    /// 렌더링된 크기(포인트). 피벗 기준으로 왼쪽 위 모서리를 힌지에 맞추는 데 쓴다.
    let onSizeChange: (CGSize) -> Void

    private static let blockSpace = "foldedBlock"

    private var palette: ScenePalette { ScenePalette(scheme: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(palette.foldHinge(for: region.kind))
                .frame(width: 2)
            CodeLinesView(
                node: node,
                lines: lines,
                selectedToken: selectedToken,
                breakpointLines: breakpointLines,
                anchorTokenID: nil,
                coordinateSpaceName: Self.blockSpace,
                foldHeaders: [:],
                onTapToken: onTapToken,
                onToggleBreakpoint: onToggleBreakpoint,
                onAnchorFrame: { _ in },
                onFoldHeaderFrame: { _, _ in }
            )
        }
        .font(.system(.footnote, design: .monospaced))
        .fixedSize()
        .coordinateSpace(name: Self.blockSpace)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .shadow(color: colorScheme == .dark ? .black.opacity(0.85) : .white.opacity(0.9), radius: 2)
        .opacity(isDimmed ? SceneStyle.dimmedCardOpacity : 1)
        .animation(.easeInOut(duration: 0.2), value: isDimmed)
    }
}
