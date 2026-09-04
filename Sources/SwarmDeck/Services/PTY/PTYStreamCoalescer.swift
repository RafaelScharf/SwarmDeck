import Foundation
import os

/// Provides high-throughput stream coalescing and adaptive backpressure.
public final class PTYStreamCoalescer: @unchecked Sendable {
    private let continuation: AsyncStream<Data>.Continuation
    private let workerTask: Task<Void, Never>
    private let isFinished = OSAllocatedUnfairLock(initialState: false)
    
    public init(
        maxBufferSize: Int = 64 * 1024,
        coalesceInterval: ContinuousClock.Instant.Duration = .milliseconds(16),
        onBatch: @escaping @Sendable (Data) async -> Void
    ) {
        var localContinuation: AsyncStream<Data>.Continuation!
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(2000)) { cont in
            localContinuation = cont
        }
        self.continuation = localContinuation
        
        self.workerTask = Task.detached(priority: .userInitiated) {
            var buffer = Data()
            buffer.reserveCapacity(maxBufferSize)
            
            for await chunk in stream {
                buffer.append(chunk)
                
                if buffer.count >= maxBufferSize {
                    let batch = buffer
                    buffer = Data()
                    buffer.reserveCapacity(maxBufferSize)
                    await onBatch(batch)
                } else {
                    try? await Task.sleep(for: coalesceInterval)
                    
                    if !buffer.isEmpty {
                        let batch = buffer
                        buffer = Data()
                        buffer.reserveCapacity(maxBufferSize)
                        await onBatch(batch)
                    }
                }
            }
            
            if !buffer.isEmpty {
                await onBatch(buffer)
            }
        }
    }
    
    public func yield(_ data: Data) {
        let finished = isFinished.withLock { $0 }
        guard !finished, !data.isEmpty else { return }
        continuation.yield(data)
    }
    
    public func finish() {
        let shouldFinish = isFinished.withLock { finished -> Bool in
            if !finished {
                finished = true
                return true
            }
            return false
        }
        if shouldFinish {
            continuation.finish()
        }
    }
    
    public func cancel() {
        finish()
        workerTask.cancel()
    }
}
