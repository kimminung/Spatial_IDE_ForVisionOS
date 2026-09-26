import Foundation
import OSLog

/// 앱 번들의 그래프 JSON을 로드한다.
///
/// 우선순위:
/// 1. `CodeSpaceGraph.json` — `Tools/CodeSpaceIndexer`가 실제 소스 트리를 SwiftSyntax로 인덱싱해 만든 v2 그래프
///    (파일·줄·심볼 참조표 포함). 재생성: `swift run codespace-indexer <소스 루트> --module CodeSpace -o Resources/CodeSpaceGraph.json`
/// 2. `SampleGraph.json` — 손으로 쓴 v1 더미 그래프
/// 3. `CodeGraph.sample` — Swift 코드에 박힌 최후의 폴백
enum GraphLoader {
    private static let logger = Logger(subsystem: "CodeSpace", category: "GraphLoader")

    static let indexedResourceName = "CodeSpaceGraph"
    static let sampleResourceName = "SampleGraph"

    static func loadBundledGraph() -> CodeGraph {
        for name in [indexedResourceName, sampleResourceName] {
            if let graph = load(resourceNamed: name) { return graph }
        }
        logger.error("번들 그래프를 하나도 읽지 못했습니다. CodeGraph.sample로 대체합니다.")
        return .sample
    }

    private static func load(resourceNamed name: String) -> CodeGraph? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            logger.notice("\(name).json이 번들에 없습니다.")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let graph = try parse(data: data)
            logger.info("\(name).json 로드 성공: 노드 \(graph.nodes.count)개, 엣지 \(graph.edges.count)개")
            return graph
        } catch {
            logger.error("\(name).json 로드/파싱 실패: \(error.localizedDescription)")
            return nil
        }
    }

    /// JSON 데이터를 `CodeGraph`로 디코딩한다.
    static func parse(data: Data) throws -> CodeGraph {
        try JSONDecoder().decode(CodeGraph.self, from: data)
    }
}
