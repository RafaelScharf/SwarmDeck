---
type: prototype-resolution
ticket: issue-11
status: resolved
date: 2026-09-04
url: https://github.com/RafaelScharf/SwarmDeck/issues/11
branch: feat/issue-11-pty-backpressure
---

# Resolution: Prototype - PTY High-Throughput Backpressure & Stream Coalescing

## Question
How do the libghostty `InMemoryTerminalSession` and `AgentStateDetector` handle massive bursts of stdout (e.g. `find /`, 50,000-line test runs, verbose compilation logs) without starving Swift 6's cooperative thread pool, causing memory spikes, or dropping UI frame rates?

## Findings & Implementation

1. **Root Cause Analysis:**
   - Previously, every PTY chunk read in `setOnData` spawned an unconstrained detached `Task { await detector?.feed(data: data) }`.
   - In massive bursts (e.g. 50,000 lines), thousands of tasks were queued concurrently on Swift 6's cooperative thread pool, risking thread starvation, unbounded memory usage, and UI lag.

2. **PTYStreamCoalescer with AsyncStream Backpressure:**
   - Implemented `PTYStreamCoalescer` using `AsyncStream<Data>(bufferingPolicy: .bufferingNewest(2000))`.
   - Replaced unbounded task spawning with a **single persistent background worker task** consuming from the stream.
   - Implemented adaptive 60 FPS frame coalescing: accumulates incoming chunks up to 64KB or flushes every 16ms, ensuring smooth Metal rendering in libghostty without lock contention.
   - PTY read handler only calls non-blocking `coalescer.yield(data)`.

3. **Detector Memory Bounding & Quiescence Evaluation:**
   - Capped `OutputStateDetector`'s internal buffer to a sliding 16KB tail (`16384` bytes) to prevent memory ballooning during multi-megabyte bursts.
   - Added multiline support `(?im)` to prompt regexes.
   - During active bursts, state immediately transitions to `.working` without running heavy regexes on intermediate logs. Full regex evaluation is deferred until the 250ms quiescence window elapses.

## Test Validation
- Created comprehensive stress-testing suite in `temp/prototypes/test_pty_backpressure.swift`.
- Tested:
  1. 500-chunk rapid burst coalesced into just 2 batches with 100% byte delivery (zero loss).
  2. 2 MB heavy data burst into `OutputStateDetector` maintaining bounded buffer and accurately detecting blocked prompt after 250ms quiescence.
  3. Real 50,000-line PTY child process execution (338,910 bytes processed in 0.07s at ~4.8 MB/s), coalescing thousands of PTY reads into only 11 batches, with clean zombie process reaping.
- All tests passed with 100% success rate.
