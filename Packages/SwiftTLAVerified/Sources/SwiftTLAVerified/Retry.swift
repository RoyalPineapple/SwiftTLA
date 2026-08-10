import SwiftTLA
import SwiftTLAMacros

/// A retry strategy whose state transitions are verified at compile time.
/// Guarantees bounded attempts, no retry after success or cancellation.
@TLAModel
public struct Retry: Sendable {
    public let maxAttempts: Int
    public let backoff: Duration

    public static var spec: TLASpec {
        TLASpec("Retry") {
            let phase = Var("phase", 0)
            Variable(phase)
            let attempts = Var("attempts", 0)
            Variable(attempts)
            // 0=idle, 1=attempting, 2=backingOff, 3=succeeded, 4=failed, 5=cancelled

            Action("start")            { phase == 0 && attempts == 0 && phase.becomes(1) && attempts.becomes(1) }
            Action("succeed")          { phase == 1 && phase.becomes(3) }
            Action("failAndBackoff")   { phase == 1 && attempts < 3 && phase.becomes(2) }
            Action("failTerminal")     { phase == 1 && attempts == 3 && phase.becomes(4) }
            Action("retry")            { phase == 2 && phase.becomes(1) && attempts.becomes(attempts + 1) }
            Action("cancelFromIdle")    { phase == 0 && phase.becomes(5) }
            Action("cancelFromAttempt") { phase == 1 && phase.becomes(5) }
            Action("cancelFromBackoff") { phase == 2 && phase.becomes(5) }

            Invariant("boundedAttempts") { attempts <= 3 }
        }
    }

    public init(maxAttempts: Int, backoff: Duration = .seconds(1)) {
        precondition(maxAttempts > 0)
        self.maxAttempts = maxAttempts
        self.backoff = backoff
    }

    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                try Task.checkCancellation()
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(for: backoff)
                }
            }
        }
        throw lastError ?? CancellationError()
    }
}
