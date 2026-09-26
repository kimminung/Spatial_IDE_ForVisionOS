import Foundation

extension CodeGraph {
    /// Phase 1 검증용 더미 그래프.
    /// CodeSpace 앱 자체의 구조를 축소해 흉내낸 것으로, 깊이 0(모듈) ~ 4(하위 함수)까지 형성된다.
    /// Phase 2부터는 각 노드에 더미 코드 스니펫도 함께 실어, 탭했을 때 코드 패널에 표시한다.
    static let sample = CodeGraph(
        nodes: [
            // depth 0
            CodeNode(
                id: "CodeSpace", name: "CodeSpace", kind: .module, parentID: nil,
                codeSnippet: """
                @main
                struct CodeSpaceApp: App {
                    var body: some Scene {
                        WindowGroup(id: "Launcher") { LauncherView() }
                        ImmersiveSpace(id: "CodeSpaceImmersiveSpace") {
                            CodeSpaceImmersiveView()
                        }
                    }
                }
                """
            ),

            // depth 1 — 모듈이 소유하는 타입들
            CodeNode(
                id: "AppModel", name: "AppModel", kind: .type, parentID: "CodeSpace",
                codeSnippet: """
                @Observable
                final class AppModel {
                    var graph: CodeGraph = .sample
                    var immersionStyle: ImmersionStyle = .mixed
                    var selectedToken: TokenSelection?
                }
                """
            ),
            CodeNode(
                id: "GraphLoader", name: "GraphLoader", kind: .type, parentID: "CodeSpace",
                codeSnippet: """
                enum GraphLoader {
                    static func loadBundledSample() -> CodeGraph {
                        // JSON 리소스를 읽어 CodeGraph로 디코딩한다.
                    }
                }
                """
            ),
            CodeNode(
                id: "SpatialLayout", name: "SpatialLayout", kind: .type, parentID: "CodeSpace",
                codeSnippet: """
                struct SpatialLayout {
                    var origin: SIMD3<Float> = [0, 1.3, -1.5]
                    var depthSpacing: Float = 0.5

                    func positions(for graph: CodeGraph)
                        -> [String: SIMD3<Float>] { ... }
                }
                """
            ),
            CodeNode(
                id: "SceneBuilder", name: "CodeGraphSceneBuilder", kind: .type, parentID: "CodeSpace",
                codeSnippet: """
                enum CodeGraphSceneBuilder {
                    static func makeRootEntity(
                        graph: CodeGraph,
                        layout: SpatialLayout
                    ) -> Entity { ... }
                }
                """
            ),

            // depth 2 — 타입이 소유하는 멤버
            CodeNode(
                id: "AppModel.graph", name: "graph", kind: .variable, parentID: "AppModel",
                codeSnippet: "var graph: CodeGraph = .sample"
            ),
            CodeNode(
                id: "AppModel.immersionStyle", name: "immersionStyle", kind: .variable, parentID: "AppModel",
                codeSnippet: "var immersionStyle: ImmersionStyle = .mixed"
            ),
            CodeNode(
                id: "GraphLoader.load", name: "load()", kind: .function, parentID: "GraphLoader",
                codeSnippet: """
                static func load() -> CodeGraph {
                    do {
                        let data = try loadBundledData()
                        return try parse(data: data)
                    } catch {
                        return .sample
                    }
                }
                """
            ),
            CodeNode(
                id: "SpatialLayout.positions", name: "positions(for:)", kind: .function, parentID: "SpatialLayout",
                codeSnippet: """
                func positions(for graph: CodeGraph) -> [String: SIMD3<Float>] {
                    let depths = graph.callDepths()
                    // 깊이별로 X/Y/Z 좌표를 계산한다.
                }
                """,
                breakpointLines: [1]
            ),
            CodeNode(
                id: "SceneBuilder.makeRoot", name: "makeRootEntity()", kind: .function, parentID: "SceneBuilder",
                codeSnippet: """
                static func makeRootEntity(
                    graph: CodeGraph, layout: SpatialLayout
                ) -> Entity {
                    // 노드 + 엣지 엔티티를 생성해 루트에 매단다.
                }
                """
            ),

            // depth 3 — 함수가 호출하는 함수
            CodeNode(
                id: "GraphLoader.parse", name: "parse(data:)", kind: .function, parentID: "GraphLoader",
                codeSnippet: """
                static func parse(data: Data) throws -> CodeGraph {
                    let graph = try JSONDecoder().decode(CodeGraph.self, from: data)
                    try validate(graph)
                    return graph
                }
                """
            ),
            CodeNode(
                id: "CodeGraph.callDepths", name: "callDepths()", kind: .function, parentID: "CodeSpace",
                codeSnippet: """
                func callDepths() -> [String: Int] {
                    // 루트 노드에서 BFS로 각 노드의 호출 깊이를 계산한다.
                }
                """
            ),
            CodeNode(
                id: "NodeEntityFactory.makeEntity", name: "makeEntity(for:)", kind: .function, parentID: "CodeSpace",
                codeSnippet: """
                static func makeEntity(for node: CodeNode) -> ModelEntity {
                    // kind별 메시/머티리얼 + Collision/InputTarget/Hover 컴포넌트 부여.
                }
                """
            ),

            // depth 4
            CodeNode(
                id: "GraphLoader.validate", name: "validate(_:)", kind: .function, parentID: "GraphLoader",
                codeSnippet: """
                static func validate(_ graph: CodeGraph) throws {
                    guard !graph.nodes.isEmpty else {
                        fatalError("그래프에 노드가 없습니다")
                    }
                    if hasDuplicateIDs(graph) { throw GraphError.duplicateID }
                }
                """
            ),
        ],
        edges: [
            // 소유 관계 (모듈 → 타입): 구조일 뿐 실행 흐름이 아니다.
            CodeEdge(from: "CodeSpace", to: "AppModel", kind: .owns),
            CodeEdge(from: "CodeSpace", to: "GraphLoader", kind: .owns),
            CodeEdge(from: "CodeSpace", to: "SpatialLayout", kind: .owns),
            CodeEdge(from: "CodeSpace", to: "SceneBuilder", kind: .owns),

            // 소유 관계 (타입 → 멤버)
            CodeEdge(from: "AppModel", to: "AppModel.graph", kind: .owns),
            CodeEdge(from: "AppModel", to: "AppModel.immersionStyle", kind: .owns),
            CodeEdge(from: "GraphLoader", to: "GraphLoader.load", kind: .owns),
            CodeEdge(from: "SpatialLayout", to: "SpatialLayout.positions", kind: .owns),
            CodeEdge(from: "SceneBuilder", to: "SceneBuilder.makeRoot", kind: .owns),

            // 호출 관계 (함수 → 함수)
            CodeEdge(from: "GraphLoader.load", to: "GraphLoader.parse", kind: .throwsError),      // parse의 오류가 load로 전파
            CodeEdge(from: "GraphLoader.parse", to: "GraphLoader.validate", kind: .terminates),   // validate는 fatalError로 끝날 수 있음
            CodeEdge(from: "SpatialLayout.positions", to: "CodeGraph.callDepths", kind: .calls),
            CodeEdge(from: "SceneBuilder.makeRoot", to: "NodeEntityFactory.makeEntity", kind: .calls),
            CodeEdge(from: "SceneBuilder.makeRoot", to: "SpatialLayout.positions", kind: .calls),
            CodeEdge(from: "GraphLoader.load", to: "AppModel.graph", kind: .calls),
        ]
    )
}
