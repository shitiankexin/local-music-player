import Foundation

struct LyricLine: Hashable, Identifiable {
    var id: Int { index }
    let index: Int
    let time: TimeInterval
    let text: String
}

struct LRCFile {
    let lines: [LyricLine]
    let embeddedOffset: TimeInterval

    /// A positive manual offset means lyrics are displayed LATER.
    func activeIndex(at playbackTime: TimeInterval, manualOffset: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        let timestamp = playbackTime - embeddedOffset - manualOffset
        var left = 0
        var right = lines.count
        while left < right {
            let mid = (left + right) / 2
            if lines[mid].time <= timestamp { left = mid + 1 }
            else { right = mid }
        }
        return left > 0 ? left - 1 : nil
    }

    static func load(from url: URL) -> LRCFile? {
        guard let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16) else { return nil }
        return parse(string)
    }

    private static let timeRegex = NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
    private static let offsetRegex = NSRegularExpression(pattern: #"(?i)\[offset:\s*([+-]?\d+)\]"#)

    static func parse(_ source: String) -> LRCFile {
        var result: [(time: Double, text: String)] = []
        var offset: Double = 0

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = offsetRegex.firstMatch(in: line, range: range),
               let r = Range(match.range(at: 1), in: line),
               let milliseconds = Double(line[r]) {
                offset = milliseconds / 1000
            }
            let matches = timeRegex.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            var lyric = line
            for match in matches.reversed() {
                if let matchedRange = Range(match.range, in: lyric) {
                    lyric.removeSubrange(matchedRange)
                }
            }
            lyric = lyric.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyric.isEmpty else { continue }
            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minuteRange]),
                      let seconds = Double(line[secondRange]) else { continue }
                var fraction: Double = 0
                if let fracRange = Range(match.range(at: 3), in: line) {
                    let digits = String(line[fracRange])
                    if let value = Double(digits) {
                        fraction = value / pow(10.0, Double(digits.count))
                    }
                }
                result.append((minutes * 60 + seconds + fraction, lyric))
            }
        }
        result.sort { $0.time < $1.time }
        let lines = result.enumerated().map { idx, item in
            LyricLine(index: idx, time: item.time, text: item.text)
        }
        return LRCFile(lines: lines, embeddedOffset: offset)
    }
}

private extension NSRegularExpression {
    convenience init(pattern: String) {
        do {
            try self.init(pattern: pattern, options: [])
        } catch {
            preconditionFailure("Invalid regular expression: \(pattern) — \(error)")
        }
    }
}
