import AppKit

// Debug/QA: render one rim frame to a PNG and exit (spec §56). No window needed.
//   AuraRim --render-test [path] [--notch]
if let idx = CommandLine.arguments.firstIndex(of: "--render-test") {
    let path = CommandLine.arguments.count > idx + 1 && !CommandLine.arguments[idx+1].hasPrefix("--")
        ? CommandLine.arguments[idx+1]
        : "aurarim-rim.png"
    let notch = CommandLine.arguments.contains("--notch")
        ? NotchGeometry(hasNotch: true, centerX: 756, width: 200, height: 32)
        : .none
    var cfg = RimConfig()
    cfg.thicknessPoints = 14; cfg.glow = 60; cfg.brightness = 90; cfg.colorBalance = 50
    cfg.primary = .vibrantViolet; cfg.secondary = .coolBlue; cfg.scale = 2
    cfg.cornerRadiusPoints = 14
    let ok = RimOffscreenRenderer.renderPNG(to: path, width: 1512 * 2, height: 982 * 2,
                                            config: cfg, notch: notch)
    print(ok ? "Rendered \(path)" : "Render failed")
    exit(ok ? 0 : 1)
}

// Debug/QA: fetch lyrics once and print, then exit.
//   AuraRim --lyrics-test "Title" "Artist" ["Album"] [durationSeconds]
if let idx = CommandLine.arguments.firstIndex(of: "--lyrics-test") {
    let a = CommandLine.arguments
    let title = a.count > idx + 1 ? a[idx + 1] : "Never Gonna Give You Up"
    let artist = a.count > idx + 2 ? a[idx + 2] : "Rick Astley"
    let album = a.count > idx + 3 ? a[idx + 3] : ""
    let dur = a.count > idx + 4 ? Double(a[idx + 4]) ?? 0 : 213
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let lyrics = await LyricsProvider.fetch(title: title, artist: artist, album: album, duration: dur)
        if let lyrics {
            print("lines=\(lyrics.lines.count) synced=\(lyrics.isSynced)")
            for l in lyrics.lines.prefix(4) { print("  [\(l.time.map { String(format: "%.2f", $0) } ?? "-")] \(l.text)") }
        } else { print("NIL — fetch failed") }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// Debug/QA: render the panel + player UI to PNGs and exit.
//   AuraRim --render-ui <dir>
if let idx = CommandLine.arguments.firstIndex(of: "--render-ui") {
    let dir = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "."
    let appTmp = NSApplication.shared            // ImageRenderer needs an app context
    _ = appTmp
    MainActor.assumeIsolated { UISnapshot.renderAll(to: dir) }
    exit(0)
}

// Entry point. A menu-bar (accessory) app: no Dock icon or main window by
// default (spec §4). The delegate builds everything at launch.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
