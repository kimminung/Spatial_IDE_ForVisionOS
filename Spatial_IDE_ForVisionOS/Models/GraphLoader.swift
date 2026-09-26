import Foundation
import OSLog

/// Phase 4: 하드코딩된 `CodeGraph.sample` 대신, 앱 번들에 포함된 JSON 리소스에서
/// 실제 데이터 파이프라인을 흉내내 그래프를 로드한다.
///
/// PRD의 데이터 파이프라인 문서에 따르면 최종적으로는 SwiftSyntax가 만든 AST를 JSON으로
/// 직렬화해 이 경로로 흘려보낼 예정이다. 지금은 `SampleGraph.json`이 그 자리를 대신한다.
enum GraphLoader {
    private static let logger = Logger(subsystem: "CodeSpace", category: "GraphLoader")

    /// 번들에 포함된 `SampleGraph.json`을 읽어 `CodeGraph`로 디코딩한다.
    /// 리소스를 찾지 못하거나 디코딩에 실패하면, 앱이 빈 공간으로 뜨는 것을 막기 위해
    /// Swift 코드로 정의된 `CodeGraph.sample`로 안전하게 대체한다.
    static func loadBundledSample() -> CodeGraph {
        guard let url = Bundle.main.url(forResource: "SampleGraph", withExtension: "json") else {
            logger.error("SampleGraph.json을 번들에서 찾지 못했습니다. CodeGraph.sample로 대체합니다.")
            return .sample
        }

        do {
            let data = try Data(contentsOf: url)
            let graph = try parse(data: data)
            logger.info("SampleGraph.json 로드 성공: 노드 \(graph.nodes.count)개, 엣지 \(graph.edges.count)개")
            return graph
        } catch {
            logger.error("SampleGraph.json 로드/파싱 실패: \(error.localizedDescription). CodeGraph.sample로 대체합니다.")
            return .sample
        }
    }

    /// JSON 데이터를 `CodeGraph`로 디코딩한다.
    static func parse(data: Data) throws -> CodeGraph {
        try JSONDecoder().decode(CodeGraph.self, from: data)
    }
}
