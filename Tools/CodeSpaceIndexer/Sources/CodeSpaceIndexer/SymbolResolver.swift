import Foundation

/// 모든 파일의 선언을 모아 이름 참조를 노드 ID로 해석하고, 엣지와 심볼 참조표를 만든다.
///
/// 해석 규칙(정확도 순):
/// 1. `Type.foo(...)` — base가 모듈 안의 타입 이름이면 그 타입의 멤버에서 찾는다.
/// 2. `bar.foo(...)` — base가 같은 타입의 프로퍼티이고 타입 주석이 있으면 그 타입의 멤버에서 찾는다.
/// 3. `foo(...)` / `self.foo(...)` — 같은 타입(및 확장) 멤버 → 모듈 수준 함수.
/// 4. 그래도 없으면 모듈 전체에서 이름이 **유일**할 때만 채택한다. 여러 개면 오탐을 피해 버린다.
///
/// 프로토콜 요구사항은 구체 구현이 있으면 후보에서 제외한다. 완전한 타입 기반 해석은 IndexStoreDB(USR) 연동으로 대체 예정.
struct SymbolResolver {
    let moduleID: String
    let declarations: [Declaration]

    private let byID: [String: Declaration]
    private let functionsByBaseName: [String: [Declaration]]
    private let variablesByName: [String: [Declaration]]
    private let typesByName: [String: Declaration]

    init(moduleID: String, declarations: [Declaration]) {
        self.moduleID = moduleID
        self.declarations = declarations
        byID = Dictionary(uniqueKeysWithValues: declarations.map { ($0.id, $0) })

        var functions: [String: [Declaration]] = [:]
        var variables: [String: [Declaration]] = [:]
        var types: [String: Declaration] = [:]
        for decl in declarations {
            switch decl.kind {
            case .function:
                functions[Self.baseName(decl.name), default: []].append(decl)
            case .variable:
                variables[decl.name, default: []].append(decl)
            case .type:
                types[decl.name] = decl
            case .module:
                break
            }
        }
        functionsByBaseName = functions
        variablesByName = variables
        typesByName = types
    }

    static func baseName(_ name: String) -> String {
        name.split(separator: "(").first.map(String.init) ?? name
    }

    // MARK: - 출력

    func buildGraph(fileCount: Int) -> IndexedGraph {
        var nodes: [IndexedNode] = []
        var edges: Set<IndexedEdge> = []
        /// (from, to) → 우선순위가 가장 높은 종류. terminates > throwsError > calls.
        var callKinds: [String: String] = [:]

        let typeCount = declarations.filter { $0.kind == .type }.count
        let functionCount = declarations.filter { $0.kind == .function }.count
        nodes.append(IndexedNode(
            id: moduleID, name: moduleID, kind: "module", parentID: nil,
            codeSnippet: "// 모듈 \(moduleID)\n// 파일 \(fileCount)개 · 타입 \(typeCount)개 · 함수 \(functionCount)개",
            breakpointLines: [], file: nil, line: nil, symbolRefs: [:]
        ))

        for decl in declarations {
            var symbolRefs: [String: String] = [:]
            for reference in decl.references {
                guard let target = resolve(reference, from: decl) else { continue }
                symbolRefs[reference.name] = target.id

                // 엣지는 함수 호출에만 만든다. 타입·값 참조는 심볼표로만 남긴다.
                guard reference.form == .call, target.kind == .function, target.id != decl.id else { continue }
                let key = "\(decl.id)->\(target.id)"
                let kind: String
                if target.isTerminating {
                    kind = "terminates"
                } else if target.isThrowing && reference.insideTry {
                    kind = "throwsError"
                } else {
                    kind = "calls"
                }
                callKinds[key] = Self.stronger(callKinds[key], kind)
            }
            // 선언 자신의 이름도 표에 넣어, 선언부 토큰을 선택하면 곧 자기 노드로 해석되게 한다.
            symbolRefs[Self.baseName(decl.name)] = decl.id

            nodes.append(IndexedNode(
                id: decl.id, name: decl.name, kind: decl.kind.rawValue, parentID: decl.parentID,
                codeSnippet: decl.snippet, breakpointLines: [],
                file: decl.file, line: decl.line, symbolRefs: symbolRefs
            ))
            if let parentID = decl.parentID {
                edges.insert(IndexedEdge(from: parentID, to: decl.id, kind: "owns"))
            }
        }

        for (key, kind) in callKinds {
            let parts = key.components(separatedBy: "->")
            edges.insert(IndexedEdge(from: parts[0], to: parts[1], kind: kind))
        }

        let formatter = ISO8601DateFormatter()
        return IndexedGraph(
            schemaVersion: 2,
            module: moduleID,
            generatedAt: formatter.string(from: Date()),
            nodes: nodes.sorted { $0.id < $1.id },
            edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
        )
    }

