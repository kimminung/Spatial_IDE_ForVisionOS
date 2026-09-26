import SwiftUI
import RealityKit

/// ImmersiveSpace 안에서 코드 그래프를 렌더링하는 최상위 뷰.
///
/// - Phase 1: 노드 위치 배치
/// - Phase 2: 엣지 렌더링 + 모든 노드에 코드 카드(attachment) 상시 표시. 카드는 텍스트만 있다.
/// - Phase 3: 공간 인터랙션
///   - 카드 안의 식별자 토큰: 응시 → 시스템 Hover 하이라이트, 핀치 → 선택 → 쓰임새 흐름 강조
///   - 카드 거터 탭 → 브레이크포인트 토글 → 그 노드에서 나가는 엣지가 출발점에 멈춰 점멸
///   - 그래프 전체: 시선과 무관한 전역 제스처(두 손 확대/축소·자유 회전, 한 손 이동), 모드 잠금으로 구분
/// - Phase 4: JSON 그래프 로드 + 엣지 종류(소유/호출/오류 전파/종료)별로 다른 흐름 표현, 하단 범례
/// - Phase 5: Z축 코드 접힘 — `catch`/`guard … else` 본문을 별도 attachment로 떼어, 카드의 헤더 줄
///   왼쪽 아래 모서리(힌지)에 Y축 78° 회전한 피벗 엔티티로 붙여 카드 뒤(-Z)로 꺾어 놓는다.
///
/// 외관: 시스템 라이트/다크 설정(`colorScheme`)을 그대로 따른다.
struct CodeSpaceImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var gestures = GraphGestureController()

    /// 접힘 블록의 힌지 위치(노드 로컬 미터). 카드가 헤더 줄 프레임을 측정해 보고한다.
    @State private var foldHinges: [FoldKey: SIMD3<Float>] = [:]
    /// 접힘 블록 attachment의 렌더링 크기(포인트). 왼쪽 위 모서리를 힌지에 맞추는 데 쓴다.
    @State private var foldSizes: [FoldKey: CGSize] = [:]

    private static let legendAttachmentID = "flow-legend"

    private var palette: ScenePalette { ScenePalette(scheme: colorScheme) }

    /// 노드 ID → 그 노드 코드의 접힘 영역들. 스니펫은 정적이므로 매번 계산해도 비용이 작다.
    private var foldRegions: [String: [CodeFoldRegion]] {
        Dictionary(uniqueKeysWithValues: appModel.graph.nodes.map { ($0.id, CodeFolder.regions(for: $0)) })
    }

    var body: some View {
        RealityView { content, attachments in
            content.add(ImmersiveBackdropFactory.makeSkyDome(palette: palette))

            let root = CodeGraphSceneBuilder.makeRootEntity(graph: appModel.graph, layout: appModel.layout, palette: palette)
            content.add(root)
            gestures.root = root

            let regions = foldRegions
            for node in appModel.graph.nodes {
                guard let nodeEntity = root.findEntity(named: node.id),
                      let card = attachments.entity(for: node.id) else { continue }
                nodeEntity.addChild(card)

                // 접힘 블록: 힌지 피벗(Y축 회전) 아래에 attachment를 둔다. 위치는 update에서 맞춘다.
                for region in regions[node.id] ?? [] {
                    let key = FoldKey(nodeID: node.id, regionID: region.id)
                    guard let block = attachments.entity(for: key.attachmentID) else { continue }
                    let pivot = Entity()
                    pivot.name = key.attachmentID
                    pivot.orientation = simd_quatf(angle: SceneStyle.foldAngle, axis: SIMD3<Float>(0, 1, 0))
                    pivot.addChild(block)
                    nodeEntity.addChild(pivot)
                }
            }

            if let anchor = root.findEntity(named: CodeGraphSceneBuilder.legendAnchorName),
               let legend = attachments.entity(for: Self.legendAttachmentID) {
                anchor.addChild(legend)
            }

            // 매 프레임: 엣지를 노드(또는 선택된 토큰) 위치에 동기화하고 흐름 펄스를 전진시킨다.
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                CodeGraphSceneBuilder.tick(
                    root: root,
                    deltaTime: Float(event.deltaTime),
                    endpointAnchors: appModel.activeEdgeAnchors
                )
            }
        } update: { content, _ in
            // 토큰 선택·브레이크포인트·시스템 외관이 바뀌면 배경과 엣지를 현재 상태로 다시 적용한다.
            if let dome = content.entities.first(where: { $0.name == ImmersiveBackdropFactory.entityName }) {
                ImmersiveBackdropFactory.apply(palette, to: dome)
            }
            guard let root = content.entities.first(where: { $0.name == CodeGraphSceneBuilder.rootEntityName }) else { return }
            CodeGraphSceneBuilder.applyEmphasis(
                root: root,
                highlighted: appModel.highlightedNodeIDs,
                containment: appModel.containmentNodeIDs,
                pausedNodeIDs: appModel.pausedNodeIDs,
                palette: palette
            )
            placeFoldedBlocks(under: root)
        } attachments: {
            ForEach(appModel.graph.nodes) { node in
                Attachment(id: node.id) {
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
                                foldHinges[FoldKey(nodeID: node.id, regionID: regionID)] = offset
                            }
                        }
                    )
                    .graphGestures(gestures)
                }

                let lines = CodeTokenizer.tokenize(node.codeSnippet ?? "")
                ForEach(CodeFolder.regions(in: lines)) { region in
                    let key = FoldKey(nodeID: node.id, regionID: region.id)
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
                                foldSizes[key] = size
                            }
                        )
                        .graphGestures(gestures)
                    }
                }
            }

            Attachment(id: Self.legendAttachmentID) {
                FlowLegendView()
            }
        }
        .graphGestures(gestures)
        .onImmersionChange { _, newValue in
            appModel.immersionAmount = newValue.amount ?? 0
        }
    }

    // MARK: - 접힘 블록 배치

    /// 힌지 피벗을 헤더 줄 왼쪽 아래 모서리에 놓고, attachment(중심 기준)를 피벗 로컬에서
    /// (+w/2, -h/2)만큼 옮겨 블록의 왼쪽 위 모서리가 힌지에 맞물리게 한다. 피벗이 Y축으로 돌아
    /// 있으므로 블록의 가로 방향은 카드 뒤(-Z)로 뻗는다.
    private func placeFoldedBlocks(under root: Entity) {
        for (key, hinge) in foldHinges {
            guard let pivot = root.findEntity(named: key.attachmentID) else { continue }
            pivot.position = hinge
            guard let block = pivot.children.first, let size = foldSizes[key] else { continue }
            block.position = SIMD3<Float>(
                Float(size.width / 2) / SceneStyle.pointsPerMeter,
                -Float(size.height / 2) / SceneStyle.pointsPerMeter,
                0
            )
        }
    }

    // MARK: - 카드 상태

    private func isDimmed(_ node: CodeNode) -> Bool {
        appModel.highlightedNodeIDs.map { !$0.contains(node.id) } ?? false
    }

    private func breakpointLines(of node: CodeNode) -> Set<Int> {
        Set(appModel.breakpoints.filter { $0.nodeID == node.id }.map(\.line))
    }
}

/// 노드 하나의 접힘 영역 하나를 가리키는 키. attachment ID와 피벗 엔티티 이름으로도 쓴다.
private struct FoldKey: Hashable {
    let nodeID: String
    let regionID: Int

    var attachmentID: String { "\(nodeID)#fold\(regionID)" }
}
