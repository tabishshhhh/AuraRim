import SwiftUI
import simd

/// A persistable, thread-safe RGBA color in extended sRGB (components 0…1).
/// Interpolation is done in OKLab so album-color transitions feel perceptually
/// even rather than muddying through grey (spec §36, §68).
struct ColorValue: Codable, Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var simd: SIMD4<Float> { SIMD4(Float(r), Float(g), Float(b), Float(a)) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    var nsColor: NSColor {
        NSColor(srgbRed: r.clamped01, green: g.clamped01, blue: b.clamped01, alpha: a.clamped01)
    }

    init(_ nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent),
                  b: Double(c.blueComponent), a: Double(c.alphaComponent))
    }

    // MARK: Presets (spec §73 initial defaults)
    static let vibrantViolet = ColorValue(r: 0.60, g: 0.30, b: 1.00)
    static let coolBlue = ColorValue(r: 0.20, g: 0.55, b: 1.00)

    // MARK: - OKLab

    /// Perceptual linear interpolation. `t` in 0…1.
    static func mix(_ a: ColorValue, _ b: ColorValue, _ t: Double) -> ColorValue {
        let la = OKLab(a), lb = OKLab(b)
        let m = OKLab(
            L: la.L + (lb.L - la.L) * t,
            a: la.a + (lb.a - la.a) * t,
            b: la.b + (lb.b - la.b) * t
        )
        var out = m.toColorValue()
        out.a = a.a + (b.a - a.a) * t
        return out
    }
}

/// Minimal OKLab implementation (Björn Ottosson). Enough for interpolation and
/// deriving complementary/analogous secondary colors from album art.
struct OKLab {
    var L: Double, a: Double, b: Double

    init(L: Double, a: Double, b: Double) { self.L = L; self.a = a; self.b = b }

    init(_ c: ColorValue) {
        // sRGB -> linear
        func lin(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = lin(c.r), g = lin(c.g), bl = lin(c.b)
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }

    func toColorValue() -> ColorValue {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        var r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        var g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        var bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func gam(_ v: Double) -> Double {
            let x = v.clamped01
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        r = gam(r); g = gam(g); bl = gam(bl)
        return ColorValue(r: r, g: g, b: bl)
    }

    /// Chroma in the a/b plane.
    var chroma: Double { (a * a + b * b).squareRoot() }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
