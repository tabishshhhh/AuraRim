import SwiftUI

/// An inline HSB color wheel (hue = angle, saturation = radius) with a draggable
/// knob, matching the reference panel. Brightness is edited separately.
struct ColorWheel: View {
    @Binding var color: ColorValue

    private var hsb: (h: CGFloat, s: CGFloat, b: CGFloat) {
        let c = color.nsColor.usingColorSpace(.deviceRGB) ?? color.nsColor
        return (c.hueComponent, c.saturationComponent, c.brightnessComponent)
    }

    private let rainbow: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12.0)
        .map { Color(hue: $0, saturation: 1, brightness: 1) }

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let r = d / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let cur = hsb
            let knob = CGPoint(
                x: center.x + cos(cur.h * 2 * .pi) * cur.s * r,
                y: center.y + sin(cur.h * 2 * .pi) * cur.s * r)

            ZStack {
                Circle()
                    .fill(AngularGradient(gradient: Gradient(colors: rainbow), center: .center))
                    .overlay(Circle().fill(RadialGradient(
                        gradient: Gradient(colors: [.white, .white.opacity(0)]),
                        center: .center, startRadius: 0, endRadius: r)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12)))
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .background(Circle().fill(color.color))
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .position(knob)
            }
            .frame(width: d, height: d)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                update(location: g.location, center: center, radius: r, brightness: cur.b)
            })
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func update(location: CGPoint, center: CGPoint, radius: CGFloat, brightness: CGFloat) {
        let dx = location.x - center.x, dy = location.y - center.y
        var angle = atan2(dy, dx) / (2 * .pi)
        if angle < 0 { angle += 1 }
        let sat = min(1, sqrt(dx * dx + dy * dy) / radius)
        let ns = NSColor(deviceHue: angle, saturation: sat, brightness: max(0.15, brightness), alpha: 1)
        color = ColorValue(ns)
    }
}

/// Wheel + title/percentage + a brightness slider, matching the reference block.
struct ColorWheelPicker: View {
    let title: String
    let percent: Int
    @Binding var color: ColorValue

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(percent)%").font(.caption).foregroundStyle(.secondary)
            }
            ColorWheel(color: $color)
            HStack(spacing: 6) {
                Image(systemName: "sun.min").font(.caption2).foregroundStyle(.secondary)
                Slider(value: brightnessBinding, in: 0.15...1)
                Image(systemName: "sun.max").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: {
                let c = color.nsColor.usingColorSpace(.deviceRGB) ?? color.nsColor
                return Double(c.brightnessComponent)
            },
            set: { newB in
                let c = color.nsColor.usingColorSpace(.deviceRGB) ?? color.nsColor
                color = ColorValue(NSColor(deviceHue: c.hueComponent, saturation: c.saturationComponent,
                                           brightness: CGFloat(newB), alpha: 1))
            })
    }
}
