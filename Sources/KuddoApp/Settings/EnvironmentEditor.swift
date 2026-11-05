import AppKit
import SwiftUI

/// An environment as NAME / value rows, each changed on purpose: a row's
/// pencil opens it for editing and only its Save writes it; its trash asks
/// before removing it. Environment variables carry tokens and paths every
/// new tab depends on, so nothing is written as it's typed — a half-typed
/// PATH would otherwise be what the next tab got.
///
/// One row is open at a time; the other rows' buttons wait until it's saved
/// or cancelled. Return in it saves and Esc cancels (`SettingsEdits`), and
/// leaving the pane, or the profile, with a row open drops what was typed,
/// the same as Cancel.
///
/// These are rows of a Form section.
struct EnvironmentEditor: View {
    /// What is saved now.
    let saved: [String: String]
    /// Shown while there is nothing saved.
    let emptyNote: String
    /// The indexed control, Add Variable, which search lands on. The rows'
    /// own stops are hung off it (`SettingsDynamicStops`).
    let anchor: SettingsField
    @FocusState.Binding var focus: SettingsField?
    let save: ([String: String]) -> Void

    /// The row open for editing, if any.
    @State private var editing: EnvEdit?
    /// This editor, to `SettingsEdits` and `SettingsDynamicStops`.
    @State private var token = UUID()

    /// Wide enough for the long names agents and toolchains use,
    /// WARP_CLI_AGENT_PROTOCOL_VERSION among them.
    private let nameWidth: CGFloat = 220

    private var names: [String] { saved.keys.sorted() }

    var body: some View {
        if names.isEmpty && editing == nil {
            Text(emptyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            columnHeads
        }
        ForEach(names, id: \.self) { name in
            if editing?.original == name {
                editingRow
            } else {
                savedRow(name)
            }
        }
        if editing != nil && editing?.original == nil {
            editingRow
        }
        addButton
            // On the one row that is always there: modifiers on a group of
            // rows apply to each row, and a row going away would clear them.
            .onAppear { SettingsDynamicStops.shared.set(stops, for: anchor, owner: token) }
            .onChange(of: stops) { _, new in
                SettingsDynamicStops.shared.set(new, for: anchor, owner: token)
            }
            .onDisappear {
                SettingsDynamicStops.shared.clear(anchor, owner: token)
                close()
            }
    }

    // MARK: rows

    /// Column heads, once, over the rows. A grouped Form turns a field's
    /// title into a label beside it, which put "NAME" and "value" inline with
    /// what was typed — so the fields carry no title of their own.
    private var columnHeads: some View {
        HStack(spacing: 6) {
            Text("Name").frame(width: nameWidth, alignment: .leading)
            Text("Value")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func savedRow(_ name: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .frame(width: nameWidth, alignment: .leading)
            Text(saved[name] ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button { open(name) } label: { Image(systemName: "pencil") }
                .help("Edit \(name)")
                .focusableControl(.envEdit(name), focus: $focus, onActivate: { open(name) })
            Button { confirmRemove(name) } label: { Image(systemName: "trash") }
                .help("Remove \(name)")
                .focusableControl(.envDelete(name), focus: $focus,
                                  onActivate: { confirmRemove(name) })
        }
        .buttonStyle(.borderless)
        .disabled(editing != nil)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var editingRow: some View {
        HStack(spacing: 6) {
            TextField("Name", text: editingBinding(\.name), prompt: Text(""))
                .frame(width: nameWidth)
                .focused($focus, equals: .envName)
                .onSubmit(commit)
            TextField("Value", text: editingBinding(\.value), prompt: Text(""))
                .focused($focus, equals: .envValue)
                .onSubmit(commit)
            // AppKit buttons: SwiftUI wouldn't take focus from the fields
            // to its own buttons beside them (`SettingsKeyViews`).
            SettingsButton(title: "Cancel", field: .envCancel, action: cancel)
                .fixedSize()
            SettingsButton(title: "Save", field: .envSave, prominent: true,
                           enabled: canSave, action: commit)
                .fixedSize()
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
        if let problem = editing?.problem(in: saved) {
            Text(problem)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var addButton: some View {
        HStack {
            Spacer()
            Button("Add Variable", action: add)
                .disabled(editing != nil)
                .focusableControl(anchor, focus: $focus, onActivate: add)
        }
    }

    // MARK: state

    private func editingBinding(_ field: WritableKeyPath<EnvEdit, String>) -> Binding<String> {
        Binding(get: { editing?[keyPath: field] ?? "" },
                set: { editing?[keyPath: field] = $0 })
    }

    private var canSave: Bool { editing?.canSave(in: saved) ?? false }

    /// Tab order: each saved row's Edit and Remove, then Add Variable. With
    /// a row open, only that row: its fields, Cancel, and Save once it can —
    /// everything else is disabled until it closes.
    private var stops: [SettingsField] {
        if editing != nil {
            return [.envName, .envValue, .envCancel] + (canSave ? [.envSave] : [])
        }
        return names.flatMap { [SettingsField.envEdit($0), .envDelete($0)] } + [anchor]
    }

    private func open(_ name: String) {
        editing = .editing(name, in: saved)
        SettingsEdits.begin(token, cancel: cancel)
        // The value is what changes most; the name is a Tab back.
        moveFocus(to: .envValue)
    }

    private func add() {
        editing = .new
        SettingsEdits.begin(token, cancel: cancel)
        moveFocus(to: .envName)
    }

    private func commit() {
        guard let editing, editing.canSave(in: saved) else { return }
        save(editing.applied(to: saved))
        close()
        moveFocus(to: .envEdit(editing.key))
    }

    private func cancel() {
        let original = editing?.original
        close()
        moveFocus(to: original.map { .envEdit($0) } ?? anchor)
    }

    private func close() {
        editing = nil
        SettingsEdits.end(token)
    }

    /// Asks first: a removed variable is gone from every tab opened after.
    private func confirmRemove(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(name)”?"
        alert.informativeText = "Tabs opened from now on won't have it. "
            + "Tabs already open keep theirs."
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.enableButtonKeyboardNavigation()
        alert.appendKeyEquivalentHints()
        let env = saved
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else {
                moveFocus(to: .envDelete(name))
                return
            }
            var remaining = env
            remaining[name] = nil
            save(remaining)
            moveFocus(to: anchor)
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    /// Next pass: a control this pass adds doesn't exist yet to take focus.
    private func moveFocus(to field: SettingsField) {
        DispatchQueue.main.async { focus = field }
    }
}
