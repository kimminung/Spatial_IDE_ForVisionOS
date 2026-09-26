import Foundation
import SwiftParser
import SwiftSyntax

// codespace-indexer <소스 루트> [--module 이름] [-o 출력.json] [--exclude 경로조각 ...]

var arguments = Array(CommandLine.arguments.dropFirst())
var sourceRoot: String?
var moduleName: String?
var outputPath: String?
var excludes: [String] = ["/.build/", "/Tools/", "/DerivedData/", "Tests/"]

while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--module": moduleName = arguments.isEmpty ? nil : arguments.removeFirst()
    case "-o", "--output": outputPath = arguments.isEmpty ? nil : arguments.removeFirst()
    case "--exclude": if !arguments.isEmpty { excludes.append(arguments.removeFirst()) }
    case "-h", "--help":
        print("usage: codespace-indexer <source-root> [--module NAME] [-o OUTPUT.json] [--exclude FRAGMENT]…")
        exit(0)
    default: sourceRoot = argument
    }
}

guard let sourceRoot else {
    FileHandle.standardError.write(Data("소스 루트 경로가 필요합니다.\n".utf8))
    exit(1)
}

let rootURL = URL(fileURLWithPath: sourceRoot).standardizedFileURL
let moduleID = moduleName ?? rootURL.lastPathComponent

// 1. Swift 파일 수집
var swiftFiles: [URL] = []
if let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil) {
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let path = url.path
        if excludes.contains(where: { path.contains($0) }) { continue }
        swiftFiles.append(url)
    }
}
swiftFiles.sort { $0.path < $1.path }

// 2. 파일별 선언·참조 수집
var declarations: [Declaration] = []
var extendedTypeNames: Set<String> = []
for url in swiftFiles {
    guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
    let tree = Parser.parse(source: source)
    let relative = String(url.path.dropFirst(rootURL.path.count + 1))
    let collector = DeclarationCollector(moduleID: moduleID, relativePath: relative, source: source, tree: tree)
    collector.walk(tree)
    declarations.append(contentsOf: collector.declarations)
    extendedTypeNames.formUnion(collector.extendedTypeNames)
}

// 3. 확장만 있고 선언은 다른 모듈에 있는 타입(예: `extension Color`)은 타입 노드를 만들어 준다.
let declaredTypeNames = Set(declarations.filter { $0.kind == .type }.map(\.name))
for name in extendedTypeNames.subtracting(declaredTypeNames).sorted() {
    let decl = Declaration(
        id: "\(moduleID).\(name)", name: name, kind: .type, parentID: moduleID,
        file: nil, line: nil, snippet: "extension \(name) {\n    // 다른 모듈의 타입에 대한 확장\n}"
    )
    declarations.append(decl)
}

// 4. 해석 및 출력
let resolver = SymbolResolver(moduleID: moduleID, declarations: declarations)
let graph = resolver.buildGraph(fileCount: swiftFiles.count)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try encoder.encode(graph)

if let outputPath {
    try data.write(to: URL(fileURLWithPath: outputPath))
} else {
    FileHandle.standardOutput.write(data)
}

let callEdges = graph.edges.filter { $0.kind != "owns" }.count
FileHandle.standardError.write(Data(
    "파일 \(swiftFiles.count)개 → 노드 \(graph.nodes.count)개, 엣지 \(graph.edges.count)개(호출 계열 \(callEdges)개)\n".utf8
))
