import Foundation

/// Pure filename/path helpers. This file can be typechecked and tested on Linux too.
enum LibraryFileRules {
    static let acceptedExtensions: Set<String> = ["flac", "lrc"]

    static func normalizedStem(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    static func contains(_ child: URL, in directory: URL) -> Bool {
        let base = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = child.standardizedFileURL.resolvingSymlinksInPath().path
        return candidate == base || candidate.hasPrefix(base + "/")
    }

    static func relativePath(of url: URL, in directory: URL) -> String? {
        let root = directory.standardizedFileURL.path
        let file = url.standardizedFileURL.path
        guard file.hasPrefix(root + "/") else { return nil }
        return String(file.dropFirst(root.count + 1))
    }

    /// Name collision candidates stay within the same directory.
    static func collisionName(base: String, ext: String, index: Int) -> String {
        index < 2 ? "\(base).\(ext)" : "\(base) (\(index)).\(ext)"
    }

    /// Matching by title is allowed only when there is exactly one candidate.
    static func uniqueMatch(lyricStem: String, trackStems: [String: [UUID]], titles: [String: [UUID]]) -> UUID? {
        let key = normalizedStem(lyricStem)
        let exact = Array(Set(trackStems[key] ?? []))
        if exact.count == 1 { return exact.first }
        if !exact.isEmpty { return nil }
        let byTitle = Array(Set(titles[key] ?? []))
        return byTitle.count == 1 ? byTitle.first : nil
    }
}
