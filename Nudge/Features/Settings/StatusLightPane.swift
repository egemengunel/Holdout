//
//  StatusLightPane.swift
//  Nudge
//

import SwiftUI

/// What the Control Strip icon can show, in priority order, with the optional ones switchable.
/// Clicking a row plays it on the preview (and in the row), so this is the legend and the settings
/// in one. Once the header scrolls away, a floating copy of the icon keeps playing it at the top.
struct StatusLightPane: View {
    fileprivate struct Signal: Identifiable {
        let id: String
        let pulse: IconPulse
        let title: String
        let detail: String
        /// The setting that turns it off; nil when it's always on.
        let key: String?
    }

    private static let persistent: [Signal] = [
        Signal(id: "memory", pulse: .alert, title: "Memory is critical", detail: "Red until you open the Mac tab. Only when Activity Monitor's graph turns red.", key: NudgeSettings.Key.macDistress),
        Signal(id: "waiting", pulse: .waiting, title: "A session needs you", detail: "Amber while an agent waits for an answer or permission.", key: nil),
    ]

    private static let flashes: [Signal] = [
        Signal(id: "done", pulse: .done(at: 0), title: "A session finished", detail: "A green check, then back to the hand.", key: NudgeSettings.Key.sessionDone),
        Signal(id: "build", pulse: .done(at: 0, symbol: "hammer.fill"), title: "A build finished", detail: "Green when it succeeds, red when it fails.", key: NudgeSettings.Key.buildResult),
        Signal(id: "cpu", pulse: .headsUp(at: 0, symbol: "cpu"), title: "A process hogs the CPU", detail: "Two soft orange flashes, at most every 30 minutes.", key: NudgeSettings.Key.cpuHeadsUp),
    ]

    private static let ambient: [Signal] = [
        Signal(id: "working", pulse: .working, title: "Agents are working", detail: "Slow blue breathing, with how many.", key: nil),
        Signal(id: "idle", pulse: .idle, title: "All quiet", detail: "The hand. Tap it to open the strip.", key: nil),
    ]

    @State private var selected = "waiting"
    @State private var headerVisible = true

    private var current: Signal? {
        (Self.persistent + Self.flashes + Self.ambient).first { $0.id == selected }
    }

    private var playing: IconPulse { current?.pulse ?? .idle }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .statusLight, text: "Nudge's icon in the Control Strip is a status light. Color says what happened; motion says how urgent. Click a signal to see it.") {
                    TouchBarStage(plate: .right) { Self.bar(for: selected, pulse: playing) }
                }
                .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY > 24 } action: { headerVisible = $0 }
            }
            section("Stays on until you look", Self.persistent)
            section("Flashes once", Self.flashes)
            section("In the background", Self.ambient)
        }
        .formStyle(.grouped)
        .overlay(alignment: .top) {
            if !headerVisible, let current {
                NowPlaying(signal: current)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: headerVisible)
    }

    /// The bar for a signal: a real recording of it, or for the two that can't be staged on
    /// demand (a memory crisis, a runaway process), the icon playing over an ordinary app's bar.
    @ViewBuilder
    private static func bar(for id: String, pulse: IconPulse) -> some View {
        let clip: String? = switch id {
        case "waiting": "BarWaiting"
        case "done": "BarSessionDone"
        case "build": "BarBuildSucceeded"
        case "working": "BarWorking"
        case "idle": "BarIdle"
        case "memory": Cinematic.url("BarAlert", "mp4") == nil ? nil : "BarAlert"
        case "cpu": Cinematic.url("BarCPU", "mp4") == nil ? nil : "BarCPU"
        default: nil
        }
        if let clip {
            BarVideo(name: clip).id(clip)
        } else {
            PulseOverIdleBar(pulse: pulse).id(id)
        }
    }

    private func section(_ title: String, _ signals: [Signal]) -> some View {
        Section(title) {
            ForEach(signals) { signal in
                SignalRow(signal: signal, isSelected: signal.id == selected)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = signal.id }
                    .accessibilityAddTraits(signal.id == selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selected = signal.id }
            }
        }
    }

    private struct SignalRow: View {
        let signal: Signal
        let isSelected: Bool
        @AppStorage private var isOn: Bool

        init(signal: Signal, isSelected: Bool) {
            self.signal = signal
            self.isSelected = isSelected
            _isOn = AppStorage(wrappedValue: true, signal.key ?? "statusLight.unused")
        }

        var body: some View {
            HStack(spacing: 12) {
                Group {
                    if isSelected {
                        IconPreview(pulse: signal.pulse)
                            .scaleEffect(0.73)
                            .frame(width: 40, height: 22)
                    } else {
                        StaticIcon(pulse: signal.pulse)
                    }
                }
                .opacity(signal.key == nil || isOn ? 1 : 0.35)
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                }
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

/// The selected signal, floating over the pane once the header's preview has scrolled out of sight.
private struct NowPlaying: View {
    let signal: StatusLightPane.Signal

    var body: some View {
        let content = HStack(spacing: 10) {
            // Concentric with the capsule: its radius (21) less the 6 pt inset.
            IconPreview(pulse: signal.pulse, cornerRadius: 15)
                .id(signal.id)
            Text(signal.title)
                .font(.callout.weight(.medium))
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)

        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
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
