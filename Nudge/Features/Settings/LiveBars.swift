//
//  LiveBars.swift
//  Nudge
//

import AVFoundation
import SwiftUI

// Bar content for `TouchBarStage`, laid out at the Touch Bar's size (1004 × 30 pt). The fixed
// parts are pieces of real captures of Nudge's strip (`Design/Film`); only what changes with
// your choices is drawn, matched to the real controls.

/// Where the strip's content scrolls: after the ✕ and the tabs, up to where the bar stops
/// showing it (measured on the real strip).
private enum StripMetrics {
    static let contentStart: CGFloat = 215.5
    static let contentEnd: CGFloat = 677
    /// The real strip fades its scrolling content out over its last 22 pt.
    static let edgeFade: CGFloat = 22
}

private func barImage(_ name: String) -> Image? {
    Cinematic.image(name, "png").map { Image(nsImage: $0) }
}

/// The strip's scrolling area: clips and fades its trailing edge, as the bar does.
private struct StripContent<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .fixedSize()
            .frame(width: StripMetrics.contentEnd - StripMetrics.contentStart, height: 30, alignment: .leading)
            .clipped()
            .mask {
                HStack(spacing: 0) {
                    Color.white
                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: StripMetrics.edgeFade)
                }
            }
            .offset(x: StripMetrics.contentStart)
    }
}

/// The Project tab of a demo project, laid out as `ProjectStripView` does it: the project chip,
/// then these buttons (Build and Commit included, if shown), squeezed to fit what the bar shows, then the last build.
struct ProjectBar: View {
    struct Button: Hashable {
        let title: String
        let symbol: String
    }

    let buttons: [Button]

    /// The two pills of the capture, as they sit in `BarProjectPills` (in points).
    private static let chipWidth: CGFloat = 142.5
    private static let buildPill: (x: CGFloat, width: CGFloat) = (148.5, 90)
    /// The strip's spacing between its items.
    private static let spacing: CGFloat = 6

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black
            barImage("BarFixedProject")?.resizable().frame(width: 215, height: 30)
            StripContent {
                HStack(spacing: Self.spacing) {
                    pills.frame(width: Self.chipWidth, alignment: .leading).clipped()
                    if !buttons.isEmpty {
                        ButtonCapsule(buttons: buttons, room: StripMetrics.contentEnd - StripMetrics.contentStart - StripMetrics.edgeFade - Self.chipWidth - Self.spacing)
                    }
                    pills.offset(x: -Self.buildPill.x).frame(width: Self.buildPill.width, alignment: .leading).clipped()
                }
            }
        }
        .frame(width: TouchBarMetrics.size.width, height: TouchBarMetrics.size.height)
        .modifier(BarGlow())
    }

    private var pills: some View {
        barImage("BarProjectPills")?.resizable().frame(width: 244.5, height: 30)
    }
}

/// The Project tab's buttons: one momentary segmented control, as the bar draws it. Like the
/// real one, buttons lose their label from the last one back when they don't fit in `room`.
private struct ButtonCapsule: View {
    let buttons: [ProjectBar.Button]
    let room: CGFloat

    var body: some View {
        let labeled = Self.labeledCount(buttons, room: room)
        HStack(spacing: 0) {
            ForEach(Array(buttons.enumerated()), id: \.element) { index, button in
                HStack(spacing: 6.5) {
                    Image(systemName: button.symbol)
                        .font(.system(size: 16))
                    if index < labeled {
                        Text(button.title)
                            .font(.system(size: 15))
                            .fixedSize()
                    }
                }
                .padding(.horizontal, index < labeled ? 7 : 0)
                .frame(width: index < labeled ? nil : Self.iconWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(height: 30)
        .foregroundStyle(.white)
        .background(Color(red: 0x47 / 255, green: 0x46 / 255, blue: 0x46 / 255), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.snappy(duration: 0.45), value: buttons)
        .animation(.snappy(duration: 0.45), value: labeled)
    }

    /// An icon-only button's width, as `ProjectStripView` sets it.
    private static let iconWidth: CGFloat = 42

    /// How many buttons, from the first, keep their label.
    private static func labeledCount(_ buttons: [ProjectBar.Button], room: CGFloat) -> Int {
        let font = NSFont.systemFont(ofSize: 15)
        let widths = buttons.map { button in
            let symbol = NSImage(systemSymbolName: button.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))?.size.width ?? 20
            return 14 + symbol + 6.5 + (button.title as NSString).size(withAttributes: [.font: font]).width
        }
        var labeled = buttons.count
        while labeled > 0, widths.prefix(labeled).reduce(0, +) + CGFloat(buttons.count - labeled) * iconWidth > room {
            labeled -= 1
        }
        return labeled
    }
}

/// The Agents tab as sessions start one after another: the real recording when there is one
/// (`Design/Film/record-strip.sh`), else real session pills from a capture, arriving in turn.
struct AgentsArrivingBar: View {
    var body: some View {
        if Cinematic.url("BarAgentsArriving", "mp4") != nil {
            BarVideo(name: "BarAgentsArriving")
        } else {
            ArrivingPills()
        }
    }
}

private struct ArrivingPills: View {
    private static let pills: [(name: String, width: CGFloat)] = [
        ("BarPillCursor", 195.5), ("BarPillCodex", 196), ("BarPillClaude", 53.5),
    ]
    @State private var shown = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black
            barImage("BarFixedAgents")?.resizable().frame(width: 215, height: 30)
            HStack(spacing: 8.5) {
                ForEach(Array(Self.pills.prefix(shown).enumerated()), id: \.offset) { _, pill in
                    barImage(pill.name)?.resizable().frame(width: pill.width, height: 30)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .offset(x: StripMetrics.contentStart)
        }
        .frame(width: TouchBarMetrics.size.width, height: TouchBarMetrics.size.height)
        .modifier(BarGlow())
        .task {
            while !Task.isCancelled {
                for count in [0, 1, 2, 3] {
                    withAnimation(.snappy(duration: 0.5)) { shown = count }
                    try? await Task.sleep(for: .seconds(count == 3 ? 3.5 : 1.1))
                }
            }
        }
    }
}

/// Recordings of the bar one after another, each played through once and dissolving into the next.
struct CyclingBar: View {
    var clips = ["BarWorking", "BarWaiting", "BarBuildSucceeded", "BarSessionDone", "BarBuildFailed", "BarIdle"]
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BarVideo(name: clips[index])
            .id(index)
            .frame(width: TouchBarMetrics.size.width, height: TouchBarMetrics.size.height)
            .transition(.opacity)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    let seconds = await Self.duration(of: clips[index])
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.5)) { index = (index + 1) % clips.count }
                }
            }
    }

    private static func duration(of clip: String) async -> Double {
        if let known = durations[clip] { return known }
        guard let url = Cinematic.url(clip, "mp4"),
              let seconds = try? await AVURLAsset(url: url).load(.duration).seconds,
              seconds.isFinite, seconds > 1
        else { return 4 }
        durations[clip] = min(seconds, 8)
        return min(seconds, 8)
    }

    private static var durations: [String: Double] = [:]
}

/// A recording of an ordinary app's bar with the status light playing over Nudge's icon, for
/// the states that can't be recorded on demand (a real memory crisis, a runaway process).
struct PulseOverIdleBar: View {
    let pulse: IconPulse

    var body: some View {
        ZStack(alignment: .topLeading) {
            BarVideo(name: "BarIdle")
            IconPreview(pulse: pulse)
                .offset(x: 715, y: 0)
        }
        .frame(width: TouchBarMetrics.size.width, height: TouchBarMetrics.size.height)
    }
}
