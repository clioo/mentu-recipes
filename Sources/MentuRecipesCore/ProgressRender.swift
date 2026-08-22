import Foundation

/// One grammar for every progress line the runner prints.
///
/// Before this existed the runner printed `▶ label · backend` and nothing else:
/// no position in the recipe, no state vocabulary, no elapsed column, and no
/// outcome once the step ended. Sequence, pipeline, parallel and compound
/// recipes all render through here now, so a line means the same thing wherever
/// it appears.
///
/// Layout is column-exact: every field is padded as plain text and only then
/// wrapped in color, so ANSI codes never shift a column. Tests render with
/// `Palette.plain` and assert on the exact string.
enum ProgressRender {

    // MARK: - State vocabulary

    /// The five states any unit of work can be in. Nothing prints a state glyph
    /// that is not one of these.
    enum State: String, Sendable, CaseIterable {
        case queued, running, ok, failed, skipped

        var glyph: String {
            switch self {
            case .queued:  return "\u{23F8}"   // ⏸
            case .running: return "\u{23F5}"   // ⏵
            case .ok:      return "\u{2713}"   // ✓
            case .failed:  return "\u{2717}"   // ✗
            case .skipped: return "\u{2298}"   // ⊘
            }
        }

        func color(_ p: Palette) -> String {
            switch self {
            case .queued:  return p.dim
            case .running: return p.cyan
            case .ok:      return p.green
            case .failed:  return p.red
            case .skipped: return p.yellow
            }
        }
    }

    // MARK: - Palette

    /// Color codes as data, so one layout implementation serves both the terminal
    /// and the tests.
    struct Palette: Sendable {
        let dim: String, reset: String, green: String
        let red: String, cyan: String, yellow: String, bold: String

        static let plain = Palette(dim: "", reset: "", green: "",
                                   red: "", cyan: "", yellow: "", bold: "")
        static let ansi = Palette(
            dim: "\u{1b}[2m", reset: "\u{1b}[0m", green: "\u{1b}[32m",
            red: "\u{1b}[91m", cyan: "\u{1b}[36m", yellow: "\u{1b}[33m", bold: "\u{1b}[1m")

        /// Color only when stdout is a terminal, so redirected run logs stay plain.
        static var forStandardOutput: Palette {
            isatty(STDOUT_FILENO) != 0 ? .ansi : .plain
        }
    }

    // MARK: - Column widths

    /// Fixed columns. A line is readable down the page only if these never move.
    enum Col {
        static let counter = 7   // "12/99  "
        static let label = 24
        static let engine = 12
        static let elapsed = 7
        static let bar = 20
    }

    // MARK: - Primitives

    /// Pad to `width`, truncating with an ellipsis when the text does not fit.
    static func pad(_ text: String, _ width: Int) -> String {
        guard text.count <= width else {
            return String(text.prefix(max(width - 1, 0))) + "\u{2026}"
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    /// Right-align within `width` (durations read better on the right edge).
    static func padLeft(_ text: String, _ width: Int) -> String {
        guard text.count < width else { return text }
        return String(repeating: " ", count: width - text.count) + text
    }

    /// Duration style shared with the summary lines: 3s, 4m12s, 1h07m.
    static func duration(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m\(String(format: "%02d", seconds % 60))s" }
        return "\(seconds / 3600)h\(String(format: "%02d", seconds % 3600 / 60))m"
    }

    /// Determinate progress: a fixed-width bar plus the percent it represents.
    /// Fixed width is the point. A bar whose length depends on the step count
    /// cannot be compared between two lines.
    ///
    /// `leadingEdge` replaces the first pending cell, which is how a runner can
    /// animate a cell filling without changing the line's width.
    static func bar(done: Int, total: Int, width: Int = Col.bar,
                    palette p: Palette = .ansi, leadingEdge: String? = nil) -> String {
        let safeTotal = max(total, 1)
        let clamped = min(max(done, 0), safeTotal)
        let filledCells = Int((Double(clamped) / Double(safeTotal) * Double(width)).rounded())
        let pending = width - filledCells
        var out = "\(p.cyan)\(String(repeating: "\u{2588}", count: filledCells))\(p.reset)"
        if let edge = leadingEdge, pending > 0 {
            out += "\(p.cyan)\(edge)\(p.reset)"
            out += "\(p.dim)\(String(repeating: "\u{2591}", count: pending - 1))\(p.reset)"
        } else {
            out += "\(p.dim)\(String(repeating: "\u{2591}", count: pending))\(p.reset)"
        }
        let pct = Int((Double(clamped) / Double(safeTotal) * 100).rounded())
        return out + " \(p.dim)\(padLeft("\(pct)%", 4))\(p.reset)"
    }

    // MARK: - Lines

    /// A step line: state, position in the recipe, what ran it, how long, what happened.
    ///
    ///     ⏵ 1/2    produce                 shell             3s  running
    ///     ✓ 1/2    produce                 shell             4s  ok
    ///     ✗ 2/2    demo-verify             shell            12s  exit 1
    static func stepLine(state: State, index: Int, total: Int, label: String,
                         engine: String, elapsed: String, outcome: String,
                         palette p: Palette = .ansi) -> String {
        let counter = total > 0 ? "\(index)/\(total)" : ""
        var line = "\(state.color(p))\(state.glyph)\(p.reset) "
        line += "\(p.bold)\(pad(counter, Col.counter))\(p.reset)"
        line += pad(label, Col.label)
        line += "\(p.dim)\(pad(engine, Col.engine))\(p.reset)"
        line += "\(p.dim)\(padLeft(elapsed, Col.elapsed))\(p.reset)  "
        line += outcome
        return line
    }

    /// A layer line inside a compound or pipeline block. `waitingOn` non-empty
    /// means the layer cannot start yet and names exactly what it is waiting for,
    /// which is the question a stalled graph always raises.
    ///
    ///     ✓ prep                   recipe         1m20s  ok
    ///     ⏵ variants               recipe            13s  running
    ///     ⏸ join                   recipe             0s  waiting on variants
    static func layerLine(state: State, label: String, kind: String,
                          elapsed: String, deps: [String], waitingOn: [String],
                          outcome: String? = nil, palette p: Palette = .ansi) -> String {
        let tail: String
        if !waitingOn.isEmpty {
            tail = "\(p.dim)waiting on \(waitingOn.joined(separator: ", "))\(p.reset)"
        } else if let outcome {
            tail = outcome
        } else if deps.isEmpty {
            tail = "\(p.dim)no deps\(p.reset)"
        } else {
            tail = "\(p.dim)after \(deps.joined(separator: ", "))\(p.reset)"
        }
        var line = "\(state.color(p))\(state.glyph)\(p.reset) "
        line += pad(label, Col.label)
        line += "\(p.dim)\(pad(kind, Col.engine))\(p.reset)"
        line += "\(p.dim)\(padLeft(elapsed, Col.elapsed))\(p.reset)  "
        line += tail
        return line
    }
}
