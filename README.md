# AuraRim

A native macOS menu-bar utility that draws an animated, glowing rim around your
display(s). The rim can react to system audio, pulse with the beat, and pick its
colors automatically from the album art of whatever's playing — or from colors
you choose. It's click-through, multi-monitor, notch-aware, and stays out of the
way until you turn it on.

> **AuraRim** is an original, independent implementation of the publicly
> observable interaction model of the app *Lumn*. It contains no code, assets,
> or branding from that product. "AuraRim" is a neutral working name; all
> branding is centralized in [`AppBrand.swift`](Sources/AuraRim/App/AppBrand.swift).

---

## What it does

- Transparent, **click-through** glowing rim on any selected display (Metal-rendered).
- **Music Sync** mode: brightness/glow/thickness react to system audio; a
  bass-transient **beat detector** drives elegant pulses. Works with *any* Mac
  audio — Spotify, Apple Music, YouTube, games, video — because it analyzes
  **system audio**, not app-specific hooks.
- **Idle** mode: slow luminous breathing + gradient drift when audio is quiet.
- **Static** mode: an ambient gradient with negligible GPU cost.
- **Automatic album colors**: extracts two perceptually-separated colors from
  album art and transitions to them smoothly (OKLab, 400–900 ms).
- **Manual colors** with two native color pickers + a color-balance slider.
- **Multi-monitor**, per-display enable, live hotplug handling, **notch-aware**
  top edge on built-in displays.
- Compact SwiftUI menu-bar control panel; optional conventional Settings window.
- Local-only, no account. License stored in the Keychain. Sleep/wake aware.

## System requirements

- macOS 14 (Sonoma) or later — built & tested on macOS 26, Xcode 26, Swift 6.3.
- Apple Silicon (arm64).

## Build & run

This is a Swift Package. Open `Package.swift` in Xcode 26 and run, **or** from
the terminal:

```bash
# Build a proper .app bundle (menu-bar accessory, ad-hoc signed):
./build.sh release
open AuraRim.app
```

```bash
# Run the unit tests:
swift test
```

```bash
# Visual QA: render one rim frame to a PNG without a window (spec §56):
.build/release/AuraRim --render-test rim.png          # plain
.build/release/AuraRim --render-test rim.png --notch   # notched display
```

The app launches as a **menu-bar accessory** — look for the rim glyph in the
menu bar, not the Dock. First launch shows a short onboarding flow.

## Required permissions & why

| Permission | Why | When requested |
|---|---|---|
| **Screen & System Audio Recording** | ScreenCaptureKit captures *system* audio (never the mic) to drive Music Sync. | On first use of Music Sync, or via onboarding "Allow System Audio". |
| **Automation** (Music / Spotify) | Read the current track + artwork for automatic colors. Optional. | Only when a supported music app is running and album colors are on. |

The app **never** requests microphone access. Audio is analyzed live on-device
and never recorded or uploaded. See the privacy copy in `AppBrand.swift`.

## Architecture

Modules mirror the spec's suggested layout (`Sources/AuraRim/…`):

