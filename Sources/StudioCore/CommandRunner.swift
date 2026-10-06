import Foundation
import Darwin

public struct CommandFailure: LocalizedError, Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }

    public var errorDescription: String? {
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "Command exited with status \(exitCode)." :
            "Command exited with status \(exitCode).\n\(detail)"
    }
}

/// Executes one native tool at a time, without a shell. Output callbacks arrive on
/// a background queue. Environment values override the inherited environment.
@MainActor
public final class CommandRunner {
    public var isRunning: Bool { execution != nil }
    private var execution: CommandExecution?

    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        directory: URL? = nil,
        environment: [String: String]? = nil,
        onOutput: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        guard execution == nil else { throw RunnerError.alreadyRunning }
        let current = CommandExecution(executable: executable, arguments: arguments,
                                       directory: directory, environment: environment,
                                       onOutput: onOutput)
        execution = current
        defer { execution = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                current.start(continuation)
            }
        } onCancel: {
            current.cancel()
        }
    }

    /// Cancels only this runner's command and its verified, dedicated process group.
    public func cancel() { execution?.cancel() }

    private enum RunnerError: LocalizedError {
        case alreadyRunning
        var errorDescription: String? { "A command is already running." }
    }
}

/// All mutable state is confined to queue. Neither Process callbacks nor task
/// cancellation touch state directly. This keeps launch/exit/cancel races ordered.
private final class CommandExecution: @unchecked Sendable {
    private static let captureLimit = 1024 * 1024
    private let queue = DispatchQueue(label: "SwiftRenderStudio.CommandRunner")
    private let process = Process()
    private let pipe = Pipe()
    private let onOutput: @Sendable (String) -> Void
    private var continuation: CheckedContinuation<String, Error>?
    private var reader: DispatchSourceRead?
    private var descriptor: Int32 = -1
    private var processID: pid_t = 0
    private var ownsProcessGroup = false
    private var cancelled = false
    private var finished = false
    private var tail = Data()
    private var incompleteUTF8 = Data()

    init(executable: URL, arguments: [String], directory: URL?,
         environment: [String: String]?, onOutput: @escaping @Sendable (String) -> Void) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in value }
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        self.onOutput = onOutput
    }

    func start(_ continuation: CheckedContinuation<String, Error>) {
        queue.async { [self] in
            self.continuation = continuation
            if cancelled { finish(.failure(CancellationError())); return }
            do {
                // A duplicate descriptor is owned exclusively by the read source.
                // Nonblocking reads cannot hang when a descendant inherits the pipe.
                descriptor = dup(pipe.fileHandleForReading.fileDescriptor)
                guard descriptor >= 0 else { throw posixError() }
                let flags = fcntl(descriptor, F_GETFL)
                guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                    let error = posixError()
                    close(descriptor)
                    descriptor = -1
                    throw error
                }
                let fd = descriptor
                let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
                source.setEventHandler { [weak self] in self?.drain() }
                source.setCancelHandler { close(fd) }
                reader = source
                source.resume()
                try pipe.fileHandleForReading.close()
                process.terminationHandler = { [weak self] process in
                    guard let self else { return }
                    let status = process.terminationStatus
                    self.queue.async { self.didExit(status: status) }
                }
                try process.run()
                processID = process.processIdentifier
                // Foundation normally creates a group for the launched process.
                // Try establishing one if needed; never signal an inherited group.
                if getpgid(processID) != processID { _ = setpgid(processID, processID) }
                ownsProcessGroup = processID > 0 && getpgid(processID) == processID
                try? pipe.fileHandleForWriting.close()
            } catch {
                finish(.failure(error))
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            guard !finished else { return }
            cancelled = true
            guard process.isRunning else { return }
            signal(SIGTERM)
            queue.asyncAfter(deadline: .now() + 0.5) { [self] in
                guard !finished, cancelled, process.isRunning else { return }
                signal(SIGKILL)
            }
        }
    }

    private func signal(_ value: Int32) {
        guard processID > 0 else { return }
        if ownsProcessGroup {
            _ = Darwin.kill(-processID, value)
        } else if process.isRunning {
            _ = Darwin.kill(processID, value)
        }
    }

    private func didExit(status: Int32) {
        guard !finished else { return }
        // The original process group ID remains reserved while its descendants
        // exist, even after the leader exits. Finish cancellation of that group
        // now instead of leaving an orphan compiler holding the output pipe open.
        if cancelled && ownsProcessGroup { signal(SIGKILL) }
        drain()
        let output = capturedOutput()
        if cancelled {
            finish(.failure(CancellationError()))
        } else if status == 0 {
            finish(.success(output))
        } else {
            finish(.failure(CommandFailure(exitCode: status, output: output)))
        }
    }

    private func drain() {
        guard descriptor >= 0, !finished else { return }
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        var consumed = 0
        // Yield between batches so a tool flooding stdout cannot starve cancel().
        while consumed < Self.captureLimit {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                consumed += count
                let chunk = Data(buffer.prefix(count))
                tail.append(chunk)
                if tail.count > Self.captureLimit {
                    tail.removeFirst(tail.count - Self.captureLimit)
                }
                stream(chunk)
            } else if count == -1 && errno == EINTR {
                continue
            } else {
                // EOF or EAGAIN. Never wait for descendant-owned writers to close.
                if count == 0 {
                    reader?.cancel()
                    reader = nil
                    descriptor = -1
                }
                break
            }
        }
    }

    private func stream(_ chunk: Data) {
        incompleteUTF8.append(chunk)
        let bytes = [UInt8](incompleteUTF8.suffix(4))
        var keep = 0
        for distance in 0..<bytes.count {
            let byte = bytes[bytes.count - 1 - distance]
            if byte & 0xC0 == 0x80 { continue }
            let required = byte & 0xE0 == 0xC0 ? 2 : byte & 0xF0 == 0xE0 ? 3 : byte & 0xF8 == 0xF0 ? 4 : 1
            if required > distance + 1 { keep = distance + 1 }
            break
        }
        let end = incompleteUTF8.count - keep
        if end > 0 {
            onOutput(String(decoding: incompleteUTF8.prefix(end), as: UTF8.self))
            incompleteUTF8.removeFirst(end)
        }
    }

    private func capturedOutput() -> String {
        // If a capped tail starts partway through a UTF-8 scalar, omit that partial
        // scalar rather than invent a replacement character at the truncation edge.
        let bytes = tail.drop(while: { $0 & 0xC0 == 0x80 })
        return String(decoding: bytes, as: UTF8.self)
    }

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        if !incompleteUTF8.isEmpty {
            onOutput(String(decoding: incompleteUTF8, as: UTF8.self))
            incompleteUTF8.removeAll()
        }
        process.terminationHandler = nil
        reader?.cancel()
        reader = nil
        descriptor = -1
        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
        let completion = continuation
        continuation = nil
        completion?.resume(with: result)
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
