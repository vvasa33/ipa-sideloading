import Foundation

struct LyricLine: Identifiable, Equatable, Codable {
    var id: Int
    var timeMS: Int
    var text: String
}

enum LRCParser {
    static func parse(_ raw: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{2,3}))?\]"#
        ) else {
            return []
        }
        var collected: [(Int, String)] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, range: range)
            guard let last = matches.last, let lastRange = Range(last.range, in: line) else { continue }
            let text = line[lastRange.upperBound...].trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: line),
                    let secondRange = Range(match.range(at: 2), in: line),
                    let minutes = Int(line[minuteRange]),
                    let seconds = Int(line[secondRange])
                else { continue }
                let fraction = milliseconds(in: line, match: match)
                collected.append((minutes * 60_000 + seconds * 1000 + fraction, text))
            }
        }
        return collected
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, timeMS: $0.element.0, text: $0.element.1) }
    }

    private static func milliseconds(in line: String, match: NSTextCheckingResult) -> Int {
        let fractionRange = match.range(at: 3)
        guard fractionRange.location != NSNotFound, let range = Range(fractionRange, in: line) else {
            return 0
        }
        let digits = String(line[range])
        let value = Int(digits) ?? 0
        return digits.count >= 3 ? value : value * 10
    }
}
