import KuddoCore
import SwiftUI

/// What every new tab's environment holds beyond the one Kuddo was started
/// with: the user's variables, edited Edit-then-Save (`EnvironmentEditor`),
/// and Kuddo's own under them, listed from the code that sets them.
struct EnvironmentPane: View {
    @ObservedObject private var store = ThemeStore.shared
    @FocusState.Binding var focus: SettingsField?

    init(focus: FocusState<SettingsField?>.Binding) {
        self._focus = focus
    }

    var body: some View {
        Form {
            Section("Your Variables") {
                EnvironmentEditor(saved: store.settings.environment,
                                  emptyNote: "No variables of your own yet.",
                                  anchor: .tabEnvAdd,
                                  focus: $focus,
                                  save: { store.settings.environment = $0 })
                Text("Set in every tab opened from now on, whatever its profile. "
                     + "Yours replace Kuddo's variables of the same name, and a "
                     + "profile's own replace yours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Set by Kuddo") {
                ForEach(presets, id: \.name) { variable in
                    PresetVariableRow(name: variable.name, value: variable.value,
                                      replaced: replacedNames.contains(variable.name))
                }
                Text("Every tab gets these, on top of the environment Kuddo was "
                     + "started with.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// The variables Kuddo sets in every tab, from the list the PTY uses.
    private var presets: [(name: String, value: String)] {
        Pty.baseEnvironment.map { entry in
            let name = entry.prefix { $0 != "=" }
            return (String(name), String(entry.dropFirst(name.count + 1)))
        }
    }

    /// Kuddo's variables that one of the user's saved ones replaces.
    private var replacedNames: Set<String> {
        Set(store.settings.environment.keys)
    }
}

/// One of Kuddo's own variables, read-only: the name on the left and its
/// value on the right, as a Settings row reads. Struck through, and saying
/// why, once one of the user's rows replaces it.
private struct PresetVariableRow: View {
    let name: String
    let value: String
    let replaced: Bool

    var body: some View {
        LabeledContent {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .strikethrough(replaced)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        } label: {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .strikethrough(replaced)
                .textSelection(.enabled)
            if replaced {
                Text("Replaced by yours")
            }
        }
        .foregroundStyle(replaced ? HierarchicalShapeStyle.secondary : .primary)
    }
}
