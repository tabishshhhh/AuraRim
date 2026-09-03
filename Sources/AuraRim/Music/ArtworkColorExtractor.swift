import CoreGraphics
import AppKit

/// Extracts a primary + secondary color from album art (spec §11, §68).
/// Pure and testable — give it a CGImage, get two display-ready colors that are
/// perceptually separated and luminance-clamped so the glow always shows.
enum ArtworkColorExtractor {

    static func extract(from image: CGImage, size: Int = 48) -> (primary: ColorValue, secondary: ColorValue)? {
        guard let pixels = downscaledPixels(image, size: size) else { return nil }

        // Weighted histogram in a coarse RGB grid (spec §68: cluster + weight).
        struct Bucket { var count = 0; var r = 0.0; var g = 0.0; var b = 0.0; var sat = 0.0 }
        var buckets: [Int: Bucket] = [:]
        var i = 0
        while i + 3 < pixels.count {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i+1]) / 255
            let b = Double(pixels[i+2]) / 255, a = Double(pixels[i+3]) / 255
            i += 4
            if a < 0.5 { continue }                              // ignore transparent
            let mx = max(r, g, b), mn = min(r, g, b)
            if mx < 0.06 { continue }                            // reject near-black
            if mn > 0.95 { continue }                            // reject near-white
            let sat = mx <= 0 ? 0 : (mx - mn) / mx
            let key = (Int(r * 7) << 6) | (Int(g * 7) << 3) | Int(b * 7)
            var bkt = buckets[key] ?? Bucket()
            bkt.count += 1; bkt.r += r; bkt.g += g; bkt.b += b; bkt.sat += sat
            buckets[key] = bkt
        }
        guard !buckets.isEmpty else { return nil }

        // Average each bucket, weight by frequency × saturation (favor saturation).
        let clusters: [(color: ColorValue, weight: Double)] = buckets.values.map { b in
            let n = Double(b.count)
            let color = ColorValue(r: b.r / n, g: b.g / n, b: b.b / n)
            let sat = b.sat / n
            return (color, n * (0.25 + sat))
        }.sorted { $0.weight > $1.weight }

        let primary = clampForGlow(clusters[0].color)

        // Secondary: first cluster far enough from primary in OKLab; else derive.
        let minDistance = 0.12
        let primaryLab = OKLab(primary)
        var secondary: ColorValue?
        for c in clusters.dropFirst() {
            if oklabDistance(primaryLab, OKLab(clampForGlow(c.color))) > minDistance {
                secondary = clampForGlow(c.color); break
            }
        }
        return (primary, secondary ?? derivedComplement(of: primary))
    }

    // MARK: Helpers

    /// Keep luminance/chroma in a visible band so dark or washed-out art still glows.
    private static func clampForGlow(_ c: ColorValue) -> ColorValue {
        var lab = OKLab(c)
        lab.L = min(0.82, max(0.5, lab.L))
        // Ensure a little chroma so the color reads.
        if lab.chroma < 0.06 {
            let scale = 0.06 / max(lab.chroma, 1e-4)
            lab.a *= scale; lab.b *= scale
        }
        return lab.toColorValue()
    }

    /// Rotate hue ~150° in the OKLab a/b plane for an analogous/complementary
    /// second color when art is essentially monochrome (spec §11).
    private static func derivedComplement(of c: ColorValue) -> ColorValue {
        var lab = OKLab(c)
        let angle = atan2(lab.b, lab.a) + .pi * 0.83
        let chroma = max(0.09, lab.chroma)
        lab.a = cos(angle) * chroma
        lab.b = sin(angle) * chroma
        lab.L = min(0.82, max(0.5, lab.L * 0.95 + 0.05))
        return lab.toColorValue()
    }

    private static func oklabDistance(_ a: OKLab, _ b: OKLab) -> Double {
        let dL = a.L - b.L, da = a.a - b.a, db = a.b - b.b
        return (dL * dL + da * da + db * db).squareRoot()
    }

    private static func downscaledPixels(_ image: CGImage, size: Int) -> [UInt8]? {
        let bytesPerRow = size * 4
        var data = [UInt8](repeating: 0, count: size * size * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return data
    }
}
