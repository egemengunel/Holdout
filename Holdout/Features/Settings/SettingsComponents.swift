//
//  SettingsComponents.swift
//  Holdout
//

import AppKit
import SwiftUI

/// A white symbol on a colored rounded square, like System Settings' sidebar icons.
struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tint.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
    }
}

/// The card at the top of each pane: what this pane is for, in a sentence.
struct PaneHeader<Accessory: View>: View {
    let pane: SettingsPane
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                SymbolTile(symbol: pane.symbol, tint: pane.tint, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.title).font(.title2.weight(.semibold))
                    Text(text)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            accessory
        }
        .padding(.vertical, 6)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(pane: SettingsPane, text: String) {
        self.init(pane: pane, text: text) { EmptyView() }
    }
}

/// A numbered setup checklist. Done steps get a check; the first open one is highlighted.
struct StepList: View {
    let steps: [AgentGuide.Step]

    var body: some View {
        let current = steps.firstIndex { !$0.isDone }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    marker(index: index, done: step.isDone, current: index == current)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.title)
                            .fontWeight(index == current ? .medium : .regular)
                            .foregroundStyle(step.isDone ? .secondary : .primary)
                        if let detail = step.detail {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let code = step.code {
                            CopyableCode(text: code)
                        }
                        if let button = step.button, !step.isDone || step.buttonStaysWhenDone {
                            Button(button.title, action: button.action)
                                .controlSize(.small)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func marker(index: Int, done: Bool, current: Bool) -> some View {
        ZStack {
            Circle()
                .fill(done ? AnyShapeStyle(Color.green) : current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            if done {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            } else {
                Text("\(index + 1)").font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundStyle(done || current ? .white : .secondary)
        .frame(width: 18, height: 18)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
    }
}

/// A line to paste into a terminal, with a copy button.
struct CopyableCode: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Connected / needs approval / not connected, as a small colored capsule.
struct StatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// The agent's own app icon when it's installed, otherwise its bundled logo or a neutral tile.
struct AgentIcon: View {
    let agent: AgentInstaller.Agent
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let icon = agent.appIcon {
                Image(nsImage: icon).resizable()
            } else if let logo = agent.logoAsset {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous).strokeBorder(.black.opacity(0.1)))
                    .overlay(Image(logo).resizable().scaledToFit().padding(size * 0.18))
            } else {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "terminal").foregroundStyle(.secondary))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A Touch Bar–style row of buttons, for previewing the Project tab's actions.
struct TouchBarButtonsPreview: View {
    let buttons: [(title: String, symbol: String)]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    HStack(spacing: 5) {
                        Image(systemName: button.symbol)
                        Text(button.title).lineLimit(1)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.16))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
