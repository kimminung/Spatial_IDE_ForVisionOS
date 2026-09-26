import Foundation

/// 코드 스니펫을 토큰 단위로 나눈다. 카드가 각 토큰을 개별 뷰로 그려,
/// 식별자(변수·타입·함수 이름)에만 응시 하이라이트와 탭을 붙일 수 있게 한다.
nonisolated enum CodeTokenKind: Equatable {
    case keyword
    case identifier
    case typeName      // 대문자로 시작하는 식별자
    case number
    case string
    case comment
    case punctuation
    case whitespace
}

nonisolated struct CodeToken: Identifiable, Equatable {
    let id: Int
    let text: String
    let kind: CodeTokenKind

    /// 응시 하이라이트/탭 대상이 되는 토큰인지.
    var isInteractive: Bool { kind == .identifier || kind == .typeName }
}

nonisolated struct CodeLine: Identifiable {
    let id: Int
    let tokens: [CodeToken]
}

/// 순수 문자열 처리라 액터 격리가 필요 없다(`CodeFolder`, 레이아웃 계산 등 비격리 문맥에서도 호출).
nonisolated enum CodeTokenizer {
    private static let keywords: Set<String> = [
        "let", "var", "func", "struct", "class", "enum", "extension", "protocol", "import",
        "static", "private", "public", "internal", "final", "override", "return", "if", "guard",
        "else", "switch", "case", "default", "for", "in", "while", "do", "try", "catch", "throw",
        "throws", "async", "await", "self", "Self", "nil", "true", "false", "some", "any", "where",
        "init", "inout", "typealias", "associatedtype", "mutating", "lazy", "weak", "unowned",
    ]

    /// 스니펫을 줄 단위로, 각 줄을 토큰 단위로 나눈다.
    static func tokenize(_ source: String) -> [CodeLine] {
        var nextID = 0
        return source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { lineIndex, line in
            let tokens = tokenizeLine(String(line), startingID: &nextID)
            return CodeLine(id: lineIndex, tokens: tokens)
        }
    }

    private static func tokenizeLine(_ line: String, startingID nextID: inout Int) -> [CodeToken] {
        var tokens: [CodeToken] = []
        let chars = Array(line)
        var index = 0

        func emit(_ text: String, _ kind: CodeTokenKind) {
            tokens.append(CodeToken(id: nextID, text: text, kind: kind))
            nextID += 1
        }

        while index < chars.count {
            let char = chars[index]

            // 주석: 줄 끝까지
            if char == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                emit(String(chars[index...]), .comment)
                break
            }

            // 문자열 리터럴
            if char == "\"" {
                var end = index + 1
                while end < chars.count, chars[end] != "\"" { end += 1 }
                end = min(end + 1, chars.count)
                emit(String(chars[index..<end]), .string)
                index = end
                continue
            }

            // 공백
            if char.isWhitespace {
                var end = index
                while end < chars.count, chars[end].isWhitespace { end += 1 }
                emit(String(chars[index..<end]), .whitespace)
                index = end
                continue
            }

            // 식별자 / 키워드
            if char.isLetter || char == "_" {
                var end = index
                while end < chars.count, chars[end].isLetter || chars[end].isNumber || chars[end] == "_" { end += 1 }
                let word = String(chars[index..<end])
                if keywords.contains(word) {
                    emit(word, .keyword)
                } else if word.first?.isUppercase == true {
                    emit(word, .typeName)
                } else {
                    emit(word, .identifier)
                }
                index = end
                continue
            }

            // 숫자
            if char.isNumber {
                var end = index
                while end < chars.count, chars[end].isNumber || chars[end] == "." { end += 1 }
                emit(String(chars[index..<end]), .number)
                index = end
                continue
            }

            // 그 외 한 글자 구두점
            emit(String(char), .punctuation)
            index += 1
        }

        return tokens
    }
}
