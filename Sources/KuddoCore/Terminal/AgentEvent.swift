import Foundation

/// A report from a coding agent speaking Warp's "cli-agent" protocol: an
/// OSC 777 notification titled `warp://cli-agent` whose body is one JSON
/// object, e.g.
///
///     {"v":1,"agent":"omp","event":"permission_request","tool_name":"bash",
///      "summary":"omp wants to run bash","session_id":"…","cwd":"…","project":"…"}
///
/// An agent only sends these where `WARP_CLI_AGENT_PROTOCOL_VERSION` is set,
/// which Kuddo does in every tab (`Pty.spawn`). That variable is what lets
/// one find Kuddo at all: omp picks its notification escape from a list of
/// terminals it knows by name, Kuddo isn't on it, and off the list all it
/// sends is a bell. With the variable set it sends these instead — and stops
/// sending its own "Complete" banners, so these replace them rather than
/// doubling up.
///
/// Most events are progress, not a request: `session_start`,
/// `prompt_submit`, `tool_complete` and `permission_replied` arrive on every
/// turn, and posting them would be a banner per tool call. Only the four
/// that leave the agent waiting on a person make a banner.
package struct AgentEvent: Equatable {
    /// The OSC 777 title that marks a body as one of these.
    package static let notificationTitle = "warp://cli-agent"

    package var event: String
    /// The agent's own name for itself, "omp".
    package var agent: String?
    package var toolName: String?
    /// A sentence the agent wrote for a person: "omp wants to run bash".
    package var summary: String?
    /// For `stop`, the start of the agent's last reply; for `stop_failure`,
    /// the error. omp sends at most 200 characters of it.
    package var response: String?
    package var errorType: String?

    /// nil for a body that isn't a JSON object with an `event`.
    package init?(json body: String) {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String
        else { return nil }
        func text(_ key: String) -> String? {
            guard let s = object[key] as? String else { return nil }
            let line = Self.oneLine(s)
            return line.isEmpty ? nil : line
        }
        self.event = event
        self.agent = text("agent")
        self.toolName = text("tool_name")
        self.summary = text("summary")
        self.response = text("response")
        self.errorType = text("error_type")
    }

    /// What the banner says under the tab's name: who, then what. nil for an
    /// event that doesn't ask anything of anyone. A nil subtitle leaves the
    /// banner to name the foreground process, as for any other notification.
    package var banner: (subtitle: String?, body: String)? {
        switch event {
        case "permission_request":
            // omp's summary names itself, "omp wants to run bash"; the
            // subtitle already does, so the body starts at the verb.
            let ask = summary.map(withoutAgentName)
                ?? toolName.map { "Wants to run \($0)" }
                ?? "Needs your permission"
            return (agent, ask)
        case "question_asked":
            return (agent, summary.map(withoutAgentName) ?? "Has a question for you")
        case "stop":
            return (said("finished"), response ?? "Your turn")
        case "stop_failure":
            let fallback = errorType == "aborted" ? "Aborted" : "Stopped with an error"
            return (said("stopped"), response ?? fallback)
        default:
            return nil
        }
    }

    /// "omp finished", or "Finished" from an agent that didn't give a name.
    private func said(_ verb: String) -> String {
        guard let agent else { return verb.prefix(1).uppercased() + verb.dropFirst() }
        return "\(agent) \(verb)"
    }

    /// "omp wants to run bash" → "Wants to run bash".
    private func withoutAgentName(_ s: String) -> String {
        guard let agent, s.count > agent.count + 1,
              s.lowercased().hasPrefix(agent.lowercased() + " ") else { return s }
        let rest = s.dropFirst(agent.count + 1)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    /// A banner line from markdown source. The prose stays and the structure
    /// goes: a heading only labels what follows it, and a table cut to fit a
    /// banner is a row of pipes ("| Project | What it is | |---|"), so both
    /// are dropped, along with fences and the marks ahead of a quote or list
    /// item. Emphasis and code ticks come off, whitespace and newlines
    /// collapse, and the length is kept to something a banner can show.
    static func oneLine(_ s: String) -> String {
        let prose = s.split(whereSeparator: \.isNewline).compactMap { raw -> Substring? in
            var line = Substring(raw).drop(while: { $0.isWhitespace })
            if line.hasPrefix("|") || line.hasPrefix("```") { return nil }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " { return nil }
            for mark in ["> ", "- ", "* ", "+ "] where line.hasPrefix(mark) {
                line = line.dropFirst(mark.count)
                break
            }
            return line
        }
        var text = prose.joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        text = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        let limit = 300
        if text.count > limit { text = String(text.prefix(limit)) + "…" }
        return text
    }
}
