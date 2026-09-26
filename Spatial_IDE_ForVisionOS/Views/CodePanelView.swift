import SwiftUI

/// 3D 노드에 붙어 항상 떠 있는 코드 카드. 테두리·배경 없이 코드 텍스트만 있다.
///
/// 코드는 토큰 단위로 그려지며, 식별자(변수·타입·함수 이름) 토큰만 상호작용 대상이다.
/// - 응시: 시스템이 토큰에 Hover 하이라이트를 그린다. (visionOS는 시선 위치를 앱에 알려주지 않는다.)
/// - 핀치(탭): 토큰을 선택해 그 쓰임새 흐름(관련 노드와 엣지)을 강조한다. 다시 탭하면 해제.
/// - 선택된 토큰 텍스트가 이 카드에 있으면, 그 토큰의 위치를 노드 중심 기준 3D 오프셋으로 보고해
///   엣지 끝점이 노드 중심 대신 **그 토큰**에 붙도록 한다.
///
/// 각 줄 왼쪽에는 거터가 있다.
/// - 거터를 탭하면 그 줄에 브레이크포인트를 토글한다(파란 표식). 브레이크포인트가 있는 노드에서
///   나가는 엣지는 출발점에 멈춰 빨갛게 점멸해 "실행이 여기서 멈춘다"를 보여준다.
/// - `throw` / `try` / `catch` 줄에는 빨간 바, `fatalError` / `exit` 줄에는 정지 표식이 자동으로 붙는다.
///
/// **Z축 접힘**: `catch` 블록과 `guard … else` 본문은 이 카드에 그리지 않는다. 헤더 줄만 남기고
/// 줄 끝에 힌지 글리프를 표시하며, 헤더 줄 왼쪽 아래 모서리의 위치를 노드 중심 기준 미터 오프셋으로
/// 보고한다(`onFoldHingeChange`). 본문은 `FoldedBlockView`가 그 자리에서 뒤(-Z)로 꺾여 붙는다.
///
/// **컨테이너 카드**: 펼친 타입·모듈의 카드는 왼쪽 위에 작은 접기 버튼(`onCollapse`)이 있다.
struct CodePanelView: View {
    @Environment(\.colorScheme) private var colorScheme

    let node: CodeNode
    let selectedToken: TokenSelection?
    /// 이 카드가 현재 쓰임새 흐름 밖에 있어 흐리게 보여야 하는지.
    let isDimmed: Bool
    /// 이 노드에 걸린 브레이크포인트 줄 번호들.
    let breakpointLines: Set<Int>
    let onTapToken: (String) -> Void
    let onToggleBreakpoint: (Int) -> Void
    /// 선택 토큰의 위치(노드 중심 기준 미터 오프셋). 이 카드에 해당 토큰이 없으면 nil.
    let onTokenAnchorChange: (SIMD3<Float>?) -> Void
    /// 접힘 영역 ID → 힌지 위치(노드 중심 기준 미터 오프셋).
    let onFoldHingeChange: ([Int: SIMD3<Float>]) -> Void
    /// 렌더링 크기(포인트). 레이아웃이 카드가 겹치지 않게 배치하는 데 쓴다.
    var onSizeChange: ((CGSize) -> Void)? = nil
    /// 컨테이너(타입·모듈) 카드일 때만 제공: 자식들을 다시 접는다.
    var onCollapse: (() -> Void)? = nil

    private static let cardSpace = "codeCard"

    @State private var cardSize: CGSize = .zero
    @State private var anchorTokenFrame: CGRect?
    @State private var foldHeaderFrames: [Int: CGRect] = [:]

    private var allLines: [CodeLine] {
        CodeTokenizer.tokenize(node.codeSnippet ?? "// 코드 없음")
    }

    private var foldRegions: [CodeFoldRegion] { CodeFolder.regions(in: allLines) }

