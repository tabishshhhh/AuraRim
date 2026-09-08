import SwiftUI

/// Actions the popover can invoke, injected so the view stays free of AppKit.
struct ControlPanelActions {
    var openSettings: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var quit: () -> Void = {}
    var requestAudio: () -> Void = {}
    var showPlayer: () -> Void = {}
}

/// The primary menu-bar experience (spec §5, §34), matched to the reference:
/// minimal, translucent, native, compact. Every control updates the rim live.
struct ControlPanelView: View {
    @Bindable var state: AppState
    var actions: ControlPanelActions

    private var primaryPercent: Int { Int((100 - state.colorBalance).rounded()) }
    private var secondaryPercent: Int { Int(state.colorBalance.rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let track = state.currentTrack, track.playbackState != .stopped {
                nowPlayingRow(track)
            }
            Divider().opacity(0.4)

            dropdownRow("Gradient") {
                Picker("", selection: $state.gradientMode) {
                    ForEach(GradientMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.menu).fixedSize()
            }
            dropdownRow("Animation") {
                Picker("", selection: $state.animationMode) {
                    ForEach(AnimationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.menu).fixedSize()
            }

            toggleRow("Notch compatibility", $state.notchEnabled)
            audioWarningIfNeeded

            slider("Thickness", $state.thickness, 2...40)
            slider("Glow", $state.glow, 0...100)

            toggleRow("Override album color", $state.overrideAlbumColor)
            if state.overrideAlbumColor {
                HStack(alignment: .top, spacing: 18) {
                    ColorWheelPicker(title: "Primary", percent: primaryPercent, color: $state.primaryColor)
                    ColorWheelPicker(title: "Secondary", percent: secondaryPercent, color: $state.secondaryColor)
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
            }

            displaySection
            Divider().opacity(0.4)

            toggleRow("Lock screen player", $state.lockScreenPlayer)
            toggleRow("Show in Dock", $state.showInDock)
                .onChange(of: state.showInDock) { _, v in
                    NSApp.setActivationPolicy(v ? .regular : .accessory)
                }

            Divider().opacity(0.4)
            footer
        }
        .padding(16)
        .frame(width: 320)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.overrideAlbumColor)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.currentTrack)
    }

    // MARK: Header
    private var header: some View {
        HStack {
            Text(AppBrand.name).font(.title3.weight(.semibold))
            Spacer()
            Button {
                state.rimEnabled.toggle()
            } label: {
                Text(state.rimEnabled ? "Active" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.rimEnabled ? Color.orange : Color.secondary)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .glassCard(cornerRadius: 20, tint: state.rimEnabled ? .orange : nil, interactive: true)
            }
            .buttonStyle(.plain)
            .help("Rim Lighting")
        }
    }

    // MARK: Now playing (tap to open the big player)
    private func nowPlayingRow(_ track: TrackMetadata) -> some View {
        Button(action: actions.showPlayer) {
            HStack(spacing: 10) {
                Group {
                    if let data = track.artworkData, let img = NSImage(data: data) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .glassCard(cornerRadius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open player")
    }

    // MARK: Reusable rows
    private func dropdownRow<Content: View>(_ label: String, @ViewBuilder _ control: () -> Content) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            control()
        }
    }

    private func toggleRow(_ label: String, _ value: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Toggle("", isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            Slider(value: value, in: range)
        }
    }

    // MARK: Displays (spec §20)
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display").font(.subheadline)
            if state.displays.isEmpty {
                Text("No displays detected").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(state.displays) { display in
                let selected = state.selectedDisplayUUIDs.contains(display.uuid)
                Button {
                    if selected { state.selectedDisplayUUIDs.remove(display.uuid) }
                    else { state.selectedDisplayUUIDs.insert(display.uuid) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                        Text(display.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .glassCard(cornerRadius: 10)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Footer (spec §29 updates)
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Version \(appVersion) (\(appBuild))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates…", action: actions.checkForUpdates)
                    .font(.caption).buttonStyle(.link)
            }
            toggleRow("Check automatically", $state.automaticUpdates)
            Divider().opacity(0.4)
            Button("Quit \(AppBrand.name)", action: actions.quit)
                .buttonStyle(.plain).font(.subheadline)
        }
    }

    private var audioWarningIfNeeded: some View {
        Group {
            if state.animationMode == .musicSync && state.audioPermission == .denied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("System audio access is required for Music Sync.").font(.caption)
                    Spacer()
                    Button("Allow", action: actions.requestAudio).buttonStyle(.link).font(.caption)
                }
                .padding(8)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
