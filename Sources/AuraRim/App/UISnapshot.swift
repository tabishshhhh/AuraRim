import SwiftUI
import AppKit

/// QA-only: render the panel and player to PNGs with `ImageRenderer`, so UI can
/// be verified without an awake physical display. Debug builds/CLI only.
@MainActor
enum UISnapshot {
    static func renderAll(to dir: String) {
        let state = AppState()
        state.overrideAlbumColor = true          // show the color wheels
        state.displays = [DisplayInfo(id: 1, uuid: "u", name: "Built-in Retina Display",
                                      frame: .init(x: 0, y: 0, width: 1512, height: 982),
                                      scale: 2, isBuiltIn: true, refreshRate: 120, notch: .none)]
        state.selectedDisplayUUIDs = ["u"]
        state.currentTrack = TrackMetadata(
            title: "Earrings", artist: "Malcolm Todd", album: "Malcolm Todd",
            duration: 200, playbackPosition: 40, playbackState: .playing,
            bundleIdentifier: "com.spotify.client", sourceName: "Spotify", artworkData: nil)
        state.albumColors = (ColorValue(r: 0.6, g: 0.2, b: 0.35), ColorValue(r: 0.2, g: 0.3, b: 0.6))

        render(ControlPanelView(state: state, actions: .init()), to: "\(dir)/panel.png")
        render(NowPlayingPlayerView(state: state, isExpanded: false, actions: .init())
                .frame(width: 720, height: 600), to: "\(dir)/player.png")
    }

    private static func render<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view.padding(0).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed for \(path)"); return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
