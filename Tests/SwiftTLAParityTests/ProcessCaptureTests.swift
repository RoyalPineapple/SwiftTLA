import Darwin
import Foundation
import Testing
@testable import UpstreamParity

@Suite(.serialized)
struct ProcessCaptureTests {
  @Test("capture preserves output larger than a pipe buffer on both streams")
  func capturesCompleteOutput() throws {
    let result = try executeProcess(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "dd if=/dev/zero bs=65536 count=4 2>/dev/null; { dd if=/dev/zero bs=65536 count=4 2>/dev/null; } >&2; exit 7"],
      directory: FileManager.default.temporaryDirectory, timeout: 5)
    #expect(result.status == 7)
    #expect(result.stdout == String(repeating: "\0", count: 262_144))
    #expect(result.stderr == String(repeating: "\0", count: 262_144))
  }

  @Test("an inherited output descriptor does not delay capture after process exit")
  func doesNotWaitForInheritedDescriptors() throws {
    let started = ContinuousClock.now
    let result = try executeProcess(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "/bin/sleep 30 & printf '%s' \"$!\""],
      directory: FileManager.default.temporaryDirectory, timeout: 2)
    let child = try #require(Int32(result.stdout))
    defer { _ = Darwin.kill(child, SIGKILL) }
    #expect(result.status == 0)
    #expect(started.duration(to: .now) < .seconds(2))
  }

  @Test("invalid UTF-8 output fails capture instead of returning replacement text", arguments: ["1", "2"])
  func rejectsUndecodableOutput(stream: String) throws {
    #expect(throws: (any Error).self) {
      try executeProcess(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "printf '\\377' >&\(stream)"],
        directory: FileManager.default.temporaryDirectory, timeout: 2)
    }
  }

  @Test("timeout preserves output already written to both streams")
  func retainsOutputOnTimeout() throws {
    do {
      _ = try executeProcess(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "printf out; printf err >&2; exec /bin/sleep 30"],
        directory: FileManager.default.temporaryDirectory, timeout: 0.25)
      Issue.record("Expected the process deadline to expire")
    } catch let error as TLCProcessError {
      #expect(error == .timedOut(partialStdout: "out", partialStderr: "err"))
    }
  }
}
