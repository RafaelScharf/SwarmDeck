import Foundation
import os

/// Provides high-throughput stream coalescing and adaptive backpressure.
public final class PTYStreamCoalescer: @unchecked Sendable {
    private struct State {
        var buffer = Data()
        var isFinished = false
        var isFlushScheduled = false
    }
    
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let maxBufferSize: Int
    private let coalesceInterval: ContinuousClock.Instant.Duration
    private let onBatch: @Sendable (Data) async -> Void
    private var flushTask: Task<Void, Never>?
    
    public init(
        maxBufferSize: Int = 64 * 1024,
        coalesceInterval: ContinuousClock.Instant.Duration = .milliseconds(16),
        onBatch: @escaping @Sendable (Data) async -> Void
    ) {
        self.maxBufferSize = maxBufferSize
        self.coalesceInterval = coalesceInterval
        self.onBatch = onBatch
    }
    
    public func yield(_ data: Data) {
        guard !data.isEmpty else { return }
        
        let (batchToEmit, shouldScheduleFlush) = state.withLock { s -> (Data?, Bool) in
            guard !s.isFinished else { return (nil, false) }
            s.buffer.append(data)
            if s.buffer.count >= maxBufferSize {
                let batch = s.buffer
                s.buffer = Data()
                s.buffer.reserveCapacity(maxBufferSize)
                s.isFlushScheduled = false
                return (batch, false)
            } else if !s.isFlushScheduled {
                s.isFlushScheduled = true
                return (nil, true)
            }
            return (nil, false)
        }
        
        if let batch = batchToEmit {
            Task { await self.onBatch(batch) }
        } else if shouldScheduleFlush {
            scheduleFlush()
        }
    }
    
    private func scheduleFlush() {
        flushTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: self.coalesceInterval)
            let batchToEmit = self.state.withLock { s -> Data? in
                s.isFlushScheduled = false
                if !s.buffer.isEmpty {
                    let batch = s.buffer
                    s.buffer = Data()
                    s.buffer.reserveCapacity(self.maxBufferSize)
                    return batch
                }
                return nil
            }
            if let batch = batchToEmit {
                await self.onBatch(batch)
            }
        }
    }
    
    public func finish() {
        let batchToEmit = state.withLock { s -> Data? in
            s.isFinished = true
            s.isFlushScheduled = false
            if !s.buffer.isEmpty {
                let batch = s.buffer
                s.buffer = Data()
                return batch
            }
            return nil
        }
        flushTask?.cancel()
        flushTask = nil
        if let batch = batchToEmit {
            Task { await self.onBatch(batch) }
        }
    }
    
    public func cancel() {
        finish()
    }
}
