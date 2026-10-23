//
//  HelloAnimation.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/08/24.
//
//  Handwritten "hello" inspired by Apple's macOS welcome screen.
//  Path data adapted from ncdai's Apple Hello Effect (https://chanhdai.com/components/apple-hello-effect).
//

import SwiftUI

struct HelloShape: Shape {
    enum Stroke {
        /// The first downstroke of the "h".
        case h1
        /// The rest of the "h" flowing into "ello".
        case ello
    }

    var stroke: Stroke

    /// Size of the coordinate space the path data was drawn in.
    static let viewBox = CGSize(width: 638, height: 200)
    /// Stroke width in `viewBox` units.
    static let strokeWidth: CGFloat = 14.8883

    /// Scale factor that aspect-fits the `viewBox` into `size`.
    static func scale(for size: CGSize) -> CGFloat {
        min(size.width / viewBox.width, size.height / viewBox.height)
    }

    func path(in rect: CGRect) -> Path {
        let scale = Self.scale(for: rect.size)
        let offsetX = rect.minX + (rect.width - Self.viewBox.width * scale) / 2
        let offsetY = rect.minY + (rect.height - Self.viewBox.height * scale) / 2
        let transform = CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)

        switch stroke {
        case .h1: return Self.h1Path.applying(transform)
        case .ello: return Self.elloPath.applying(transform)
        }
    }

    private static let h1Path: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 8.69214, y: 166.553))
        path.addCurve(to: CGPoint(x: 89.8191, y: 98.0295), control1: CGPoint(x: 36.2393, y: 151.239), control2: CGPoint(x: 61.3409, y: 131.548))
        path.addCurve(to: CGPoint(x: 120.122, y: 31.0026), control1: CGPoint(x: 109.203, y: 75.1488), control2: CGPoint(x: 119.625, y: 49.0228))
        path.addCurve(to: CGPoint(x: 101.759, y: 7.43883), control1: CGPoint(x: 120.37, y: 17.6036), control2: CGPoint(x: 113.836, y: 7.43883))
        path.addCurve(to: CGPoint(x: 74.7122, y: 40.9363), control1: CGPoint(x: 88.3598, y: 7.43883), control2: CGPoint(x: 79.9231, y: 17.6036))
        path.addCurve(to: CGPoint(x: 54.1166, y: 190.356), control1: CGPoint(x: 69.005, y: 66.5793), control2: CGPoint(x: 64.7866, y: 96.0036))
        return path
    }()

    private static let elloPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 55.1624, y: 181.135))
        path.addCurve(to: CGPoint(x: 107.963, y: 98.0479), control1: CGPoint(x: 60.6251, y: 133.114), control2: CGPoint(x: 81.4118, y: 98.0479))
        path.addCurve(to: CGPoint(x: 131.071, y: 128.817), control1: CGPoint(x: 123.844, y: 98.0479), control2: CGPoint(x: 133.937, y: 110.703))
        path.addCurve(to: CGPoint(x: 125.408, y: 163.06), control1: CGPoint(x: 129.457, y: 139.487), control2: CGPoint(x: 127.587, y: 150.405))
        path.addCurve(to: CGPoint(x: 152.122, y: 191.348), control1: CGPoint(x: 122.869, y: 178.941), control2: CGPoint(x: 130.128, y: 191.348))
        path.addCurve(to: CGPoint(x: 237.097, y: 145.915), control1: CGPoint(x: 184.197, y: 191.348), control2: CGPoint(x: 219.189, y: 173.523))
        path.addCurve(to: CGPoint(x: 245.928, y: 119.884), control1: CGPoint(x: 243.198, y: 136.509), control2: CGPoint(x: 245.68, y: 128.073))
        path.addCurve(to: CGPoint(x: 222.851, y: 93.8296), control1: CGPoint(x: 246.176, y: 104.996), control2: CGPoint(x: 237.739, y: 93.8296))
        path.addCurve(to: CGPoint(x: 189.6, y: 142.465), control1: CGPoint(x: 203.992, y: 93.8296), control2: CGPoint(x: 189.6, y: 115.17))
        path.addCurve(to: CGPoint(x: 239.208, y: 192.341), control1: CGPoint(x: 189.6, y: 171.745), control2: CGPoint(x: 205.481, y: 192.341))
        path.addCurve(to: CGPoint(x: 359.199, y: 75.8585), control1: CGPoint(x: 285.066, y: 192.341), control2: CGPoint(x: 335.86, y: 137.292))
        path.addCurve(to: CGPoint(x: 368.26, y: 31.1512), control1: CGPoint(x: 365.788, y: 58.513), control2: CGPoint(x: 368.26, y: 42.4065))
        path.addCurve(to: CGPoint(x: 352.131, y: 7.55823), control1: CGPoint(x: 368.26, y: 17.8057), control2: CGPoint(x: 364.042, y: 7.55823))
        path.addCurve(to: CGPoint(x: 325.829, y: 30.9129), control1: CGPoint(x: 340.469, y: 7.55823), control2: CGPoint(x: 332.777, y: 16.6141))
        path.addCurve(to: CGPoint(x: 309.203, y: 98.4549), control1: CGPoint(x: 317.688, y: 47.4967), control2: CGPoint(x: 311.667, y: 71.4162))
        path.addCurve(to: CGPoint(x: 349.936, y: 191.348), control1: CGPoint(x: 303, y: 166.301), control2: CGPoint(x: 316.896, y: 191.348))
        path.addCurve(to: CGPoint(x: 457.286, y: 75.6686), control1: CGPoint(x: 390, y: 191.348), control2: CGPoint(x: 434.542, y: 135.534))
        path.addCurve(to: CGPoint(x: 466.275, y: 31.1512), control1: CGPoint(x: 463.803, y: 58.513), control2: CGPoint(x: 466.275, y: 42.4065))
        path.addCurve(to: CGPoint(x: 450.146, y: 7.55823), control1: CGPoint(x: 466.275, y: 17.8057), control2: CGPoint(x: 462.057, y: 7.55823))
        path.addCurve(to: CGPoint(x: 423.844, y: 30.9129), control1: CGPoint(x: 438.484, y: 7.55823), control2: CGPoint(x: 430.792, y: 16.6141))
        path.addCurve(to: CGPoint(x: 407.218, y: 98.4549), control1: CGPoint(x: 415.703, y: 47.4967), control2: CGPoint(x: 409.682, y: 71.4162))
        path.addCurve(to: CGPoint(x: 444.416, y: 191.348), control1: CGPoint(x: 401.015, y: 166.301), control2: CGPoint(x: 414.911, y: 191.348))
        path.addCurve(to: CGPoint(x: 499.471, y: 138.402), control1: CGPoint(x: 473.874, y: 191.348), control2: CGPoint(x: 489.877, y: 165.67))
        path.addCurve(to: CGPoint(x: 544.935, y: 94.8221), control1: CGPoint(x: 508.955, y: 111.447), control2: CGPoint(x: 520.618, y: 94.8221))
        path.addCurve(to: CGPoint(x: 580.916, y: 137.75), control1: CGPoint(x: 565.035, y: 94.8221), control2: CGPoint(x: 580.916, y: 109.71))
        path.addCurve(to: CGPoint(x: 535.362, y: 192.341), control1: CGPoint(x: 580.916, y: 168.768), control2: CGPoint(x: 560.792, y: 192.093))
        path.addCurve(to: CGPoint(x: 499.774, y: 147.179), control1: CGPoint(x: 512.984, y: 192.589), control2: CGPoint(x: 498.285, y: 174.475))
        path.addCurve(to: CGPoint(x: 543.943, y: 94.8221), control1: CGPoint(x: 501.511, y: 116.907), control2: CGPoint(x: 519.873, y: 94.8221))
        path.addCurve(to: CGPoint(x: 578.682, y: 107.725), control1: CGPoint(x: 557.839, y: 94.8221), control2: CGPoint(x: 569.51, y: 100.999))
        path.addCurve(to: CGPoint(x: 630.047, y: 96.7186), control1: CGPoint(x: 603.549, y: 125.866), control2: CGPoint(x: 622.709, y: 114.656))
        return path
    }()
}

