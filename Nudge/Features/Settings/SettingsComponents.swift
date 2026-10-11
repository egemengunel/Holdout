//
//  SettingsComponents.swift
//  Nudge
//

import AppKit
import SwiftUI

/// The top of each pane, the way System Settings opens a pane: symbol, title, one sentence.
/// A pane's symbol in white on a tile of its color, with a hairline edge, as in System Settings.
struct PaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        shape
            .fill(pane.tint.gradient)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PaneHeader<Accessory: View>: View {
    let pane: SettingsPane
    let text: String
    @ViewBuilder var accessory: Accessory

    /// The accessory (a `TouchBarStage`) runs edge to edge on the black page, and the title
    /// sits in its faded lower edge.
    var body: some View {
        VStack(spacing: 0) {
            accessory
            VStack(spacing: 8) {
                PaneIcon(pane: pane, size: 44)
                Text(pane.title).font(.title2.weight(.semibold))
                Text(text)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }
            .padding(.top, Accessory.self == EmptyView.self ? 12 : -30)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(pane: SettingsPane, text: String) {
        self.init(pane: pane, text: text) { EmptyView() }
    }
}

/// A numbered setup checklist, one row per step: done steps get a check, the first open one is
/// highlighted. Put it in a Form section (or a stack) for the rows' container.
struct StepList: View {
    let steps: [AgentGuide.Step]

    var body: some View {
        let current = steps.firstIndex { !$0.isDone }
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: step.isDone ? "checkmark.circle.fill" : "\(index + 1).circle\(index == current ? ".fill" : "")")
                    .foregroundStyle(step.isDone ? AnyShapeStyle(.green) : index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .imageScale(.large)
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
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }
}

/// A line to paste into a terminal, selectable, with a Copy button.
struct CopyableCode: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
        }
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
