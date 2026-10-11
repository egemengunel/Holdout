//
//  TouchBarStage.swift
//  Nudge
//

import AVFoundation
import SwiftUI

/// A render of the MacBook with its Touch Bar switched off (`Design/Film/plates.py`), with live
/// content drawn onto the bar's screen in perspective: a real recording of the bar, or a view.
/// The plates' edges are baked to dissolve into black; the content fades with them.
struct TouchBarStage<Content: View>: View {
    enum Plate: String {
        /// The whole bar from above, with the bezel and the number row.
        case bar = "Bar"
        /// Closer on the strip's content: its sessions, project and buttons.
        case strip = "Strip"
        /// The bar's right end: the Control Strip, Touch ID and the delete key.
        case right = "Right"
        /// The whole deck from high above.
        case wide = "Wide"
    }

    let plate: Plate
    @ViewBuilder var content: Content

    var body: some View {
        if let geometry = PlateGeometry.load(plate.rawValue), let image = Cinematic.image("Plate" + plate.rawValue) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(geometry.size.width / geometry.size.height, contentMode: .fit)
                .overlay {
                    StageCanvas(geometry: geometry, content: AnyView(content))
                }
                .accessibilityHidden(true)
        }
    }
}

extension TouchBarStage where Content == BarVideo {
    /// A recording of the bar (2008 × 60, from `Design/Film/record.sh`), looping.
    init(plate: Plate, clip: String) {
        self.init(plate: plate) { BarVideo(name: clip) }
    }
}

/// The Touch Bar's own size, in points: content is laid out at this size, then projected.
enum TouchBarMetrics {
    static let size = CGSize(width: 1004, height: 30)
}

/// Where the bar's screen lands in a plate, in the plate's pixels.
struct PlateGeometry: Decodable {
    let size: CGSize
    let topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint
    /// The fraction of the width the plate's edges fade over (as baked by `bake.sh`).
    var fade: CGFloat { 0.16 }

    private static let all: [String: PlateGeometry] = {
        guard let url = Cinematic.url("Plates", "json"), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: PlateGeometry].self, from: data)) ?? [:]
    }()

    static func load(_ name: String) -> PlateGeometry? { all[name] }

    private enum CodingKeys: String, CodingKey { case size, topLeft, topRight, bottomRight, bottomLeft }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func point(_ key: CodingKeys) throws -> CGPoint {
            let v = try c.decode([CGFloat].self, forKey: key); return CGPoint(x: v[0], y: v[1])
        }
        let s = try c.decode([CGFloat].self, forKey: .size)
        size = CGSize(width: s[0], height: s[1])
        topLeft = try point(.topLeft); topRight = try point(.topRight)
        bottomRight = try point(.bottomRight); bottomLeft = try point(.bottomLeft)
    }
}

/// Hosts the content at the bar's size and projects it onto the plate's bar with a
/// `sublayerTransform`, which AppKit leaves alone (it manages each view's own transform).
private struct StageCanvas: NSViewRepresentable {
    let geometry: PlateGeometry
    let content: AnyView

    func makeNSView(context: Context) -> StageCanvasView { StageCanvasView(geometry: geometry, content: content) }

    func updateNSView(_ view: StageCanvasView, context: Context) {
        view.hosting.rootView = content
    }
}

final class StageCanvasView: NSView {
    let hosting: NSHostingView<AnyView>
    private let geometry: PlateGeometry
    private let fade = CAGradientLayer()

