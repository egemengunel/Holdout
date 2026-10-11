//
//  TouchBarPreview.swift
//  Holdout
//

import AppKit
import Combine
import SwiftUI

/// A SwiftUI copy of the Control Strip icon playing one of `IconPulse`'s states, for Settings.
/// It mirrors the motion in `IconPulse.animation` (the real icon is Core Animation layers).
struct IconPreview: View {
    let pulse: IconPulse
    /// Seconds of stillness between loops of the one-shot flashes.
    private let rest: TimeInterval = 1.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let (intensity, showsState) = Self.frame(pulse, at: t, rest: rest)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: Self.tint(pulse, intensity)))
                Image(systemName: showsState ? pulse.symbol : IconPulse.idleSymbol)
                    .font(.system(size: 15, weight: pulse.symbol == "checkmark" ? .semibold : .regular))
                    .foregroundStyle(.white)
            }
            .frame(width: 55, height: 30)
        }
    }

    private static func tint(_ pulse: IconPulse, _ intensity: Double) -> NSColor {
        guard let color = pulse.color?.usingColorSpace(.sRGB) else { return IconPulse.resting }
        return IconPulse.resting.blended(withFraction: intensity, of: color) ?? color
    }

    /// Color strength 0...1 at time `t`, and whether the state's own symbol (not the hand) shows.
    private static func frame(_ pulse: IconPulse, at t: TimeInterval, rest: TimeInterval) -> (Double, Bool) {
        func wave(_ phase: Double) -> Double { (1 - cos(phase * 2 * .pi)) / 2 }
        switch pulse {
        case .idle:
            return (0, true)
        case .working:
            return (0.35 + 0.65 * wave(t / 2.4), true)
        case .waiting:
            return (0.25 + 0.75 * wave(t / 0.9), true)
        case .alert:
            return (0.1 + 0.9 * (1 - wave(t / 0.5)), true)
        case .done:
            let length = IconPulse.doneDuration
            let local = t.truncatingRemainder(dividingBy: length + rest)
            guard local < length else { return (0, false) }
            if local < 1.5 {
                let phase = (local / 0.5).truncatingRemainder(dividingBy: 1)
                return (0.1 + 0.9 * (1 - wave(phase)), true)
            }
            return (1 - (local - 1.5) / 1.5, true)
        case .headsUp:
            let length = IconPulse.headsUpDuration
            let local = t.truncatingRemainder(dividingBy: length + rest)
            guard local < length else { return (0, false) }
            return (0.15 + 0.55 * (1 - wave(local / (length / 2))), true)
        }
    }
}

/// A mock of the Touch Bar with Holdout's strip open and the Control Strip icon playing `pulse`.
struct TouchBarPreview: View {
    let pulse: IconPulse
    /// Which tab shows as selected.
    var tab = "terminal"

    var body: some View {
        HStack(spacing: 8) {
            ForEach(["terminal", "iphone", "hammer", "memorychip"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 44, height: 30)
                    .background(Color.white.opacity(symbol == tab ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 12)
            IconPreview(pulse: pulse)
                .id(pulse.previewID)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity)
    }
}

private extension IconPulse {
    /// Restarts the preview's timeline when the state changes.
    var previewID: String { "\(self)" }
}
