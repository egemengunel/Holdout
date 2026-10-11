//
//  StatusLightPane.swift
//  Holdout
//

import SwiftUI

/// What the Control Strip icon can show, in priority order, with the optional ones switchable.
/// Selecting a row plays it on the preview, so this is the legend and the settings in one.
struct StatusLightPane: View {
    private struct Signal: Identifiable {
        let id: String
        let pulse: IconPulse
        let title: String
        let detail: String
        /// The setting that turns it off; nil when it's always on.
        let key: String?
    }

    private static let persistent: [Signal] = [
        Signal(id: "memory", pulse: .alert, title: "Memory is critical", detail: "Red until you open the Mac tab. Only when Activity Monitor's graph turns red.", key: HoldoutSettings.Key.macDistress),
        Signal(id: "waiting", pulse: .waiting, title: "A session needs you", detail: "Amber while an agent waits for an answer or permission.", key: nil),
    ]

    private static let flashes: [Signal] = [
        Signal(id: "done", pulse: .done(at: 0), title: "A session finished", detail: "A green check, then back to the hand.", key: HoldoutSettings.Key.sessionDone),
        Signal(id: "build", pulse: .done(at: 0, symbol: "hammer.fill"), title: "A build finished", detail: "Green when it succeeds, red when it fails.", key: HoldoutSettings.Key.buildResult),
        Signal(id: "cpu", pulse: .headsUp(at: 0, symbol: "cpu"), title: "A process hogs the CPU", detail: "Two soft orange flashes, at most every 30 minutes.", key: HoldoutSettings.Key.cpuHeadsUp),
    ]

    private static let ambient: [Signal] = [
        Signal(id: "working", pulse: .working, title: "Agents are working", detail: "Slow blue breathing, with how many.", key: nil),
        Signal(id: "idle", pulse: .idle, title: "All quiet", detail: "The hand. Tap it to open the strip.", key: nil),
    ]

    @State private var selected = "waiting"

    private var playing: IconPulse {
        (Self.persistent + Self.flashes + Self.ambient).first { $0.id == selected }?.pulse ?? .idle
    }

    var body: some View {
        Form {
            Section {
                TouchBarPreview(pulse: playing)
            } footer: {
                Text("Holdout's icon in the Control Strip is a status light. Color says what happened; motion says how urgent. Point at a signal to see it.")
            }
            section("Stays on until you look", Self.persistent)
            section("Flashes once", Self.flashes)
            section("In the background", Self.ambient)
        }
        .formStyle(.grouped)
    }

    private func section(_ title: String, _ signals: [Signal]) -> some View {
        Section(title) {
            ForEach(signals) { signal in
                SignalRow(signal: signal)
                    .contentShape(Rectangle())
                    .onHover { if $0 { selected = signal.id } }
            }
        }
    }

    private struct SignalRow: View {
        let signal: Signal
        @AppStorage private var isOn: Bool

        init(signal: Signal) {
            self.signal = signal
            _isOn = AppStorage(wrappedValue: true, signal.key ?? "statusLight.unused")
        }

        var body: some View {
            HStack(spacing: 12) {
                StaticIcon(pulse: signal.pulse)
                    .opacity(signal.key == nil || isOn ? 1 : 0.35)
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.title)
                    Text(signal.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if signal.key != nil {
                    Toggle(signal.title, isOn: $isOn)
                        .labelsHidden()
                } else {
                    Text("Always")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// The icon at full color, still: rows show what a state looks like, the preview shows how it moves.
private struct StaticIcon: View {
    let pulse: IconPulse

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: pulse.color ?? IconPulse.resting))
            Image(systemName: pulse.symbol)
                .font(.system(size: 12, weight: pulse.symbol == "checkmark" ? .semibold : .regular))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 22)
    }
}
