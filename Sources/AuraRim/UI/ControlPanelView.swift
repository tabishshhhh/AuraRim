import SwiftUI

/// Actions the popover can invoke, injected so the view stays free of AppKit.
struct ControlPanelActions {
    var openSettings: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var quit: () -> Void = {}
    var openAudioSettings: () -> Void = {}
    var activateSource: (TrackMetadata) -> Void = { _ in }
}

/// The primary menu-bar experience (spec §5, §34). Minimal, translucent, native,
/// compact. All controls update the rim in real time — no Apply button.
struct ControlPanelView: View {
    @Bindable var state: AppState
    var actions: ControlPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let track = state.currentTrack, track.playbackState != .stopped {
                nowPlaying(track)
            }
            audioWarningIfNeeded
            colorSection
            animationSection
            appearanceSection
            displaySection
            Divider().opacity(0.5)
            footer
        }
        .padding(16)
        .frame(width: 360)
        .animation(.easeInOut(duration: 0.2), value: state.currentTrack)
        .animation(.easeInOut(duration: 0.2), value: state.albumColorEnabled)
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.rimEnabled ? AppBrand.symbolActive : AppBrand.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(state.rimEnabled ? Color.accentColor : .secondary)
            Text(AppBrand.name).font(.headline)
            Spacer()
            Toggle("", isOn: $state.rimEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Rim Lighting")
        }
    }

    // MARK: Now Playing (spec §22)
    private func nowPlaying(_ track: TrackMetadata) -> some View {
        HStack(spacing: 12) {
            artwork(track)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(track.sourceName).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: track.playbackState == .playing ? "waveform" : "pause.fill")
                .foregroundStyle(.secondary).font(.caption)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { actions.activateSource(track) }
    }

    @ViewBuilder private func artwork(_ track: TrackMetadata) -> some View {
        if let data = track.artworkData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }

    // MARK: Color (spec §10, §11)
    private var colorSection: some View {
        Section(title: "Color") {
            Toggle("Album Colors", isOn: $state.albumColorEnabled)
                .toggleStyle(.switch)
            if !state.albumColorEnabled {
                HStack(spacing: 16) {
                    ColorPicker("Primary", selection: state.primaryBinding, supportsOpacity: false)
                    ColorPicker("Secondary", selection: state.secondaryBinding, supportsOpacity: false)
                }
                .font(.subheadline)
            }
            LabeledSlider(label: "Color Balance", value: $state.colorBalance, range: 0...100)
        }
    }

    // MARK: Animation (spec §16–18)
    private var animationSection: some View {
        Section(title: "Animation") {
            Picker("", selection: $state.animationMode) {
                ForEach(AnimationMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: Appearance (spec §21)
    private var appearanceSection: some View {
        Section(title: "Appearance") {
            LabeledSlider(label: "Thickness", value: $state.thickness, range: 2...40)
            LabeledSlider(label: "Glow", value: $state.glow, range: 0...100)
            LabeledSlider(label: "Brightness", value: $state.brightness, range: 0...100)
            Toggle("Notch Compatibility", isOn: $state.notchEnabled).toggleStyle(.switch)
        }
    }

    // MARK: Displays (spec §20)
    private var displaySection: some View {
        Section(title: "Displays") {
            if state.displays.isEmpty {
                Text("No displays detected").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(state.displays) { display in
                Toggle(isOn: bindingForDisplay(display.uuid)) {
                    HStack(spacing: 6) {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        Text(display.name).lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var audioWarningIfNeeded: some View {
        Group {
            if state.animationMode == .musicSync && state.audioPermission == .denied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("System audio access is required for Music Sync.")
                        .font(.caption)
                    Spacer()
                    Button("Open Settings", action: actions.openAudioSettings)
                        .buttonStyle(.link).font(.caption)
                }
                .padding(8)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Footer
    private var footer: some View {
        HStack {
            Button(action: actions.openSettings) {
                Label("Settings", systemImage: "gearshape")
            }.buttonStyle(.plain)
            Spacer()
            Menu {
                Button("Check for Updates…", action: actions.checkForUpdates)
                Button("Quit \(AppBrand.name)", action: actions.quit)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)
        }
        .font(.subheadline)
    }

    private func bindingForDisplay(_ uuid: String) -> Binding<Bool> {
        Binding(
            get: { state.selectedDisplayUUIDs.contains(uuid) },
            set: { on in
                if on { state.selectedDisplayUUIDs.insert(uuid) }
                else { state.selectedDisplayUUIDs.remove(uuid) }
            })
    }
}

// MARK: - Small reusable pieces

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.subheadline).frame(width: 96, alignment: .leading)
            Slider(value: $value, in: range)
        }
    }
}

extension AppState {
    var primaryBinding: Binding<Color> {
        Binding(get: { self.primaryColor.color },
                set: { self.primaryColor = ColorValue(NSColor($0)) })
    }
    var secondaryBinding: Binding<Color> {
        Binding(get: { self.secondaryColor.color },
                set: { self.secondaryColor = ColorValue(NSColor($0)) })
    }
}
