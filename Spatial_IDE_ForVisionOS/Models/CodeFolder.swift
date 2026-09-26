import Foundation

/// 카드 평면에서 떼어 내어 Z축으로 접어 보여줄 코드 블록 한 덩어리.
///
/// 헤더 줄(`} catch {`, `guard … else {`)은 카드에 그대로 남아 "힌지" 역할을 하고,
/// 그 아래 본문 줄들(`bodyLines`)만 별도 평면으로 옮겨 카드 뒤(-Z)로 꺾어 배치한다.
struct CodeFoldRegion: Identifiable, Hashable {
    enum Kind: Hashable {
        /// `do { } catch { … }`의 catch 본문 — 오류가 잡혀 처리되는 경로.
        case catchBlock
        /// `guard … else { … }`의 else 본문 — 조기 탈출(return/throw/fatalError) 경로.
        case guardElse
    }

    /// 헤더 줄 번호를 그대로 식별자로 쓴다(스니펫 안에서 유일).
    var id: Int { headerLine }
    let kind: Kind
    let headerLine: Int
    /// 접혀 들어가는 본문 줄 범위. 헤더 다음 줄부터 닫는 중괄호 줄 **직전**까지.
    let bodyLines: Range<Int>

    var lineCount: Int { bodyLines.count }
}

/// 토큰화된 코드에서 접힘 영역을 찾는다.
///
/// 1순위 후보(예외·탈출 경로)만 다룬다: `catch` 블록과 `guard … else` 본문.
/// 중괄호 균형으로 본문 끝을 찾으며, 문자열·주석 안의 중괄호는 토크나이저가 별도 토큰으로
/// 묶어 두므로 세지 않는다. 중첩된 영역은 가장 바깥 것만 접는다.
enum CodeFolder {

    static func regions(for node: CodeNode) -> [CodeFoldRegion] {
        regions(in: CodeTokenizer.tokenize(node.codeSnippet ?? ""))
    }

    static func regions(in lines: [CodeLine]) -> [CodeFoldRegion] {
        var result: [CodeFoldRegion] = []
        var index = 0
        while index < lines.count {
            guard let kind = headerKind(of: lines[index]),
                  let closing = closingLine(openedAt: index, in: lines) else {
                index += 1
                continue
            }
            let body = (index + 1)..<closing
            if !body.isEmpty {
                result.append(CodeFoldRegion(kind: kind, headerLine: index, bodyLines: body))
            }
            // 닫는 줄이 곧 다음 헤더(`} catch {`)일 수 있으므로 그 줄부터 다시 검사한다.
            index = max(closing, index + 1)
        }
        return result
    }

    /// 접힘 영역들의 본문에 속하는 모든 줄 번호.
    static func foldedLineIDs(of regions: [CodeFoldRegion]) -> Set<Int> {
        regions.reduce(into: Set<Int>()) { $0.formUnion($1.bodyLines) }
    }

    /// 접힌 평면에 그릴 본문 줄. 헤더 줄의 들여쓰기만큼 앞 공백을 걷어내 평면이 헤더 기준
    /// 한 단계 들여쓰기에서 시작하도록 한다.
    static func bodyLines(of region: CodeFoldRegion, in lines: [CodeLine]) -> [CodeLine] {
        let headerIndent = leadingWhitespaceCount(of: lines[region.headerLine])
        return region.bodyLines.compactMap { lineIndex in
            guard lineIndex < lines.count else { return nil }
            return dedent(lines[lineIndex], by: headerIndent)
        }
    }

    // MARK: - 내부

    private static func headerKind(of line: CodeLine) -> CodeFoldRegion.Kind? {
        let significant = line.tokens.filter { $0.kind != .whitespace && $0.kind != .comment }
        guard significant.last?.text == "{" else { return nil }
        let keywords = Set(significant.filter { $0.kind == .keyword }.map(\.text))
        if keywords.contains("catch") { return .catchBlock }
        if keywords.contains("guard") && keywords.contains("else") { return .guardElse }
        return nil
    }

    /// 헤더 줄 끝의 `{`와 짝이 되는 `}`가 있는 줄 번호. 못 찾으면 nil.
    private static func closingLine(openedAt header: Int, in lines: [CodeLine]) -> Int? {
        var depth = 1
        for lineIndex in (header + 1)..<lines.count {
            for token in lines[lineIndex].tokens where token.kind == .punctuation {
                if token.text == "{" { depth += 1 }
                if token.text == "}" {
                    depth -= 1
                    if depth == 0 { return lineIndex }
                }
            }
        }
        return nil
    }

    private static func leadingWhitespaceCount(of line: CodeLine) -> Int {
        guard let first = line.tokens.first, first.kind == .whitespace else { return 0 }
        return first.text.count
    }

    private static func dedent(_ line: CodeLine, by count: Int) -> CodeLine {
        guard count > 0, let first = line.tokens.first, first.kind == .whitespace else { return line }
        let trimmed = String(first.text.dropFirst(count))
        var tokens = Array(line.tokens.dropFirst())
        if !trimmed.isEmpty {
            tokens.insert(CodeToken(id: first.id, text: trimmed, kind: .whitespace), at: 0)
        }
        return CodeLine(id: line.id, tokens: tokens)
    }
}
