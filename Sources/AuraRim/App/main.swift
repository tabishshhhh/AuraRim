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

// Entry point. A menu-bar (accessory) app: no Dock icon or main window by
// default (spec §4). The delegate builds everything at launch.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
