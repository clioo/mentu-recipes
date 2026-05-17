import Foundation

public enum ProcessRunner {
    public static func findExecutable(_ name: String) -> String? {
        if name.contains("/") && FileManager.default.isExecutableFile(atPath: name) {
            return name
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":").map(String.init) {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func run(
        executable: String,
        arguments: [String],
        env: [String: String],
        workingDirectory: URL,
        timeout: Int,
        maxOutputBytes: Int,
        eventSink: @escaping (String) -> Void
    ) async throws -> AdapterResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let buffer = OutputBuffer(maxBytes: maxOutputBytes)

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer.appendStdout(text)
            eventSink(text)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer.appendStderr(text)
            eventSink(text)
        }

        try process.run()

        let exitTask = Task {
            await waitForExit(process)
        }

        let timedOut: Bool
        if timeout > 0 {
            timedOut = !(await completedBeforeTimeout(exitTask, seconds: timeout))
        } else {
            await exitTask.value
            timedOut = false
        }

        if timedOut {
            process.terminate()
            if !(await completedBeforeTimeout(exitTask, seconds: 2)) {
                kill(process.processIdentifier, SIGKILL)
                await exitTask.value
            }
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        let snapshot = buffer.snapshot()
        let code = timedOut ? Int32(124) : process.terminationStatus
        let stderrText = timedOut ? snapshot.stderr + "\n[mentu-recipes] timeout after \(timeout)s\n" : snapshot.stderr

        return AdapterResult(
            stdout: snapshot.stdout,
            stderr: stderrText,
            exitCode: code,
            providerCompleted: !timedOut && code == 0,
            inputTokens: nil,
            outputTokens: nil
        )
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    private static func completedBeforeTimeout(_ exitTask: Task<Void, Never>, seconds: Int) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await exitTask.value
                return true
            }
            group.addTask {
                let duration = UInt64(max(seconds, 0)) * 1_000_000_000
                try? await Task.sleep(nanoseconds: duration)
                return false
            }
            let completed = await group.next() ?? false
            group.cancelAll()
            return completed
        }
    }
}