    /// 접힌 본문을 제외하고 카드 평면에 남는 줄.
    private var visibleLines: [CodeLine] {
        let folded = CodeFolder.foldedLineIDs(of: foldRegions)
        return allLines.filter { !folded.contains($0.id) }
    }

    private var foldHeaders: [Int: CodeFoldRegion] {
        Dictionary(uniqueKeysWithValues: foldRegions.map { ($0.headerLine, $0) })
    }

    /// 선택 토큰 텍스트와 일치하는 첫 식별자 토큰(카드 평면에 보이는 줄 안에서). 엣지 끝점이 붙을 자리다.
    private var anchorTokenID: Int? {
        guard let text = selectedToken?.text else { return nil }
        for line in visibleLines {
            if let token = line.tokens.first(where: { $0.isInteractive && $0.text == text }) {
                return token.id
            }
        }
        return nil
    }

    /// 카드 중심 기준 토큰 위치를 미터로 환산한 오프셋. SwiftUI는 +y가 아래이므로 부호를 뒤집는다.
    private var anchorOffset: SIMD3<Float>? {
        guard let frame = anchorTokenFrame, cardSize != .zero else { return nil }
        return offset(ofPoint: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// 접힘 힌지 = 헤더 줄의 왼쪽 아래 모서리. 접힌 평면의 왼쪽 위 모서리가 여기에 맞물린다.
    private var foldHinges: [Int: SIMD3<Float>] {
        guard cardSize != .zero else { return [:] }
        return foldHeaderFrames.mapValues { frame in
            offset(ofPoint: CGPoint(x: frame.minX, y: frame.maxY))
        }
    }

    private func offset(ofPoint point: CGPoint) -> SIMD3<Float> {
        let dx = Float(point.x - cardSize.width / 2) / SceneStyle.pointsPerMeter
        let dy = -Float(point.y - cardSize.height / 2) / SceneStyle.pointsPerMeter
        return SIMD3<Float>(dx, dy, 0.002)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let onCollapse {
                collapseButton(onCollapse)
            }
            CodeLinesView(
                node: node,
                lines: visibleLines,
                selectedToken: selectedToken,
                breakpointLines: breakpointLines,
                anchorTokenID: anchorTokenID,
                coordinateSpaceName: Self.cardSpace,
                foldHeaders: foldHeaders,
                onTapToken: onTapToken,
                onToggleBreakpoint: onToggleBreakpoint,
                onAnchorFrame: { anchorTokenFrame = $0 },
                onFoldHeaderFrame: { region, frame in foldHeaderFrames[region.id] = frame }
            )
        }
        .font(.system(.footnote, design: .monospaced))
        .fixedSize()
        .coordinateSpace(name: Self.cardSpace)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            cardSize = size
            onSizeChange?(size)
        }
        .shadow(color: colorScheme == .dark ? .black.opacity(0.85) : .white.opacity(0.9), radius: 2)
        .opacity(isDimmed ? SceneStyle.dimmedCardOpacity : 1)
        .animation(.easeInOut(duration: 0.2), value: isDimmed)
        .onChange(of: anchorTokenID, initial: true) { _, newValue in
            if newValue == nil { anchorTokenFrame = nil }
        }
        .onChange(of: anchorOffset, initial: true) { _, newValue in
            onTokenAnchorChange(newValue)
        }
        .onChange(of: foldHinges, initial: true) { _, newValue in
            onFoldHingeChange(newValue)
        }
    }

    private var collapseLabel: String {
        switch node.kind {
        case .module:   "모듈 접기"
        case .type:     "타입 접기"
        case .function: "본문 접기"
        case .variable: "본문 접기"
        }
    }

    /// 펼친 노드를 다시 칩으로 접는 작은 버튼. 코드가 아닌 구조 조작이라 카드 본문과 분리해 위에 둔다.
    private func collapseButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up")
                Text(collapseLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect()
        .accessibilityLabel("\(node.name) 접기")
    }
}
