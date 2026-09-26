import SwiftUI
import RealityKit

/// ImmersiveSpace 안에서 코드 그래프를 렌더링하는 최상위 뷰.
///
/// - Phase 1: 노드 위치 배치
/// - Phase 2: 엣지 렌더링 + 코드 카드(attachment). 카드는 텍스트만 있다.
/// - Phase 3: 공간 인터랙션
///   - 카드 안의 식별자 토큰: 응시 → 시스템 Hover 하이라이트, 핀치 → 선택 → 쓰임새 흐름 강조
///   - 카드 거터 탭 → 브레이크포인트 토글 → 그 노드에서 나가는 엣지가 출발점에 멈춰 점멸
///   - 그래프 전체: 시선과 무관한 전역 제스처(두 손 확대/축소·자유 회전, 한 손 이동), 모드 잠금으로 구분
/// - Phase 4: JSON 그래프 로드 + 엣지 종류(소유/호출/오류 전파/종료)별로 다른 흐름 표현, 하단 범례
/// - Phase 5: Z축 코드 접힘 — `catch`/`guard … else` 본문을 별도 attachment로 떼어 카드 뒤(-Z)로 꺾어 놓는다.
/// - Phase 6: 대규모 대응 — 인덱서가 만든 실제 그래프(수백 노드)를 **포커스 모델**로 표시한다.
///   보이는 노드(`AppModel.visibleNodes`)만 attachment와 엔티티를 갖고, 접힌 컨테이너는 칩 하나,
///   포커스 밖 관계는 배치 라인 메시로 그린다. 씬은 `GraphSceneController`가 증분 갱신한다.
///
/// 외관: 시스템 라이트/다크 설정(`colorScheme`)을 그대로 따른다.
struct CodeSpaceImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var gestures = GraphGestureController()
    @State private var scene = GraphSceneController()

    /// 접힘 블록의 힌지 위치(노드 로컬 미터). 키는 접힘 attachment ID. 카드가 헤더 줄 프레임을 측정해 보고한다.
    @State private var foldHinges: [String: SIMD3<Float>] = [:]
    /// 접힘 블록 attachment의 렌더링 크기(포인트). 키는 접힘 attachment ID.
    @State private var foldSizes: [String: CGSize] = [:]

    private static let legendAttachmentID = "flow-legend"
    private static let searchAttachmentID = "symbol-search"

    private var palette: ScenePalette { ScenePalette(scheme: colorScheme) }

    var body: some View {
        RealityView { content, attachments in
            content.add(ImmersiveBackdropFactory.makeSkyDome(palette: palette))

            scene.root.position = appModel.layout.origin
            content.add(scene.root)
            gestures.root = scene.root

            if let legend = attachments.entity(for: Self.legendAttachmentID) {
                scene.legendAnchor.addChild(legend)
            }
            if let search = attachments.entity(for: Self.searchAttachmentID) {
                scene.searchAnchor.addChild(search)
            }

            // 매 프레임: 포커스 엣지를 노드(또는 선택된 토큰) 위치에 동기화하고 흐름 펄스를 전진시킨다.
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                scene.tick(deltaTime: Float(event.deltaTime), endpointAnchors: appModel.activeEdgeAnchors)
            }
        } update: { content, attachments in
            if let dome = content.entities.first(where: { $0.name == ImmersiveBackdropFactory.entityName }) {
                ImmersiveBackdropFactory.apply(palette, to: dome)
            }

            // 보이는 집합·카드 크기·펼침 상태가 바뀌면 레이아웃을 다시 계산해 씬을 증분 갱신한다.
            let visible = appModel.visibleNodes
            let sizes = appModel.cardSizes.mapValues {
                SIMD2<Float>(Float($0.width), Float($0.height)) / SceneStyle.pointsPerMeter
            }
            let positions = appModel.layout.positions(
                visible: visible,
                index: appModel.index,
                expanded: appModel.expandedIDs,
                sizes: sizes,
                isCard: appModel.isCard
            )
            let edges = appModel.edgeSets
            scene.sync(
                visible: visible,
                isCard: appModel.isCard,
                positions: positions,
                focusEdges: edges.focus,
                contextEdges: edges.context,
                foldRegions: CodeFolder.regions(for:),
                foldHinges: foldHinges,
                foldSizes: foldSizes,
                palette: palette,
                attachments: attachments
            )
            scene.applyEmphasis(
                highlighted: appModel.highlightedNodeIDs,
                containment: appModel.containmentNodeIDs,
                pausedNodeIDs: appModel.pausedNodeIDs,
                palette: palette
            )
        } attachments: {
            ForEach(appModel.visibleNodes) { node in
                Attachment(id: node.id) {
                    if appModel.isCard(node) {
                        codePanel(for: node)
                    } else {
                        NodeChipView(
                            node: node,
                            descendantCount: appModel.index.descendantCount(of: node.id),
                            isDimmed: isDimmed(node),
                            isHighlighted: touchesFlow(node),
                            onTap: { appModel.toggleExpansion(node.id) },
                            onSizeChange: { appModel.setCardSize(nodeID: node.id, size: $0) }
                        )
                        .graphGestures(gestures)
                    }
                }

                if appModel.isCard(node) {
                    let lines = CodeTokenizer.tokenize(node.codeSnippet ?? "")
                    ForEach(CodeFolder.regions(in: lines)) { region in
                        let key = FoldAttachmentKey(nodeID: node.id, regionID: region.id)
                        Attachment(id: key.attachmentID) {
                            FoldedBlockView(
                                node: node,
                                region: region,
                                lines: CodeFolder.bodyLines(of: region, in: lines),
                                selectedToken: appModel.selectedToken,
                                isDimmed: isDimmed(node),
                                breakpointLines: breakpointLines(of: node),
                                onTapToken: { token in
                                    appModel.toggleSelection(TokenSelection(nodeID: node.id, text: token))
                                },
                                onToggleBreakpoint: { line in
                                    appModel.toggleBreakpoint(Breakpoint(nodeID: node.id, line: line))
                                },
                                onSizeChange: { size in
                                    foldSizes[key.attachmentID] = size
                                }
                            )
                            .graphGestures(gestures)
                        }
                    }
                }
            }

            Attachment(id: Self.legendAttachmentID) {
                FlowLegendView()
            }
            Attachment(id: Self.searchAttachmentID) {
                SearchPanelView()
            }
        }
        .graphGestures(gestures)
        .onImmersionChange { _, newValue in
            appModel.immersionAmount = newValue.amount ?? 0
        }
    }

    // MARK: - 카드

    private func codePanel(for node: CodeNode) -> some View {
        CodePanelView(
            node: node,
            selectedToken: appModel.selectedToken,
            isDimmed: isDimmed(node),
            breakpointLines: breakpointLines(of: node),
            onTapToken: { token in
                appModel.toggleSelection(TokenSelection(nodeID: node.id, text: token))
            },
            onToggleBreakpoint: { line in
                appModel.toggleBreakpoint(Breakpoint(nodeID: node.id, line: line))
            },
            onTokenAnchorChange: { offset in
                appModel.setTokenAnchor(nodeID: node.id, offset: offset)
            },
            onFoldHingeChange: { hinges in
                for (regionID, offset) in hinges {
                    foldHinges[FoldAttachmentKey(nodeID: node.id, regionID: regionID).attachmentID] = offset
                }
            },
            onSizeChange: { appModel.setCardSize(nodeID: node.id, size: $0) },
            onCollapse: appModel.index.hasChildren(node.id) ? { appModel.collapse(node.id) } : nil
        )
        .graphGestures(gestures)
    }

    // MARK: - 카드 상태

    private func isDimmed(_ node: CodeNode) -> Bool {
        guard let highlighted = appModel.highlightedNodeIDs else { return false }
        return !highlighted.contains(node.id) && !touchesFlow(node)
    }

    /// 선택 토큰의 흐름에 포함된 노드가 이 컨테이너 안쪽(자손)에 있는지. 칩을 흐리게 하지 않고 테두리로 알린다.
    private func touchesFlow(_ node: CodeNode) -> Bool {
        guard let highlighted = appModel.highlightedNodeIDs else { return false }
        return highlighted.contains { appModel.index.ancestors(of: $0).contains(node.id) }
    }

    private func breakpointLines(of node: CodeNode) -> Set<Int> {
        Set(appModel.breakpoints.filter { $0.nodeID == node.id }.map(\.line))
    }
}
