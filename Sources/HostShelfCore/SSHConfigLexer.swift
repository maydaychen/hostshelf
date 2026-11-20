import Foundation

/// Configuration quoting is separate from the shell quoting inside ProxyCommand.
enum SSHConfigLexer {
    struct Line {
        var keyword: String
        var arguments: [String]
        var value: String
    }

    enum Failure: Error {
        case unterminatedQuote
    }

    static func parse(_ source: String) throws -> Line? {
        let characters = Array(source)
        var position = 0
        while position < characters.count, characters[position].isWhitespace { position += 1 }
        guard position < characters.count, characters[position] != "#" else { return nil }
        let start = position
        while position < characters.count,
              !characters[position].isWhitespace, characters[position] != "=" { position += 1 }
        let keyword = String(characters[start..<position]).lowercased()
        while position < characters.count, characters[position].isWhitespace { position += 1 }
        if position < characters.count, characters[position] == "=" { position += 1 }
        while position < characters.count, characters[position].isWhitespace { position += 1 }
        let valueStart = position
        var tokens: [String] = []
        var token = ""
        var tokenStarted = false
        var quote: Character?
        var commentStart = characters.count

        while position < characters.count {
            let character = characters[position]
            if character == "\\" {
                if position + 1 < characters.count {
                    let next = characters[position + 1]
                    if next == "\"" || next == "'" || next == "\\" || (quote == nil && next == " ") {
                        token.append(next)
                        tokenStarted = true
                        position += 2
                        continue
                    }
                }
                token.append(character)
                tokenStarted = true
            } else if let activeQuote = quote, character == activeQuote {
                quote = nil
                tokenStarted = true
            } else if quote == nil, character == "\"" || character == "'" {
                quote = character
                tokenStarted = true
            } else if character == "#", quote == nil, !tokenStarted {
                commentStart = position
                break
            } else if character.isWhitespace, quote == nil {
                if tokenStarted {
                    tokens.append(token)
                    token = ""
                    tokenStarted = false
                }
            } else {
                token.append(character)
                tokenStarted = true
            }
            position += 1
        }
        guard quote == nil else { throw Failure.unterminatedQuote }
        if tokenStarted { tokens.append(token) }
        let value = String(characters[valueStart..<commentStart]).trimmingCharacters(in: .whitespaces)
        return Line(keyword: keyword, arguments: tokens, value: value)
    }
}
