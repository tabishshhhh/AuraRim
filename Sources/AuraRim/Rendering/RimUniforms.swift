import simd

/// GPU uniform block. Field order & types mirror `RimUniforms` in the Metal
/// source exactly so the memory layouts match (spec §9).
struct RimUniforms {
    var primaryColor: SIMD4<Float> = .init(1, 1, 1, 1)
    var secondaryColor: SIMD4<Float> = .init(1, 1, 1, 1)
    var resolution: SIMD2<Float> = .init(1, 1)
    var time: Float = 0
    var rimThickness: Float = 14
    var glowRadius: Float = 40
    var brightness: Float = 1
    var opacity: Float = 1
    var gradientMix: Float = 0.5
    var pulseStrength: Float = 0
    var beatPhase: Float = 0
    var idlePhase: Float = 0
    var silence: Float = 0
    var notchCenterX: Float = 0
    var notchWidth: Float = 0
    var notchHeight: Float = 0
    var cornerRadius: Float = 40
    var gradientRotation: Float = 0
    var animationMode: Int32 = 0
    var notchEnabled: Int32 = 0
}

/// Sendable per-display appearance snapshot, pushed from the main actor into the
/// renderer. Colors here are already resolved (album vs. manual) and mid-transition.
struct RimConfig: Sendable, Equatable {
    var enabled: Bool = true
    var thicknessPoints: Double = 14   // 2…40
    var glow: Double = 55              // 0…100
    var brightness: Double = 85        // 0…100
    var colorBalance: Double = 50      // 0…100
    var primary: ColorValue = .vibrantViolet
    var secondary: ColorValue = .coolBlue
    var animationMode: AnimationMode = .musicSync
    var notchEnabled: Bool = true
    var notch: NotchGeometry = .none
    var scale: Double = 2
    /// Corner radius of the display in points (Apple Silicon laptops ~ large).
    var cornerRadiusPoints: Double = 12

    static let disabled = RimConfig(enabled: false)
}
