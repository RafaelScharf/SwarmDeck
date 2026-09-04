import Foundation

/// Coalesces high-throughput PTY stream chunks using AsyncStream backpressure,
/// preventing thread starvation, cooperative thread pool saturation, and UI frame drops.
public final class PTYStreamCoalescer: Sendable {
    private let continuation: AsyncStream<Data>.Continuation
    private let processingTask: Task<Void, Never>
    
    public init(
        maxBufferSize: Int = 64 * 1024,
        coalesceInterval: Duration = .milliseconds(16),
        onBatch: @escaping @Sendable (Data) async -> Void
    ) {
        var capturedContinuation: AsyncStream<Data>.Continuation!
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(2000)) { c in
            capturedContinuation = c
        }
        self.continuation = capturedContinuation
        
        self.processingTask = Task.detached(priority: .userInitiated) {
            var accumulated = Data()
            var lastFlush = ContinuousClock.now
            
            for await chunk in stream {
                accumulated.append(chunk)
                let now = ContinuousClock.now
                
                // Flush batch if accumulated buffer exceeds threshold or 16ms frame interval elapsed
                if accumulated.count >= maxBufferSize || now - lastFlush >= coalesceInterval {
                    let batch = accumulated
                    accumulated = Data()
                    accumulated.reserveCapacity(maxBufferSize)
                    lastFlush = now
                    await onBatch(batch)
                }
            }
            
            // Deliver any remaining accumulated data upon stream finish
            if !accumulated.isEmpty {
                await onBatch(accumulated)
            }
        }
    }
    
    /// Non-blocking insertion of raw PTY data chunk into backpressure stream.
    public func yield(_ data: Data) {
        continuation.yield(data)
    }
    
    /// Signals stream completion and flushes remaining buffer.
    public func finish() {
        continuation.finish()
    }
    
    /// Cancels processing task immediately.
    public func cancel() {
        continuation.finish()
        processingTask.cancel()
    }
}
