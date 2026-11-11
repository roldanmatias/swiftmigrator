import Foundation

/// Number of listings synced per batch.
/// R1: `var` → `let`. No writes anywhere in the package or its tests.
public let syncBatchSize = 10

public enum SyncConfig {
    public static let maxRetries = 3
    public static let pollInterval: TimeInterval = 30
}

// R1: `syncAttempts` was written from background queues and never read: a real
// data race on dead state. Removed (behavior-neutral).
