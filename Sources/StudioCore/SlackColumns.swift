import Foundation

/// The columns every board tag shares. The last one counts as done.
public enum SlackColumns {
    public static let all = ["Todo", "In progress", "Blocked", "Done"]
    public static let done = "Done"

    /// The standard column a spelling variant stands for ("Inprogress", "in-progress", "DONE"), or nil when it matches none.
    public static func canonical(_ status: String) -> String? {
        switch status.lowercased().filter({ !$0.isWhitespace && $0 != "-" }) {
        case "todo": return "Todo"
        case "inprogress": return "In progress"
        case "blocked": return "Blocked"
        case "done": return "Done"
        default: return nil
        }
    }
}
