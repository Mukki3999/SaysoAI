import Foundation

/// Runs `operation` but gives up after `seconds`, even if the operation never notices it was cancelled.
/// The on-device model can stall; this keeps the screen from sitting on a spinner forever.
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let gate = OneShot()
        let work = Task {
            do {
                let value = try await operation()
                if gate.claim() { continuation.resume(returning: value) }
            } catch {
                if gate.claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if gate.claim() {
                work.cancel()
                continuation.resume(throwing: ToolError("Sayso took too long to answer. Try again, or type it instead."))
            }
        }
    }
}

private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
