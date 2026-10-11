//
//  IconPreview.swift
//  Nudge
//

import AppKit
import Combine
import SwiftUI

/// A SwiftUI copy of the Control Strip icon playing one of `IconPulse`'s states, for Settings.
/// It mirrors the motion in `IconPulse.animation` (the real icon is Core Animation layers).
struct IconPreview: View {
    let pulse: IconPulse
    /// 6 matches the Touch Bar's buttons; a container can round it further to sit concentrically.
    var cornerRadius: CGFloat = 6
    /// Seconds of stillness between loops of the one-shot flashes.
    private let rest: TimeInterval = 1.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let (intensity, showsState) = Self.frame(pulse, at: t, rest: rest)
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
