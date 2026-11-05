import Foundation

/// One environment variable being added or changed in Settings, and what
/// saving it does to the environment it belongs to. The editor
/// (`EnvironmentEditor`) holds one of these while a row is open; nothing
/// reaches the saved environment until `applied(to:)` does.
struct EnvEdit: Equatable {
    /// The saved name this row was opened on; nil for a new variable.
    var original: String?
    var name: String
    var value: String

    /// A new, empty variable.
    static let new = EnvEdit(original: nil, name: "", value: "")

    /// A saved variable, opened for editing.
    static func editing(_ name: String, in env: [String: String]) -> EnvEdit {
        EnvEdit(original: name, name: name, value: env[name] ?? "")
    }

    /// The name as it will be saved.
    var key: String { name.trimmingCharacters(in: .whitespaces) }

    /// Why this can't be saved into `env`, said for the person typing; nil
    /// when it can be — and while nothing has been typed yet, since a row
    /// just opened isn't wrong. A name is what goes before the `=` in
    /// `NAME=value`, so it can't hold one, or a space; and taking a name
    /// another variable already has would overwrite that one without a word.
    func problem(in env: [String: String]) -> String? {
        if key.isEmpty { return value.isEmpty ? nil : "A variable needs a name." }
        if key.contains("=") || key.contains(where: \.isWhitespace) {
            return "Names have no “=” and no spaces."
        }
        if key != original, env[key] != nil { return "“\(key)” is already set." }
        return nil
    }

    /// Whether Save does anything, and nothing wrong.
    func canSave(in env: [String: String]) -> Bool {
        !key.isEmpty && problem(in: env) == nil && applied(to: env) != env
    }

    /// `env` with this saved into it. A rename takes the old name out.
    func applied(to env: [String: String]) -> [String: String] {
        var env = env
        if let original { env[original] = nil }
        env[key] = value
        return env
    }
}
