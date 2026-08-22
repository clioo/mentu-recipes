import Foundation

/// The runner's only route to stdout for progress. It owns the palette choice
/// and the write lock, so parallel steps cannot interleave half a line, and
/// every line goes through the `ProgressRender` grammar.
final class RunProgress: @unchecked Sendable {
    private let quiet: Bool
    private let palette: ProgressRender.Palette
    private let lock = NSLock()

    init(quiet: Bool) {
        self.quiet = quiet
        self.palette = quiet ? .plain : .forStandardOutput
    }

    // MARK: - Steps

    func stepStarted(index: Int, total: Int, label: String, engine: String, attempt: Int) {
        let outcome = attempt > 1 ? "retry \(attempt)" : "running"
        write(ProgressRender.stepLine(
            state: .running, index: index, total: total, label: label,
            engine: engine, elapsed: "0s",
            outcome: "\(palette.cyan)\(outcome)\(palette.reset)", palette: palette))
    }

    func stepFinished(index: Int, total: Int, label: String, engine: String,
                      seconds: Int, complete: Bool, detail: String?) {
        let state: ProgressRender.State = complete ? .ok : .failed
        let color = complete ? palette.green : palette.red
        var outcome = "\(color)\(complete ? "ok" : "failed")\(palette.reset)"
        if let detail, !detail.isEmpty {
            outcome += " \(palette.dim)· \(detail)\(palette.reset)"
        }
        write(ProgressRender.stepLine(
            state: state, index: index, total: total, label: label,
            engine: engine, elapsed: ProgressRender.duration(seconds: seconds),
            outcome: outcome, palette: palette))
    }

    func stepSkipped(index: Int, total: Int, label: String, reason: String) {
        write(ProgressRender.stepLine(
            state: .skipped, index: index, total: total, label: label,
            engine: "", elapsed: "",
            outcome: "\(palette.yellow)\(reason)\(palette.reset)", palette: palette))
    }

    func stepFailed(index: Int, total: Int, label: String, message: String) {
        write(ProgressRender.stepLine(
            state: .failed, index: index, total: total, label: label,
            engine: "", elapsed: "",
            outcome: "\(palette.red)\(message)\(palette.reset)", palette: palette))
    }

    // MARK: - Layers

    /// A child recipe inside a pipeline, parallel or compound run.
    func layer(state: ProgressRender.State, label: String, seconds: Int?,
               deps: [String], waitingOn: [String], outcome: String?) {
        let color: String
        switch state {
        case .ok:      color = palette.green
        case .failed:  color = palette.red
        case .running: color = palette.cyan
        case .skipped: color = palette.yellow
        case .queued:  color = palette.dim
        }
        write(ProgressRender.layerLine(
            state: state, label: label, kind: "recipe",
            elapsed: seconds.map { ProgressRender.duration(seconds: $0) } ?? "",
            deps: deps, waitingOn: waitingOn,
            outcome: outcome.map { "\(color)\($0)\(palette.reset)" }, palette: palette))
    }

    // MARK: - Bars

    /// Work completed so far, over the unit named by `noun`.
    func progressBar(done: Int, total: Int, noun: String) {
        write("\(ProgressRender.bar(done: done, total: total, palette: palette)) "
            + "\(palette.dim)\(done)/\(total) \(noun)\(palette.reset)")
    }

    // MARK: - Raw

    /// Adapter output, passed through untouched.
    func stream(_ text: String) {
        guard !quiet else { return }
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    private func write(_ line: String) {
        guard !quiet else { return }
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
