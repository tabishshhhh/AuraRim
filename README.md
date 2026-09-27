<div align="center">

# ✨ AuraRim

### Ambient screen-edge lighting + word-by-word synced lyrics for macOS

A native menu-bar app that turns your Mac into an ambient music experience: a
glowing, **beat-reactive rim of light** around your display, plus **word-by-word
synced lyrics** in the player and full-screen on your lock screen — all colored
from the album art of whatever's playing.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-000000?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Metal](https://img.shields.io/badge/Metal-rendered-9cf)
![License](https://img.shields.io/badge/license-MIT-blue)
[![Stars](https://img.shields.io/github/stars/tabishshhhh/AuraRim?style=social)](https://github.com/tabishshhhh/AuraRim/stargazers)

<!-- Drop a demo GIF here — it's the single biggest thing for traction.
     Record with ⌘⇧5, convert to GIF (e.g. Gifski), save as docs/demo.gif: -->
<!-- ![AuraRim demo](docs/demo.gif) -->

**If this looks cool, drop a ⭐ — it genuinely helps.**

</div>

---

> **Originality.** AuraRim is an independent, from-scratch implementation of the
> publicly observable interaction models of two apps — *Lumn* (screen-edge
> ambient lighting) and *Verci* (word-by-word lock-screen lyrics). It contains no
> code, assets, or branding from either product. "AuraRim" is a neutral working
> name; branding is centralized in [`AppBrand.swift`](Sources/AuraRim/App/AppBrand.swift).

---

## Features

### Ambient rim
- Transparent, **click-through** glowing rim on any selected display (Metal-rendered).
- **Music Sync**: the rim reacts to *system audio* — brightness, glow, and a
  clockwise "light chase" driven by a bass-transient **beat detector**. Works with
  any Mac audio (Spotify, Apple Music, YouTube, games), because it analyzes the
  system mix, not app-specific hooks.
- **Idle** breathing and **Static** modes for low-key ambiance.
- **Automatic album colors** (two perceptually-separated colors, OKLab transitions)
  or manual colors with native pickers.
- **Multi-monitor**, per-display enable, live hotplug, **notch-aware** top edge.

### Lyrics
- **Real word-by-word timing** via NetEase Cloud Music's YRC format, with
  [lrclib](https://lrclib.net) as a line-level fallback. Words light exactly as
  they're sung.
- **Six styles**: Focus, Karaoke, Spotlight, Ship (3D drift), Fisheye (convex
  lens), Visual (words paired with SF Symbols).
- A smooth monotonic **playback clock** keeps lyrics in sync between metadata polls.

### Full-screen lock / idle display
- When the screen locks or the screensaver starts, AuraRim shows a full-screen
  ambient lyric display with a breathing, beat-pulsing glow rim.
- macOS does **not** permit drawing on the true secure lock screen (no app can);
  this is the compliant full-screen-on-lock approach, the same one Verci uses.

## Download

- **Prebuilt app:** grab the latest `AuraRim.dmg` from the
  [**Releases**](https://github.com/tabishshhhh/AuraRim/releases) page, drag it to
  Applications, and launch. *(No release yet? Build from source below — it's one command.)*
- **From source:** see [Build & run](#build--run).

## Requirements

- macOS 14 (Sonoma) or later. Built and tested on macOS 26 / Xcode 26 / Swift 6.
- Apple Silicon (arm64) or Intel (x86_64).

## Build & run

Swift Package. Open `Package.swift` in Xcode and run, **or** from the terminal:

```bash
./build.sh release
open ~/Applications/AuraRim.app
```

`build.sh` builds, assembles the `.app`, and code-signs it with a stable Apple
Development / Developer ID identity so macOS keeps your granted permissions across
rebuilds. It installs to **`~/Applications`** (a local, non-iCloud folder) on
purpose: if the signed bundle lives on an iCloud-synced Desktop/Documents folder,
iCloud stamps extended attributes on it that invalidate the signature and reset
permissions. Set `AURARIM_SIGN_ID` to force a specific identity.

```bash
swift test                       # unit tests
.build/release/AuraRim --render-test rim.png          # render one rim frame to PNG (no window)
.build/release/AuraRim --render-test rim.png --notch  # notched variant
```

The app launches as a **menu-bar accessory** — look for it in the menu bar, not
the Dock. First launch shows a short onboarding flow.

## Permissions & why

| Permission | Why | When |
|---|---|---|
| **System Audio Recording** | A CoreAudio process tap captures *system* audio (never the mic) to drive Music Sync. | First use of Music Sync. |
| **Screen & System Audio Recording** | Fallback capture via ScreenCaptureKit if the process tap is unavailable. | Only if the tap can't start. |
| **Automation** (Music / Spotify) | Read the current track + artwork for colors and lyrics lookup. | When a supported music app is running. |
| **Network** | Fetch lyrics (NetEase / lrclib) and album artwork. | When lyrics/colors are shown. |

AuraRim **never** uses the microphone. Audio is analyzed live on-device and is
never recorded or uploaded.

## Architecture

`Sources/AuraRim/…`

- **App/** — `main` (entry + `--render-test`), `AppDelegate`, `AppState`
  (`@Observable`), `RimController` (wires state → overlays/colors/audio/now-playing),
  `NowPlayingController` (player + full-screen ambient windows), `MenuBarController`,
  `AppBrand`.
- **Rendering/** — `MetalRenderer`, `RimShaderSource` (runtime-compiled Metal),
  `RimRenderer`, `OverlayWindow` (click-through `NSPanel`), `DisplayManager`.
- **Audio/** — `CoreAudioProcessTapCapture` (primary), `SystemAudioCapture`
  (ScreenCaptureKit fallback) behind an `AudioCapturing` protocol, `AudioAnalyzer`
  (vDSP FFT + bands), `BeatDetector`, `AnimationState` (lock-protected bus),
  `AudioEngine`.
- **Music/** — `MusicProvider` (Apple Music / Spotify via AppleScript),
  `LyricsProvider` + `NetEaseLyricsProvider` (YRC word-level) + lrclib,
  `PlaybackClock`, `ArtworkColorExtractor`, `NowPlayingManager`.
- **Color/** — `ColorValue` (+ OKLab), `ColorTransitionEngine`.
- **UI/** — `NowPlayingPlayerView`, `LyricsView` (six styles), `AmbientLyricsView`
  (lock screen), `LyricSymbolMap`, `ControlPanelView`, `SettingsView`, `OnboardingView`.
- **Persistence/** — `Preferences`, `KeychainManager`.

**Threading:** the main actor owns SwiftUI/AppKit; audio capture + DSP run on a
dedicated queue and hand a lock-protected `AnimationState` to the renderer; music
metadata runs in async tasks. No high-frequency audio flows through SwiftUI.

**Rendering/perf notes:** the ambient view keeps its glow ring as a *static*,
cached layer and animates only cheap opacity/scale transforms — full-screen
`blur`/`shadow`/`drawingGroup` per frame were found to peg the CPU and are avoided.

## Known limitations

- **NetEase lyrics API is unofficial/undocumented.** It can be geo-restricted or
  rate-limited; lyrics then fall back to lrclib (line-level) or show as unavailable.
- **Secure lock screen:** no third-party app can draw on the real secure screen;
  the full-screen display appears on lock/screensaver, not over the password prompt.
- **Visual style** only shows an icon when a word is in `LyricSymbolMap` (~260
  common words), so icon density varies by song.
- Sparkle auto-updates and a licensing backend are scaffolded behind protocols but
  are not wired to live accounts.

## Privacy

No raw audio is recorded or uploaded; no track history leaves the device; no
account; no analytics. Preferences live in UserDefaults; only track title/artist
leave the device, and only to look up lyrics and artwork.
