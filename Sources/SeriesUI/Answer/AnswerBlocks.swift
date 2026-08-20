import Foundation

/// The text passes every streamed answer in the series shares: splitting
/// markdown into blocks, rendering the inline markup of one block, and the
/// punctuation safety net behind a Chinese-language prompt.
///
/// Moved here from Gloss, where it was `Answer.blocks` and friends. Minute's
/// meeting assistant renders the same kind of text — short, structured,
/// arriving token by token — and wanted exactly the same rules.
public enum SeriesAnswer {
    /// One piece of an answer's structure. Models reliably emit headings,
    /// bullets, numbered steps and fenced code for exactly the kind of question
    /// these apps ask — "compare these synonyms", "what did they decide" — and
    /// inline-only parsing left every one of those markers on screen as literal
    /// `###` and `-` characters. In an app whose entire output is one block of
    /// prose, that was the most visible thing wrong with it.
    ///
    /// Five cases covers essentially everything that actually arrives; anything
    /// else falls through to a paragraph, which is what it looked like before.
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case bullet(depth: Int, text: String)
        case numbered(marker: String, depth: Int, text: String)
        case code(language: String?, text: String)
        case paragraph(String)
        case rule
    }

    /// Splits an answer into blocks. Pure, and run against text that is still
    /// arriving — so an unterminated code fence has to render as the code it
    /// is so far rather than swallowing the rest of the answer or waiting for
    /// a close that may be seconds away.
    public static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        var codeLanguage: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if code == nil {
                    flushParagraph()
                    let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = language.isEmpty ? nil : language
                    code = []
                } else {
                    blocks.append(.code(language: codeLanguage, text: code!.joined(separator: "\n")))
                    code = nil
                    codeLanguage = nil
                }
                continue
            }
            if code != nil {
                code!.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                continue
            }
            if let heading = headingBlock(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            let depth = listDepth(line)
            if let body = bulletBody(trimmed) {
                flushParagraph()
                blocks.append(.bullet(depth: depth, text: body))
                continue
            }
            if let (marker, body) = numberedBody(trimmed) {
                flushParagraph()
                blocks.append(.numbered(marker: marker, depth: depth, text: body))
                continue
            }
            paragraph.append(line)
        }

        // Whatever is still open belongs to the reader now: mid-stream, this is
        // most of the answer.
        if let code {
            blocks.append(.code(language: codeLanguage, text: code.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func headingBlock(_ trimmed: String) -> Block? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        // "#hashtag" is not a heading; "# Heading" is.
        guard rest.first == " " else { return nil }
        return .heading(
            level: hashes,
            text: rest.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func bulletBody(_ trimmed: String) -> String? {
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedBody(_ trimmed: String) -> (marker: String, body: String)? {
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (
            marker: String(digits) + String(rest.prefix(1)),
            body: String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        )
    }

    /// Two spaces of indent is one level, which is what the models emit.
    private static func listDepth(_ line: String) -> Int {
        let spaces = line.prefix { $0 == " " }.count
        return min(spaces / 2, 3)
    }

    /// Inline-only markdown keeps the streamed text's own line breaks while
    /// rendering bold/italic/code the models like to use.
    public static func markdown(_ text: String) -> AttributedString {
        let normalized = normalizePunctuation(text)
        return (try? AttributedString(
            markdown: normalized,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(normalized)
    }

    /// Safety net behind the prompt rule: models occasionally slip half-width
    /// marks into Chinese sentences. Convert a mark to full-width only when it
    /// touches a CJK character, so English words, numbers, URLs and code are
    /// never affected.
    public static func normalizePunctuation(_ text: String) -> String {
        let map: [Character: Character] = [
            ",": "，", ".": "。", ":": "：", ";": "；",
            "!": "！", "?": "？", "(": "（", ")": "）",
        ]
        func isCJK(_ character: Character) -> Bool {
            guard let scalar = character.unicodeScalars.first else { return false }
            let value = Int(scalar.value)
            return (0x4E00...0x9FFF).contains(value)   // CJK Unified
                || (0x3400...0x4DBF).contains(value)   // CJK Extension A
                || (0x3000...0x303F).contains(value)   // CJK punctuation
                || (0xFF01...0xFF60).contains(value)   // full-width forms
        }
        var characters = Array(text)
        for index in characters.indices {
            guard let fullWidth = map[characters[index]] else { continue }
            let previousIsCJK = index > 0 && isCJK(characters[index - 1])
            let nextIsCJK = index + 1 < characters.count && isCJK(characters[index + 1])
            if previousIsCJK || nextIsCJK {
                characters[index] = fullWidth
            }
        }
        return String(characters)
    }
}
