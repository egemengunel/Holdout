//
//  Cinematic.swift
//  Nudge
//

import AVFoundation
import SwiftUI

/// Renders of a MacBook from above with Nudge's real Touch Bar recordings on it, made in Blender
/// (see `Design/Film`). Their edges are baked to dissolve into pure black, so they sit borderless
/// on a black page.
enum Cinematic {
    static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
    }

    static func image(_ name: String) -> NSImage? {
        url(name, "jpg").flatMap(NSImage.init(contentsOf:))
    }
}

/// A baked still, full width.
struct CinematicStill: View {
    let name: String

    var body: some View {
        if let image = Cinematic.image(name) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}

/// A baked film looping silently, or its poster when Reduce Motion is on.
struct CinematicFilm: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || Cinematic.url(name, "mp4") == nil {
            CinematicStill(name: name + "Poster")
        } else if let url = Cinematic.url(name, "mp4") {
            LoopingVideo(url: url)
                .aspectRatio(Self.aspect(of: url), contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    private static func aspect(of url: URL) -> CGFloat {
        guard let size = Cinematic.image(url.deletingPathExtension().lastPathComponent + "Poster")?.size, size.height > 0 else { return 1440 / 615 }
        return size.width / size.height
    }
}

private struct LoopingVideo: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerView { PlayerView(url: url) }
    func updateNSView(_ view: PlayerView, context: Context) {}
}

/// Plays while it's in a window and pauses when it leaves, so a closed guide costs nothing.
final class PlayerView: NSView {
    private let player = AVQueuePlayer()
    private let looper: AVPlayerLooper

    init(url: URL) {
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        super.init(frame: .zero)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { player.pause() } else { player.play() }
    }
}