- **App/** — `main` (entry + `--render-test`), `AppDelegate`, `AppState`
  (`@Observable`, the only user-facing state), `RimController` (the conductor:
  wires state → overlays/colors/audio/now-playing), `MenuBarController`,
  `LaunchAtLogin`, `AppBrand`.
- **Rendering/** — `MetalRenderer` (shared device/pipeline), `RimShaderSource`
  (runtime-compiled Metal), `RimRenderer` (per-view `MTKViewDelegate`),
  `OverlayWindow` (borderless click-through `NSPanel`), `DisplayOverlayController`,
  `DisplayManager` (+ notch geometry), `RimOffscreenRenderer` (QA).
- **Audio/** — `SystemAudioCapture` (ScreenCaptureKit), `AudioAnalyzer`
  (vDSP FFT + bands), `BeatDetector` (adaptive threshold), `AnimationState`
  (normalized bus), `AudioEngine` (orchestrator).
- **Color/** — `ColorValue` (+ OKLab), `ColorTransitionEngine`.
- **Music/** — `MusicProvider` protocol, `AppleMusicProvider`, `SpotifyProvider`
  (AppleScript), `ArtworkColorExtractor`, `NowPlayingManager` (adaptive polling
  + LRU color cache).
- **Persistence/** — `Preferences` (typed UserDefaults), `KeychainManager`.
- **Licensing/** — `LicenseManager` + `LicenseProviderProtocol` (+ stub).
- **Updates/** — `UpdateManaging` protocol (+ stub; Sparkle wiring below).
- **UI/** — `ControlPanelView`, `SettingsView`, `OnboardingView`, `RimPreview`.

**Threading model** (spec §63): the main actor owns SwiftUI/AppKit/windows; audio
capture + DSP run on a dedicated capture queue and hand a lock-protected
`AnimationState` to the renderer; music metadata runs in async tasks. No
high-frequency audio flows through SwiftUI observation.

### Audio processing

`System audio → PCM (SCK) → mono ring buffer → Hann-windowed FFT (vDSP) →
band energies (bass 40–180 Hz, mids, highs) + spectral flux → adaptive beat
detector → attack/release envelopes → normalized AnimationState`. The audio
callback never blocks on networking, disk, UI, or artwork decoding.

### Rendering

One shared Metal device/pipeline feeds an `MTKView` per display. The fragment
shader computes a rounded-rect signed distance for the rim core + exponential
bloom, a periodic perimeter gradient, beat/idle modulation, and a feathered
notch mask, output as premultiplied alpha over a transparent window.

### License configuration

`LicenseManager` persists the key in the Keychain and trusts a prior activation
when offline. Point `LicenseProviderProtocol` at your backend (Lemon Squeezy /
Polar / custom) by replacing `StubLicenseProvider` — no provider-specific code
leaks into the app.

### Sparkle setup

`UpdateManaging` is a stub so the app builds without the dependency. To enable
updates: add the Sparkle SwiftPM package, set `SUFeedURL` + `SUPublicEDKey` in
`Info.plist`, and forward `checkForUpdates()`/`automaticChecks` to
`SPUStandardUpdaterController`. Validate update signatures; never install
unsigned code.

## Signing, notarization & packaging (production)

`build.sh` ad-hoc signs for local dev. For distribution:

```bash
# 1. Sign with your Developer ID + hardened runtime + entitlements
codesign --force --deep --options runtime \
  --entitlements Resources/AuraRim.entitlements \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" AuraRim.app

# 2. Notarize
xcrun notarytool submit AuraRim.zip --keychain-profile "AC_PASSWORD" --wait

# 3. Staple
xcrun stapler staple AuraRim.app

# 4. Package a drag-to-Applications DMG
hdiutil create -volname AuraRim -srcfolder AuraRim.app -ov -format UDZO AuraRim.dmg
```

For the Mac App Store / full sandbox, enable `com.apple.security.app-sandbox`
and the automation/network entitlements noted in `Resources/AuraRim.entitlements`
(ScreenCaptureKit works under the sandbox with the user's TCC grant).

## Entitlements

See [`Resources/AuraRim.entitlements`](Resources/AuraRim.entitlements):
`automation.apple-events` (music metadata) and `network.client` (artwork URLs,
licensing, updates). Development builds are unsandboxed; the file documents the
sandbox additions.

## Known limitations

- **Live full-screen verification** of the on-screen overlay wasn't captured in
  the build session because the Mac's screen was locked; the rim was instead
  verified deterministically via `--render-test` (see `rim.png`). The overlay
  windows, click-through, and multi-monitor logic are implemented and compile;
  they should be spot-checked on an unlocked display.
- **Sparkle, the licensing backend, and Developer ID signing/notarization** are
  scaffolded behind protocols but require your accounts/keys to go live.
- Apple Music artwork is read as raw AppleScript data and normalized via
  `NSImage`; some tracks may not expose artwork.
- Advanced visual modes (Wave/Comet/Spectrum/…) are intentionally deferred until
  core parity is stable (spec §53).

## Privacy

No raw audio is recorded or uploaded; no track history leaves the device; no
account required; no analytics. Preferences live in UserDefaults; the license
key lives in the Keychain.
