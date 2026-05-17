import Foundation

final class OutputBuffer {
    private let lock = NSLock()
    private(set) var stdout = ""
    private(set) var stderr = ""
    private(set) var exceededLimit = false
    let maxBytes: Int

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func appendStdout(_ text: String) {
        append(text, isError: false)
    }

    func appendStderr(_ text: String) {
        append(text, isError: true)
    }

    private func append(_ text: String, isError: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !exceededLimit else { return }
        let currentBytes = stdout.utf8.count + stderr.utf8.count
        if currentBytes + text.utf8.count > maxBytes {
            exceededLimit = true
            let marker = "\n[mentu-recipes] output limit exceeded\n"
            if isError { stderr += marker } else { stdout += marker }
            return
        }
        if isError { stderr += text } else { stdout += text }
    }

    func snapshot() -> (stdout: String, stderr: String, exceeded: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr, exceededLimit)
    }
}
