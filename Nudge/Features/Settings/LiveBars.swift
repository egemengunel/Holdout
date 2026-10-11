//
//  LiveBars.swift
//  Nudge
//

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
    Cinematic.url(name, "png").flatMap(NSImage.init(contentsOf:)).map { Image(nsImage: $0) }
}

/// The strip's scrolling area: clips, fades its trailing edge, and scrolls to keep the end of
/// its content in view, the way you'd swipe to your newest button.
private struct StripContent<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        let visible = StripMetrics.contentEnd - StripMetrics.contentStart
        content
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .offset(x: -max(0, width - visible + 6))
            .frame(width: visible, height: 30, alignment: .leading)
            .clipped()
            .mask {
                HStack(spacing: 0) {
                    Color.white
                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: StripMetrics.edgeFade)
                }
            }
            .animation(.snappy(duration: 0.45), value: width)
            .offset(x: StripMetrics.contentStart)
    }
}

/// The Project tab of a demo project, with these buttons after Build and Commit.
struct ProjectBar: View {
    struct Button: Hashable {
        let title: String
        let symbol: String
    }

    let buttons: [Button]

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black
            barImage("BarFixedProject")?.resizable().frame(width: 215, height: 30)
            StripContent {
                HStack(spacing: 0) {
                    barImage("BarProjectPills")?.resizable().frame(width: 244.5, height: 30)
                    ButtonCapsule(buttons: buttons)
                }
            }
        }
        .frame(width: TouchBarMetrics.size.width, height: TouchBarMetrics.size.height)
        .modifier(BarGlow())
    }
}

/// The Project tab's buttons: one momentary segmented control, as the bar draws it.
private struct ButtonCapsule: View {
    let buttons: [ProjectBar.Button]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(buttons, id: \.self) { button in
                HStack(spacing: 6.5) {
                    Image(systemName: button.symbol)
                        .font(.system(size: 16))
                    Text(button.title)
                        .font(.system(size: 15))
                        .fixedSize()
                }
                .padding(.horizontal, 7)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 0)
        .frame(height: 30)
        .foregroundStyle(.white)
        .background(Color(red: 0x47 / 255, green: 0x46 / 255, blue: 0x46 / 255), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.snappy(duration: 0.45), value: buttons)
    }
}

/// The Agents tab as sessions start one after another, then again.
struct AgentsArrivingBar: View {
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
