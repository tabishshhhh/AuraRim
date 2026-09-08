import Foundation

struct LyricLine: Identifiable, Sendable, Equatable {
    let id = UUID()
    let time: TimeInterval?   // nil for plain (unsynced) lyrics
    let text: String
}

struct Lyrics: Sendable, Equatable {
    let lines: [LyricLine]
    var isSynced: Bool { lines.contains { $0.time != nil } }
}

/// Fetches lyrics from lrclib.net — a free, open, no-auth synced-lyrics API
/// (spec §90 future extensibility). Only track metadata leaves the device, and
/// only to look up lyrics.
enum LyricsProvider {
    private struct Response: Decodable {
        let plainLyrics: String?
        let syncedLyrics: String?
        let instrumental: Bool?
    }

    static func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> Lyrics? {
        guard !title.isEmpty else { return nil }
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: album),
            .init(name: "duration", value: String(Int(duration.rounded())))
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("AuraRim (https://aurarim.app)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return await search(title: title, artist: artist)   // fuzzy fallback
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            if decoded.instrumental == true {
                return Lyrics(lines: [LyricLine(time: nil, text: "♪ Instrumental ♪")])
            }
            return parse(decoded)
        } catch {
            return await search(title: title, artist: artist)
        }
    }

    /// Fuzzy search fallback when the exact get() misses (album/duration off).
    private static func search(title: String, artist: String) async -> Lyrics? {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [.init(name: "track_name", value: title),
                            .init(name: "artist_name", value: artist)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("AuraRim (https://aurarim.app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let results = try? JSONDecoder().decode([Response].self, from: data),
              let best = results.first(where: { $0.syncedLyrics?.isEmpty == false })
                ?? results.first(where: { $0.plainLyrics?.isEmpty == false }) else { return nil }
        return parse(best)
    }

    private static func parse(_ r: Response) -> Lyrics? {
        if let synced = r.syncedLyrics, !synced.isEmpty {
            let lines = synced.split(separator: "\n").compactMap(parseLRCLine)
            if !lines.isEmpty { return Lyrics(lines: lines) }
        }
        if let plain = r.plainLyrics, !plain.isEmpty {
            let lines = plain.split(separator: "\n", omittingEmptySubsequences: false)
                .map { LyricLine(time: nil, text: String($0)) }
            return Lyrics(lines: lines)
        }
        return nil
    }

    /// Parse a line like `[01:23.45] some text`.
    private static func parseLRCLine(_ line: Substring) -> LyricLine? {
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
        let stamp = line[line.index(after: line.startIndex)..<close]   // mm:ss.xx
        let parts = stamp.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        let text = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        return LyricLine(time: m * 60 + s, text: text)
    }
}
