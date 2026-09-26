// swift-tools-version: 5.10
import PackageDescription

/// CodeSpace 빌드 타임 인덱서.
///
/// Swift 소스 트리를 SwiftSyntax로 파싱해 모듈/타입/함수/변수 노드와
/// owns/calls/throwsError/terminates 엣지, 노드별 심볼 참조표를 JSON으로 출력한다.
/// 앱은 이 JSON(`CodeSpaceGraph.json`)을 번들에서 읽는다.
///
///     swift run codespace-indexer <소스 루트> --module CodeSpace -o <출력.json>
let package = Package(
    name: "CodeSpaceIndexer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "codespace-indexer",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/CodeSpaceIndexer"
        ),
    ]
)
