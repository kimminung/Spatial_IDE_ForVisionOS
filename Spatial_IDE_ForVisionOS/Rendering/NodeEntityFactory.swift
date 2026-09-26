import RealityKit

/// `CodeNode`를 위한 RealityKit 엔티티를 생성한다.
///
/// 노드의 시각적 표현은 코드 카드(`CodePanelView`, SwiftUI attachment) 하나뿐이다. 이 엔티티는
/// 카드가 매달리는 위치 기준점이자 엣지의 끝점이며, 자체 메시·충돌 영역·조작 컴포넌트를 갖지 않는다.
/// 응시 하이라이트와 탭은 카드 안의 토큰(SwiftUI) 단위로 일어난다.
@MainActor
enum NodeEntityFactory {
    static func makeEntity(for node: CodeNode) -> Entity {
        let entity = Entity()
        entity.name = node.id
        entity.components.set(CodeNodeInfoComponent(nodeID: node.id, kind: node.kind))
        return entity
    }
}

/// 노드 엔티티에 붙는 식별 정보. 씬 순회 시 `entity.name` 파싱 없이 바로 조회한다.
struct CodeNodeInfoComponent: Component {
    let nodeID: String
    let kind: CodeNodeKind
}
