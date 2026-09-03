import os

/// A tiny lock-protected, Sendable box for handing values across the main /
/// render thread boundary without SwiftUI observation or data races.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Value>
    init(_ value: Value) { lock = OSAllocatedUnfairLock(initialState: value) }
    var value: Value {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
