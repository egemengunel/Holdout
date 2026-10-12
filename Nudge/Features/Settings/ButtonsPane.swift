//
//  ButtonsPane.swift
//  Nudge
//

import SwiftUI

/// The Project tab's buttons: the built-in Build and Commit, your own, and a Claude Code mod's.
struct ButtonsPane: View {
    @State private var custom = NudgeSettings.customActions
    @State private var editing: CustomAction?
    @State private var isNew = false
    @State private var editingBuiltIn: ProjectStripView.Action?
    @State private var mods: [ClaudeMods.Mod] = []
    @State private var modCommands: [ClaudeMods.Command] = []
    @AppStorage(NudgeSettings.builtInHiddenKey("build")) private var buildHidden = false
    @AppStorage(NudgeSettings.builtInHiddenKey("commit")) private var commitHidden = false

    private var preview: [(title: String, symbol: String)] {
        let builtIn: [ProjectStripView.Action] = [.build, .commit].filter { NudgeSettings.showsBuiltIn($0.id) }
        return builtIn.map { ($0.title, $0.symbol) } + custom.map { ($0.title, $0.symbol) }
    }

    var body: some View {
        Form {
            Section {} footer: {
                PaneHeader(pane: .buttons, text: "Buttons on the Touch Bar's Project tab. Each one sends a prompt to the agent you're working with, for whatever project it's in.") {
                    TouchBarStage(plate: .strip) {
                        ProjectBar(buttons: preview.map { ProjectBar.Button(title: $0.title, symbol: $0.symbol) })
                    }
                }
            }

            Section {
                ForEach(custom) { action in
                    CustomActionRow(action: action) {
                        isNew = false
                        editing = action
                    } delete: {
                        custom.removeAll { $0.id == action.id }
                    }
                }
                .onMove { custom.move(fromOffsets: $0, toOffset: $1) }

                addMenu
            } header: {
                Text("Your buttons")
            } footer: {
                Text("Shown for every project, after the built-in buttons. Drag to reorder.")
            }

            Section {
                builtInRow(.build, hidden: $buildHidden)
                builtInRow(.commit, hidden: $commitHidden)
            } header: {
                Text("Built in")
            } footer: {
                Text("Build shows in Xcode projects, Commit in git repositories.")
            }

            Section {
                if modCommands.isEmpty {
                    Text(mods.isEmpty
                         ? "Claude Code mods you install, in ~/.claude/mods or CLAUDE_CODE_PLUGIN_DIRS, show up here with their slash commands."
                         : "\(mods.map(\.name).formatted(.list(type: .and))) \(mods.count == 1 ? "adds" : "add") no slash commands yet. They show up here once a Claude Code session has loaded them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(modCommands) { command in
                        Toggle(isOn: Binding(
                            get: { custom.contains { $0.runs(command) } },
                            set: { on in
                                if on { custom.append(CustomAction(command)) } else { custom.removeAll { $0.runs(command) } }
                            }
                        )) {
                            Text("/" + command.name)
                            Text([command.mod, command.description].filter { !$0.isEmpty }.joined(separator: " · "))
                        }
                    }
                }
            } header: {
                Text("From Claude Code mods")
            } footer: {
                if !modCommands.isEmpty {
                    Text("Each one runs its slash command in the chat, in Claude Code sessions. Turned on, it's one of your buttons above, to rename or reorder.")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: custom) { _, value in NudgeSettings.customActions = value }
        // The welcome guide can add buttons while this is open.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let saved = NudgeSettings.customActions
            if saved != custom { custom = saved }
        }
        .task {
            mods = ClaudeMods.installed
            modCommands = ClaudeMods.commands
        }
        .sheet(item: $editing) { action in
            CustomActionEditor(action: action, isNew: isNew) { saved in
                if let index = custom.firstIndex(where: { $0.id == saved.id }) {
                    custom[index] = saved
                } else {
                    custom.append(saved)
                }
            } delete: {
                custom.removeAll { $0.id == action.id }
            }
        }
        .sheet(item: $editingBuiltIn) { action in
            BuiltInPromptEditor(action: action)
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Blank Button") { add(CustomAction(title: "", symbol: "sparkles", prompt: "")) }
            Divider()
            Section("Start from") {
                ForEach(CustomAction.presets, id: \.title) { preset in
                    Button {
                        add(preset)
                    } label: {
                        Label(preset.title, systemImage: preset.symbol)
                    }
                }
            }
        } label: {
            Label("Add Button", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func add(_ template: CustomAction) {
        var action = template
        action.id = UUID().uuidString
        isNew = true
        editing = action
    }

    private func builtInRow(_ action: ProjectStripView.Action, hidden: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                Text(NudgeSettings.promptOverride(for: action.id) == nil ? "Default prompt" : "Custom prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit Prompt…") { editingBuiltIn = action }
                .controlSize(.small)
            Toggle("Show", isOn: Binding(get: { !hidden.wrappedValue }, set: { hidden.wrappedValue = !$0 }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

extension ProjectStripView.Action: Identifiable {}

private struct CustomActionRow: View {
    let action: CustomAction
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .frame(width: 20)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                Text(action.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Edit…", action: edit)
                .controlSize(.small)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

/// Placeholders a prompt can use, inserted by the chips under the prompt field.
private let placeholders: [(token: String, meaning: String)] = [
    ("{project}", "Project name"),
    ("{root}", "Project folder"),
    ("{repo}", "Repository name"),
    ("{branch}", "Current branch"),
]

private struct CustomActionEditor: View {
    @State private var action: CustomAction
    let isNew: Bool
    let save: (CustomAction) -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(action: CustomAction, isNew: Bool, save: @escaping (CustomAction) -> Void, delete: @escaping () -> Void) {
        _action = State(initialValue: action)
        self.isNew = isNew
        self.save = save
        self.delete = delete
    }

    private var canSave: Bool {
        !action.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TouchBarButtonsPreview(buttons: [(action.title.isEmpty ? "Title" : action.title, action.symbol)])
                }
                Section {
                    TextField("Title", text: $action.title, prompt: Text("Short, like Test or Ship"))
                    SymbolPicker(symbol: $action.symbol)
                }
                Section {
                    TextEditor(text: $action.prompt)
                        .font(.body)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                    HStack(spacing: 6) {
                        ForEach(placeholders, id: \.token) { item in
                            Button(item.token) { action.prompt += (action.prompt.last.map { $0.isWhitespace } ?? true ? "" : " ") + item.token }
                                .help("Inserts the \(item.meaning.lowercased())")
                                .controlSize(.small)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                } header: {
                    Text("Prompt")
                } footer: {
                    Text("Sent to the agent as if you typed it. Placeholders are filled in for the project you're in.")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        delete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Button" : "Save") {
                    action.title = action.title.trimmingCharacters(in: .whitespaces)
                    save(action)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
    }
}

/// A grid of likely symbols, plus a field for any SF Symbol name.
private struct SymbolPicker: View {
    @Binding var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Symbol") {
                TextField("Symbol", text: $symbol, prompt: Text("SF Symbol name"))
                    .labelsHidden()
                    .frame(maxWidth: 200)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 12), spacing: 6) {
                ForEach(CustomAction.symbols, id: \.self) { name in
                    Button {
                        symbol = name
                    } label: {
                        Image(systemName: name)
                            .frame(width: 30, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(symbol == name ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.5)))
                            )
                            .foregroundStyle(symbol == name ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
        }
    }
}

/// The wording of Build or Commit; empty means Nudge's default.
private struct BuiltInPromptEditor: View {
    let action: ProjectStripView.Action
    @AppStorage private var text: String
    @Environment(\.dismiss) private var dismiss

    init(action: ProjectStripView.Action) {
        self.action = action
        _text = AppStorage(wrappedValue: "", NudgeSettings.promptKey(action.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(action.defaultTemplate)
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Label(action.title, systemImage: action.symbol)
                } footer: {
                    Text("Leave empty for the default. {project}, {root}, {repo} and {branch} stand for the current project. A Claude Code mod words its own Build and Commit.")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Use Default") { text = "" }
                    .disabled(text.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 380)
    }
}
