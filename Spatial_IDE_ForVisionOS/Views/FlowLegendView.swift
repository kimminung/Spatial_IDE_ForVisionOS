import SwiftUI

/// 엣지 흐름의 색·형태가 무엇을 뜻하는지 알려주는 작은 범례. 그래프 아래에 attachment로 붙는다.
struct FlowLegendView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ScenePalette { ScenePalette(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 14) {
            item(color: palette.pulseColor(for: .calls), shape: .arrow, label: "호출")
            item(color: palette.pulseColor(for: .owns), shape: .dot, label: "소유(정적)")
            item(color: palette.errorFlow, shape: .reverseArrow, label: "오류 전파")
            item(color: palette.terminateFlow, shape: .stop, label: "종료")
            item(color: palette.containmentFlow, shape: .curve, label: "담김")
            item(color: palette.errorFlow, shape: .pausedBlink, label: "브레이크포인트")
            item(color: palette.foldHinge(for: .catchBlock), shape: .fold, label: "접힘(Z축)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private enum Glyph { case arrow, reverseArrow, dot, stop, curve, pausedBlink, fold }

    @ViewBuilder
    private func item(color: Color, shape: Glyph, label: String) -> some View {
        HStack(spacing: 5) {
            glyph(shape, color: color)
            Text(label)
        }
    }

    @ViewBuilder
    private func glyph(_ shape: Glyph, color: Color) -> some View {
        switch shape {
        case .arrow:
            Image(systemName: "arrow.right").foregroundStyle(color)
        case .reverseArrow:
            Image(systemName: "arrow.left").foregroundStyle(color)
        case .dot:
            Circle().fill(color.opacity(0.6)).frame(width: 6, height: 6)
        case .stop:
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 8, height: 8)
        case .curve:
            Image(systemName: "arrow.turn.left.up").foregroundStyle(color)
        case .pausedBlink:
            Image(systemName: "pause.fill").foregroundStyle(color)
        case .fold:
            Image(systemName: "arrow.turn.down.right").foregroundStyle(color)
        }
    }
}
