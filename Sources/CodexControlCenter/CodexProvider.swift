import Foundation

private final class RPCResponseAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var storedResponse: Data?

    func consume(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                (object["id"] as? NSNumber)?.intValue == 2
            else { continue }
            storedResponse = Data(line)
            return true
        }
        return false
    }

    var response: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedResponse
    }
}

public struct CodexProvider: UsageProvider {
    public let id = "codex"
    public let displayName = "Codex"
    public var timeout: TimeInterval
    public var executableOverride: URL?

    public init(timeout: TimeInterval = 15, executableOverride: URL? = nil) {
        self.timeout = timeout
        self.executableOverride = executableOverride
    }

    public func fetch() throws -> ProviderSnapshot {
        let executable = try executableOverride ?? Self.findCodexExecutable()
        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardOutput = outputPipe
        process.standardInput = inputPipe
        process.standardError = errorPipe

        let accumulator = RPCResponseAccumulator()
        let completed = DispatchSemaphore(value: 0)

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            if accumulator.consume(chunk) {
                completed.signal()
            }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw UsageError.launchFailed(error.localizedDescription)
        }

        let messages = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_control_center","title":"Codex Control Center","version":"0.4.15"},"capabilities":{}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/rateLimits/read","id":2,"params":{}}"#
        ].joined(separator: "\n") + "\n"

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data(messages.utf8))
        } catch {
            process.terminate()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw UsageError.launchFailed(error.localizedDescription)
        }

        let waitResult = completed.wait(timeout: .now() + timeout)
        outputPipe.fileHandleForReading.readabilityHandler = nil
        inputPipe.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }

        guard waitResult == .success else { throw UsageError.timedOut }
        let finalResponse = accumulator.response
        guard let finalResponse else { throw UsageError.malformedResponse }
        return try CodexResponseParser.parse(data: finalResponse)
    }

    static func findCodexExecutable() throws -> URL {
        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = environmentPath.split(separator: ":").map {
            URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
        }
        let fixedCandidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]

        if let match = (pathCandidates + fixedCandidates).first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) {
            return match
        }
        throw UsageError.codexNotFound
    }
}
