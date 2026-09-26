import Foundation

/// 앱의 `CodeGraph` JSON 스키마(v2)와 1:1로 대응하는 출력 모델.
/// 앱 쪽 디코더는 `decodeIfPresent`를 쓰므로 v1(file/line/symbolRefs 없음) JSON도 그대로 읽힌다.
struct IndexedNode: Codable {
    let id: String
    let name: String
    let kind: String            // module | type | function | variable
    let parentID: String?
    let codeSnippet: String
    let breakpointLines: [Int]
    /// 소스 루트 기준 상대 경로.
    let file: String?
    /// 선언이 시작하는 줄(1부터).
    let line: Int?
    /// 이 노드의 스니펫 안에서 쓰인 식별자 → 그것이 가리키는 노드 ID.
    /// 앱은 토큰을 선택했을 때 문자열 일치 대신 이 표로 선언·참조 노드를 찾는다.
    let symbolRefs: [String: String]
}

struct IndexedEdge: Codable, Hashable {
    let from: String
    let to: String
    let kind: String            // owns | calls | throwsError | terminates
}

struct IndexedGraph: Codable {
    let schemaVersion: Int
    let module: String
    let generatedAt: String
    let nodes: [IndexedNode]
    let edges: [IndexedEdge]
}