struct HelloAnimation: View {
    /// Scales every duration and delay of the handwriting. Values below 1 speed it up.
    var durationScale: Double = 1.0
    var onFinish: () -> Void

    @State private var h1Progress: CGFloat = 0
    @State private var h1Opacity: Double = 0
    @State private var elloProgress: CGFloat = 0
    @State private var elloOpacity: Double = 0
    @State private var opacity: Double = 1

    var body: some View {
        GeometryReader { geometry in
            let lineWidth = HelloShape.strokeWidth * HelloShape.scale(for: geometry.size)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            ZStack {
                HelloShape(stroke: .h1)
                    .trim(from: 0, to: h1Progress)
                    .stroke(.white, style: style)
                    .opacity(h1Opacity)

                HelloShape(stroke: .ello)
                    .trim(from: 0, to: elloProgress)
                    .stroke(.white, style: style)
                    .opacity(elloOpacity)
            }
        }
        .opacity(opacity)
        .accessibilityLabel("hello")
        .task {
            // Wait for the "opening" animation (notch expansion) to complete before writing
            try? await Task.sleep(for: .seconds(0.6))

            let scale = durationScale
            withAnimation(.easeInOut(duration: 0.8 * scale)) {
                h1Progress = 1
            }
            withAnimation(.easeOut(duration: 0.4)) {
                h1Opacity = 1
            }
            withAnimation(.easeInOut(duration: 2.8 * scale).delay(0.7 * scale)) {
                elloProgress = 1
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.7 * scale)) {
                elloOpacity = 1
            }

            // Let the finished word linger for a moment, then fade it out
            try? await Task.sleep(for: .seconds(3.5 * scale + 0.8))
            withAnimation(.easeInOut(duration: 0.5)) {
                opacity = 0
            }
            try? await Task.sleep(for: .seconds(0.5))

            onFinish()
        }
    }
}

#Preview {
    HelloAnimation(onFinish: {})
        .frame(width: 300, height: 100)
        .background(.black)
}
