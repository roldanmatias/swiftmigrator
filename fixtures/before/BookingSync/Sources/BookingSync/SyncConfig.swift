import Foundation

/// Number of listings synced per batch.
public var syncBatchSize = 10

public enum SyncConfig {
    public static var maxRetries = 3
    public static var pollInterval: TimeInterval = 30
}

/// Debug counter, incremented from background queues. Never read.
var syncAttempts = 0
