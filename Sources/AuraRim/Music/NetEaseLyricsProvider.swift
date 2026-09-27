import Foundation

/// Fetches word-level ("karaoke") lyrics from NetEase Cloud Music's public
/// endpoints — the same source Verci uses for its per-word timing. NetEase's
/// proprietary **YRC** format carries a start + duration for every word, which is
/// what lets each word light exactly as it's sung (line-level LRC can't).
///
/// This is an unofficial, undocumented API: it can be geo-restricted or rate
/// limited, so every call is best-effort and the caller falls back to lrclib.
/// Only track title/artist leave the device, and only to look up lyrics.
enum NetEaseLyricsProvider {
    private static let searchURL = "https://music.163.com/api/search/get"
    private static let lyricURL  = "https://music.163.com/api/song/lyric/v1"

    static func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> Lyrics? {
        guard let song = await searchSong(title: title, artist: artist, duration: duration) else {
            return nil
        }
        return await lyric(songID: song)
    }

    // MARK: Search

    private struct SearchEnvelope: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            let id: Int
            let name: String
            let artists: [Artist]?
            let duration: Int?   // milliseconds
        }
        struct Artist: Decodable { let name: String }
        let result: Result?
    }

    /// Returns the best-matching NetEase song id for the track, or nil.
    private static func searchSong(title: String, artist: String, duration: TimeInterval) async -> Int? {
        var comps = URLComponents(string: searchURL)!
        comps.queryItems = [
            .init(name: "s", value: "\(title) \(artist)".trimmingCharacters(in: .whitespaces)),
            .init(name: "type", value: "1"),      // 1 = songs
            .init(name: "limit", value: "10"),
            .init(name: "offset", value: "0")
        ]
        guard let url = comps.url,
              let data = await get(url),
              let env = try? JSONDecoder().decode(SearchEnvelope.self, from: data),
              let songs = env.result?.songs, !songs.isEmpty else { return nil }

        let wantTitle = normalize(title)
        let wantArtist = normalize(artist)
        let durMs = duration * 1000

        // Score candidates: title match is required-ish, artist + duration refine.
        func score(_ s: SearchEnvelope.Song) -> Double {
            var v = 0.0
            let t = normalize(s.name)
            if t == wantTitle { v += 3 } else if t.contains(wantTitle) || wantTitle.contains(t) { v += 1.5 }
            let artists = (s.artists ?? []).map { normalize($0.name) }.joined(separator: " ")
            if !wantArtist.isEmpty, artists.contains(wantArtist) || wantArtist.contains(artists) { v += 2 }
            if durMs > 0, let d = s.duration, abs(Double(d) - durMs) < 5_000 { v += 2 }
            else if durMs > 0, let d = s.duration, abs(Double(d) - durMs) < 12_000 { v += 0.5 }
            return v
        }

        let best = songs.max { score($0) < score($1) }
        guard let best, score(best) >= 1.5 else { return nil }   // avoid wrong-song lyrics
        return best.id
    }

    // MARK: Lyric fetch

    private struct LyricEnvelope: Decodable {
        struct Lyric: Decodable { let lyric: String? }
        let lrc: Lyric?     // line-level LRC
        let yrc: Lyric?     // word-level (YRC) — the good stuff
        let klyric: Lyric?  // alternate word-level format on some tracks
    }

    private static func lyric(songID: Int) async -> Lyrics? {
        var comps = URLComponents(string: lyricURL)!
        comps.queryItems = [
            .init(name: "id", value: String(songID)),
            .init(name: "cp", value: "false"),
            .init(name: "lv", value: "0"),
            .init(name: "kv", value: "0"),
            .init(name: "tv", value: "0"),
            .init(name: "rv", value: "0"),
            .init(name: "yv", value: "0"),    // request YRC (word-level)
            .init(name: "ytv", value: "0"),
            .init(name: "yrv", value: "0")
        ]
        guard let url = comps.url,
              let data = await get(url),
              let env = try? JSONDecoder().decode(LyricEnvelope.self, from: data) else { return nil }

        if let yrc = env.yrc?.lyric, !yrc.isEmpty {
            let lines = parseYRC(yrc)
            if lines.contains(where: { $0.words?.isEmpty == false }) {
                return Lyrics(lines: lines)
            }
        }
        if let lrc = env.lrc?.lyric, !lrc.isEmpty {
            let lines = parseLRC(lrc)
            if !lines.isEmpty { return Lyrics(lines: lines) }
        }
        return nil
    }

    // MARK: YRC parsing
    //
    // A YRC line looks like:
    //   [8930,4300](8930,540,0)Two (9470,300,0)hundred (9770,420,0)shooters
    // where [lineStartMs,lineDurationMs] is followed by (startMs,durMs,0)word
    // segments. Some lines are JSON metadata (translator/credits) and start with
    // "{" — those are skipped.
    static func parseYRC(_ raw: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for rawLine in raw.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.hasPrefix("["), !line.hasPrefix("[{") else { continue }
            guard let headEnd = line.firstIndex(of: "]") else { continue }
            let header = line[line.index(after: line.startIndex)..<headEnd]
            let hp = header.split(separator: ",")
            guard let startMs = Double(hp.first.map(String.init) ?? "") else { continue }

            let body = line[line.index(after: headEnd)...]
            var words: [LyricWord] = []
            var text = ""
            var idx = body.startIndex
            while idx < body.endIndex {
                guard body[idx] == "(",
                      let close = body[idx...].firstIndex(of: ")") else { break }
                let meta = body[body.index(after: idx)..<close].split(separator: ",")
                let ws = Double(meta.count > 0 ? String(meta[0]) : "") ?? 0
                let wd = Double(meta.count > 1 ? String(meta[1]) : "") ?? 0
                let afterClose = body.index(after: close)
                let nextParen = body[afterClose...].firstIndex(of: "(") ?? body.endIndex
                let seg = String(body[afterClose..<nextParen])
                if !seg.isEmpty {
                    words.append(LyricWord(time: ws / 1000, duration: wd / 1000, text: seg))
                    text += seg
                }
                idx = nextParen
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty && words.isEmpty { continue }
            out.append(LyricLine(time: startMs / 1000, text: trimmed,
                                 words: words.isEmpty ? nil : words))
        }
        return out
    }

    // MARK: LRC parsing (fallback)

    static func parseLRC(_ raw: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for rawLine in raw.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let stamp = line[line.index(after: line.startIndex)..<close]  // mm:ss.xx
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { continue }
            let text = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            out.append(LyricLine(time: m * 60 + s, text: text))
        }
        return out
    }

    // MARK: Networking helpers

    private static func get(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue("os=pc; appver=8.9.70", forHTTPHeaderField: "Cookie")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }

    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        // Drop bracketed qualifiers like "(feat. …)" / "[Remastered]" and punctuation.
        var result = ""
        var depth = 0
        for ch in lowered {
            if ch == "(" || ch == "[" { depth += 1; continue }
            if ch == ")" || ch == "]" { depth = max(0, depth - 1); continue }
            if depth == 0, ch.isLetter || ch.isNumber || ch == " " { result.append(ch) }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
