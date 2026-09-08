import SwiftUI

/// Conventional settings window (spec §32) with native styling.
struct SettingsView: View {
    @Bindable var state: AppState
    let license: LicenseManager
    var requestAudio: () -> Void

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            appearance.tabItem { Label("Appearance", systemImage: "paintpalette") }
            music.tabItem { Label("Music", systemImage: "music.note") }
            displays.tabItem { Label("Displays", systemImage: "display") }
            licenseTab.tabItem { Label("License", systemImage: "key") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 420)
    }

    private var general: some View {
        Form {
            Toggle("Launch at Login", isOn: $state.launchAtLogin)
                .onChange(of: state.launchAtLogin) { _, v in LaunchAtLogin.set(v) }
            Toggle("Show in Dock", isOn: $state.showInDock)
                .onChange(of: state.showInDock) { _, v in
                    NSApp.setActivationPolicy(v ? .regular : .accessory)
                }
            Toggle("Start Rim on Launch", isOn: $state.rimEnabled)
        }.padding(20)
    }

    private var appearance: some View {
        Form {
            Picker("Animation Mode", selection: $state.animationMode) {
                ForEach(AnimationMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            slider("Thickness", $state.thickness, 2...40)
            slider("Glow", $state.glow, 0...100)
            slider("Brightness", $state.brightness, 0...100)
            slider("Color Balance", $state.colorBalance, 0...100)
            Toggle("Notch Compatibility", isOn: $state.notchEnabled)
        }.padding(20)
    }

    private var music: some View {
        Form {
            Toggle("Override album color", isOn: $state.overrideAlbumColor)
            LabeledContent("System Audio") {
                switch state.audioPermission {
                case .granted: Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .denied: Button("Allow…", action: requestAudio)
                default: Button("Request…", action: requestAudio)
                }
            }
            Text(AppBrand.privacyAudioCopy).font(.caption).foregroundStyle(.secondary)
            Text(AppBrand.privacyMusicCopy).font(.caption).foregroundStyle(.secondary)
        }.padding(20)
    }

    private var displays: some View {
        Form {
            if state.displays.isEmpty { Text("No displays detected.") }
            ForEach(state.displays) { d in
                Toggle(isOn: Binding(
                    get: { state.selectedDisplayUUIDs.contains(d.uuid) },
                    set: { on in
                        if on { state.selectedDisplayUUIDs.insert(d.uuid) }
                        else { state.selectedDisplayUUIDs.remove(d.uuid) }
                    })) {
                        Text("\(d.name)\(d.notch.hasNotch ? " (notch)" : "")")
                    }
            }
        }.padding(20)
    }

    private var licenseTab: some View {
        Form {
            LabeledContent("Status") { Text(licenseDescription) }
            if state.licenseState.isActive {
                Button("Deactivate This Mac") { Task { await license.deactivate() } }
            }
            Text("Your license key is stored securely in the macOS Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20)
    }

    private var about: some View {
        VStack(spacing: 10) {
            Image(systemName: AppBrand.symbolActive).font(.system(size: 48)).foregroundStyle(.tint)
            Text(AppBrand.name).font(.title.bold())
            Text("Version \(appVersion) (\(appBuild))").font(.caption).foregroundStyle(.secondary)
            Text(AppBrand.privacyAudioCopy).font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var licenseDescription: String {
        switch state.licenseState {
        case .active: return "Active on this Mac"
        case .unactivated: return "Not activated"
        case .activating: return "Activating…"
        case .invalid(let r): return "Invalid — \(r)"
        case .activationLimitReached: return "Activation limit reached"
        case .networkUnavailable: return "Network unavailable"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(label) { Slider(value: value, in: range).frame(width: 220) }
    }
}