    init(geometry: PlateGeometry, content: AnyView) {
        self.geometry = geometry
        hosting = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        hosting.frame = CGRect(origin: .zero, size: TouchBarMetrics.size)
        hosting.wantsLayer = true
        addSubview(hosting)
        // The bar is lit from within: add its light to the dark glass rather than cover it.
        hosting.layer?.compositingFilter = CIFilter(name: "CIScreenBlendMode")
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        hosting.layer?.mask = fade
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard let layer, bounds.width > 0 else { return }
        let sx = bounds.width / geometry.size.width, sy = bounds.height / geometry.size.height
        // Plate pixels (y down) to this view's layer (y up).
        func place(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * sx, y: bounds.height - p.y * sy) }
        let h = TouchBarMetrics.size.height, w = TouchBarMetrics.size.width
        let anchor = CGPoint(x: layer.anchorPoint.x * bounds.width, y: layer.anchorPoint.y * bounds.height)
        let from = [CGPoint(x: 0, y: h), CGPoint(x: w, y: h), CGPoint(x: w, y: 0), CGPoint(x: 0, y: 0)]
        let to = [geometry.topLeft, geometry.topRight, geometry.bottomRight, geometry.bottomLeft].map(place)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = Homography.transform(
            from: from.map { CGPoint(x: $0.x - anchor.x, y: $0.y - anchor.y) },
            to: to.map { CGPoint(x: $0.x - anchor.x, y: $0.y - anchor.y) }
        )
        // Fade the content where the plate's edges fade, measured along the bar.
        fade.frame = hosting.bounds
        let left = to[0].x, right = to[1].x, span = max(right - left, 1)
        let edge = geometry.fade * bounds.width
        func u(_ x: CGFloat) -> NSNumber { NSNumber(value: Double((x - left) / span)) }
        let ramp: [CGFloat] = [0, 0.15, 0.5, 0.85, 1]
        let alphas: [CGFloat] = [0, 0.06, 0.5, 0.94, 1]
        fade.locations = ramp.map { u($0 * edge) } + ramp.reversed().map { u(bounds.width - $0 * edge) }
        fade.colors = (alphas + alphas.reversed()).map { NSColor.white.withAlphaComponent($0).cgColor }
        CATransaction.commit()
    }
}

/// The 3D transform that maps four points onto four others (a planar homography).
enum Homography {
    static func transform(from src: [CGPoint], to dst: [CGPoint]) -> CATransform3D {
        // Solve for h0…h7 in x' = (h0 x + h1 y + h2) / (h6 x + h7 y + 1), y' likewise with h3…h5.
        var m = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let x = Double(src[i].x), y = Double(src[i].y), u = Double(dst[i].x), v = Double(dst[i].y)
            m[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            m[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        for col in 0..<8 {
            let pivot = (col..<8).max { abs(m[$0][col]) < abs(m[$1][col]) }!
            m.swapAt(col, pivot)
            guard abs(m[col][col]) > 1e-12 else { return CATransform3DIdentity }
            for row in 0..<8 where row != col {
                let f = m[row][col] / m[col][col]
                for k in col..<9 { m[row][k] -= f * m[col][k] }
            }
        }
        let h = (0..<8).map { m[$0][8] / m[$0][$0] }
        var t = CATransform3DIdentity
        t.m11 = h[0]; t.m21 = h[1]; t.m41 = h[2]
        t.m12 = h[3]; t.m22 = h[4]; t.m42 = h[5]
        t.m14 = h[6]; t.m24 = h[7]; t.m44 = 1
        return t
    }
}

/// A looping recording of the bar, with a soft bloom like the OLED's.
struct BarVideo: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> GlowingVideoView { GlowingVideoView(url: Cinematic.url(name, "mp4")) }
    func updateNSView(_ view: GlowingVideoView, context: Context) {}
}

final class GlowingVideoView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let sharp = AVPlayerLayer()
    private let glow = AVPlayerLayer()

    init(url: URL?) {
        super.init(frame: .zero)
        if let url { looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)) }
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        wantsLayer = true
        layerUsesCoreImageFilters = true
        for layer in [glow, sharp] {
            layer.player = player
            layer.videoGravity = .resize
            self.layer?.addSublayer(layer)
        }
        glow.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 5])!]
        glow.opacity = 0.7
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        sharp.frame = bounds
        glow.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { player.pause() } else { player.play() }
    }
}

/// A bloom for drawn bar content, like `GlowingVideoView`'s.
struct BarGlow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background { content.blur(radius: 5).opacity(0.7) }
    }
}
