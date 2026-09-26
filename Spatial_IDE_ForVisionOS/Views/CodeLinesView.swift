import SwiftUI

/// 코드 줄 묶음을 거터 + 토큰 단위로 그리는 공용 뷰. 카드(`CodePanelView`)와
/// Z축으로 접힌 블록(`FoldedBlockView`)이 같은 규칙으로 코드를 표시하도록 공유한다.
///
/// - 식별자 토큰: 응시 하이라이트(시스템) + 핀치로 선택.
/// - 거터: 탭으로 브레이크포인트 토글, `throw/try/catch` 줄엔 빨간 바, `fatalError/exit` 줄엔 정지 표식.
/// - 접힘 헤더 줄(`foldHeaders`)에는 줄 끝에 힌지 글리프를 붙이고 줄 프레임을 보고한다.
struct CodeLinesView: View {
    @Environment(\.colorScheme) private var colorScheme

    let node: CodeNode
    let lines: [CodeLine]
    let selectedToken: TokenSelection?
    let breakpointLines: Set<Int>
    /// 엣지 끝점이 붙을 토큰. 이 토큰의 프레임을 `coordinateSpaceName` 기준으로 보고한다.
    let anchorTokenID: Int?
    let coordinateSpaceName: String
    /// 헤더 줄 번호 → 그 줄 아래로 접혀 들어간 영역.
    let foldHeaders: [Int: CodeFoldRegion]
    let onTapToken: (String) -> Void
    let onToggleBreakpoint: (Int) -> Void
    let onAnchorFrame: (CGRect?) -> Void
    let onFoldHeaderFrame: (CodeFoldRegion, CGRect) -> Void

    private var palette: ScenePalette { ScenePalette(scheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines) { line in
                lineView(line)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: CodeLine) -> some View {
        let row = HStack(spacing: 0) {
            gutter(for: line)
            ForEach(line.tokens) { token in
                tokenView(token)
            }
            if let region = foldHeaders[line.id] {
                foldHinge(for: region)
            }
        }
        if let region = foldHeaders[line.id] {
            row.onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(coordinateSpaceName))
            } action: { frame in
                onFoldHeaderFrame(region, frame)
            }
        } else {
            row
        }
    }

    // MARK: - 접힘 힌지 표식

    /// 헤더 줄 끝의 표식: "이 아래 N줄이 Z축으로 접혀 있다". 색은 접힘 종류(오류 처리/조기 탈출)를 따른다.
    private func foldHinge(for region: CodeFoldRegion) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.turn.down.right")
            Text("\(region.lineCount)")
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(palette.foldHinge(for: region.kind))
        .padding(.leading, 8)
        .accessibilityLabel("\(region.lineCount)줄이 뒤로 접혀 있음")
    }

    // MARK: - 거터 (브레이크포인트 / 오류 / 종료 표식)

    private enum LineMarker { case none, error, terminate }

    private func marker(for line: CodeLine) -> LineMarker {
        let words = Set(line.tokens.filter { $0.kind == .keyword || $0.kind == .identifier }.map(\.text))
        if !words.isDisjoint(with: ["fatalError", "exit", "abort", "preconditionFailure", "assertionFailure"]) {
            return .terminate
        }
        if !words.isDisjoint(with: ["throw", "throws", "try", "catch"]) {
            return .error
        }
        return .none
    }

    @ViewBuilder
    private func gutter(for line: CodeLine) -> some View {
        let hasBreakpoint = breakpointLines.contains(line.id)
        Button {
            onToggleBreakpoint(line.id)
        } label: {
            ZStack {
                if hasBreakpoint {
                    UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 6, topTrailingRadius: 6)
                        .fill(palette.breakpointMarker)
                        .frame(width: 12, height: 11)
                } else {
                    switch marker(for: line) {
                    case .error:
                        RoundedRectangle(cornerRadius: 1)
                            .fill(palette.errorFlow)
                            .frame(width: 3, height: 11)
                    case .terminate:
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(palette.terminateFlow)
                            .frame(width: 8, height: 8)
                    case .none:
                        Color.clear
                    }
                }
            }
            .frame(width: 16, height: 14)
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 3))
        .hoverEffect()
        .padding(.trailing, 4)
        .accessibilityLabel(hasBreakpoint ? "브레이크포인트 해제" : "브레이크포인트 설정")
    }

    // MARK: - 토큰

    @ViewBuilder
    private func tokenView(_ token: CodeToken) -> some View {
        if token.isInteractive {
            let isSelected = selectedToken?.nodeID == node.id && selectedToken?.text == token.text
            let isAnchor = token.id == anchorTokenID
            let accent = node.kind.color(for: colorScheme)
            Button {
                onTapToken(token.text)
            } label: {
                Text(token.text)
                    .foregroundStyle(isSelected || isAnchor ? accent : token.kind.color(for: colorScheme))
                    .underline(isSelected, color: accent)
            }
            .buttonStyle(.plain)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 4))
            .hoverEffect()
            .onGeometryChange(for: CGRect?.self) { proxy in
                isAnchor ? proxy.frame(in: .named(coordinateSpaceName)) : nil
            } action: { frame in
                if isAnchor { onAnchorFrame(frame) }
            }
        } else {
            Text(token.text)
                .foregroundStyle(token.kind.color(for: colorScheme))
        }
    }
}
