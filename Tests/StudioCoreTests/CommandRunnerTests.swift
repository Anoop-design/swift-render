import Foundation
import XCTest
@testable import StudioCore

final class CommandRunnerTests: XCTestCase {
    @MainActor
    func testArgumentsWithSpacesAreNotShellEvaluated() async throws {
        let runner = CommandRunner()
        let argument = "a space; $(echo should-not-run) 💛"
        let output = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"),
                                          arguments: ["%s", argument])
        XCTAssertEqual(output, argument)
        XCTAssertFalse(runner.isRunning)
    }

    @MainActor
    func testNonzeroExitIncludesStandardError() async throws {
        let runner = CommandRunner()
        do {
            _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                     arguments: ["-c", "printf 'compile failed' >&2; exit 7"])
            XCTFail("Expected CommandFailure")
        } catch let error as CommandFailure {
            XCTAssertEqual(error.exitCode, 7)
            XCTAssertEqual(error.output, "compile failed")
        }
        XCTAssertFalse(runner.isRunning)
    }

    @MainActor
    func testLargeOutputStreamsFullyButCaptureIsBounded() async throws {
        let runner = CommandRunner()
        let received = OutputCounter()
        let output = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/awk"),
            arguments: ["BEGIN { for (i=0; i<25000; i++) printf \"01234567890123456789012345678901234567890123456789012345678901234567890123456789\\n\"; printf \"THE END\" }"],
            onOutput: { received.append($0) })
        XCTAssertEqual(received.byteCount, 25000 * 81 + 7)
        XCTAssertGreaterThan(received.chunks, 1)
        XCTAssertEqual(output.utf8.count, 1024 * 1024)
        XCTAssertTrue(output.hasSuffix("THE END"))
    }

    @MainActor
    func testCancellationTerminatesCommandAndAllowsReuse() async throws {
        let runner = CommandRunner()
        let started = expectation(description: "command emitted output")
        let task = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                 arguments: ["-c", "printf ready; exec /bin/sleep 30"],
                                 onOutput: { _ in started.fulfill() })
        }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(runner.isRunning)
        let before = Date()
        runner.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertLessThan(Date().timeIntervalSince(before), 3)
        XCTAssertFalse(runner.isRunning)
        let output = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["reused"])
        XCTAssertEqual(output, "reused")
    }

    @MainActor
    func testTaskCancellationAndLaunchFailureDoNotLeaveRunnerBusy() async throws {
        let runner = CommandRunner()
        let task = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertFalse(runner.isRunning)
        do {
            _ = try await runner.run(executable: URL(fileURLWithPath: "/not-a-real-executable"), arguments: [])
            XCTFail("Expected launch failure")
        } catch { }
        XCTAssertFalse(runner.isRunning)
    }

    @MainActor
    func testTermResistantCommandIsKilledAfterGracePeriod() async throws {
        let runner = CommandRunner()
        let started = expectation(description: "TERM handler installed")
        let task = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; printf ready; while :; do /bin/sleep 1; done"],
                onOutput: { _ in started.fulfill() })
        }
        await fulfillment(of: [started], timeout: 3)
        let before = Date()
        runner.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertLessThan(Date().timeIntervalSince(before), 3)
        XCTAssertFalse(runner.isRunning)
    }

    @MainActor
    func testInheritedOutputPipeDoesNotDelayParentCompletion() async throws {
        let runner = CommandRunner()
        let before = Date()
        // The short-lived background child inherits stdout after its parent exits.
        // Waiting for pipe EOF would make an otherwise finished command hang.
        let output = try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "/bin/sleep 2 & printf complete; exit 0"])
        XCTAssertEqual(output, "complete")
        XCTAssertLessThan(Date().timeIntervalSince(before), 1)
    }
}

private final class OutputCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0
    private var count = 0
    var byteCount: Int { lock.lock(); defer { lock.unlock() }; return bytes }
    var chunks: Int { lock.lock(); defer { lock.unlock() }; return count }
    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        bytes += value.utf8.count
        count += 1
    }
}