    private static func stronger(_ current: String?, _ new: String) -> String {
        let rank = ["calls": 0, "throwsError": 1, "terminates": 2]
        guard let current else { return new }
        return (rank[new] ?? 0) > (rank[current] ?? 0) ? new : current
    }

    // MARK: - 해석

    func resolve(_ reference: Reference, from context: Declaration) -> Declaration? {
        switch reference.form {
        case .type:
            return typesByName[reference.name]
        case .call:
            return resolveMember(named: reference.name, base: reference.base, from: context, in: functionsByBaseName)
                ?? initializer(ofTypeNamed: reference.name)
        case .value:
            return resolveMember(named: reference.name, base: reference.base, from: context, in: variablesByName)
                ?? resolveMember(named: reference.name, base: reference.base, from: context, in: functionsByBaseName)
        }
    }

    /// `Foo(...)` 생성 호출 → `Foo.init(...)`가 있으면 그것, 없으면 타입 자체.
    private func initializer(ofTypeNamed name: String) -> Declaration? {
        guard let type = typesByName[name] else { return nil }
        return functionsByBaseName["init"]?.first { $0.parentID == type.id } ?? type
    }

    private func resolveMember(named name: String, base: String?, from context: Declaration, in table: [String: [Declaration]]) -> Declaration? {
        guard let candidates = table[name], !candidates.isEmpty else { return nil }
        let concrete = candidates.filter { !$0.isProtocolRequirement }
        let pool = concrete.isEmpty ? candidates : concrete

        // 1. base가 타입 이름
        if let base, let type = typesByName[base] {
            if let hit = pool.first(where: { $0.parentID == type.id }) { return hit }
        }
        // 2. base가 같은 타입의 프로퍼티(타입 주석 있음)
        if let base, let scopeTypeID = context.enclosingTypeID,
           let property = variablesByName[base]?.first(where: { $0.parentID == scopeTypeID }),
           let annotation = property.typeAnnotation.map(Self.baseTypeName),
           let type = typesByName[annotation] {
            if let hit = pool.first(where: { $0.parentID == type.id }) { return hit }
        }
        // 3. base 없음 → 같은 타입 멤버 → 모듈 수준
        if base == nil {
            if let scopeTypeID = context.enclosingTypeID, let hit = pool.first(where: { $0.parentID == scopeTypeID }) {
                return hit
            }
            if let hit = pool.first(where: { $0.parentID == moduleID }) { return hit }
        }
        // 4. 모듈 전체에서 유일할 때만. 단, base 없는 **값** 참조(`graph`, `data`)는 지역 변수일 가능성이
        //    높아 여기서 멈춘다 — 함수 호출과 `x.member` 접근만 유일성 폴백을 허용한다.
        if base == nil, table[name]?.first?.kind == .variable { return nil }
        return pool.count == 1 ? pool[0] : nil
    }

    /// `[Foo]`, `Foo?`, `Set<Foo>` 같은 주석에서 핵심 타입 이름 하나를 뽑는다(간이).
    private static func baseTypeName(_ annotation: String) -> String {
        var text = annotation
        for token in ["[", "]", "?", "!", "Set<", "Array<", ">"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        return text.split(separator: ":").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? text
    }
}
