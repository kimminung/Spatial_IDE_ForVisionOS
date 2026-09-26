import SwiftUI

/// 심볼 검색 패널. 그래프 위쪽 앵커에 attachment로 붙는다.
///
/// 수백 개 노드가 칩 안에 접혀 있으면 눈으로 찾을 수 없으므로, 이름으로 찾아 그 자리까지 펼치고
/// (`AppModel.focus(on:)`) 그 노드의 쓰임새 흐름을 곧바로 강조한다.
struct SearchPanelView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    private var results: [CodeNode] { appModel.searchNodes(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("심볼 검색 (타입, 함수, 변수)", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(width: 280)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                }
                Text("카드 \(appModel.cardCount)/\(appModel.cardBudget)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !results.isEmpty {
                Divider()
                ForEach(results) { node in
                    Button {
                        appModel.focus(on: node.id)
                        query = ""
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: node.kind.symbolName)
                                .foregroundStyle(node.kind.color(for: colorScheme))
                                .frame(width: 16)
                            Text(node.name)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            Text(container(of: node))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                }
            }
        }
        .padding(12)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 16))
        .fixedSize()
    }

    /// `CodeSpace.AppModel.graph` → `AppModel`
    private func container(of node: CodeNode) -> String {
        guard let parentID = node.parentID, let parent = appModel.index.nodesByID[parentID] else { return "" }
        return parent.name
    }
}
