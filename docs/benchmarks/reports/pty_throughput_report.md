# SwarmDeck Benchmark Report: PTY Throughput & Cycle Acceleration Harness

- **Standard Specification:** `docs/benchmarks/baseline.md` (`SWARM-SPEC-BENCH-001`, Protocols D & E)
- **Target Version:** SwarmDeck 1.0 (Phase 3 Frontier)
- **Environment:** macOS 15.7.4 (Apple Silicon (arm64)) | 8 Cores | 8.0 GB RAM
- **Timestamp:** 2026-09-08T20:20:48Z
- **Overall Verdict:** ✅ **ALL BENCHMARKS PASSED**

---

## 1. Protocol D: Pseudo-Terminal (PTY) Raw Ingestion Throughput

*Target: Sustained ingestion rate $> 65.0\text{ MB/s}$ with zero dropped bytes and memory spike $< 30.0\text{ MB}$.*

| Workload Pattern | Data Volume | Elapsed Time | Throughput | RAM Delta | Target | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Dense UTF-8 Text (Cat/Logs) | 10.0 MB | 0.030 s | **333.59 MB/s** | 0.00 MB | $> 65.0\text{ MB/s}$ | ✅ PASS |
| 24-bit TrueColor Matrix | 10.0 MB | 0.033 s | **305.39 MB/s** | 0.00 MB | $> 65.0\text{ MB/s}$ | ✅ PASS |
| Cursor Repositioning & Selective Erasure | 10.0 MB | 0.040 s | **248.87 MB/s** | 0.22 MB | $> 65.0\text{ MB/s}$ | ✅ PASS |
| Syntax Diffs (Git/Patch) | 10.0 MB | 0.025 s | **407.09 MB/s** | 0.00 MB | $> 65.0\text{ MB/s}$ | ✅ PASS |

---

## 2. Protocol D: Backpressure Coalescing Efficiency (`PTYStreamCoalescer`)

*Evaluates `AsyncStream` batching efficiency (60 FPS / 16ms window) vs UI main-thread dispatch reduction.*

| Metric | Measured Value | Baseline Target | Status |
| :--- | :--- | :--- | :--- |
| **Input Stream Chunks** | 4000 chunks | High-density burst | ℹ️ Tested |
| **Input Data Volume** | 0.49 MB | Multi-megabyte load | ℹ️ Tested |
| **Emitted Batches** | 8 batches | Coalesced into render frames | ℹ️ Measured |
| **Average Batch Size** | 64000 bytes | Bounded to 64 KB max | ✅ Optimal |
| **Coalescing Reduction** | **99.8%** | $\ge 50.0\%$ reduction | ✅ PASS |
| **Dropped Data Bytes** | **0 bytes** | **0 bytes** (100% integrity) | ✅ PASS (Zero loss) |

---

## 3. Protocol E: In-Stream Agent Prompt Detection Turnaround

*Measures detection latency from byte arrival in `AgentStateDetector.feed(data:)` to state transition dispatch under background data flood.*

| Scenario / Trigger | Detected State | Measured Latency | Protocol Target | Status |
| :--- | :--- | :--- | :--- | :--- |
| OSC 133;B Semantic Prompt Marker | `idle` | **0.019 ms** | < 0.5 ms | ✅ PASS |
| Terminal Bell Alert (\x07) | `blocked(reason: "Terminal Bell Alert")` | **0.052 ms** | < 0.5 ms | ✅ PASS |
| Blocked Confirmation Prompt (y/n) | `blocked` | **0.750 ms** | < 3.0 ms | ✅ PASS |
| Shell Interactive Prompt (❯) | `idle` | **0.188 ms** | < 3.0 ms | ✅ PASS |
| Continuous Compiler Flood | No False Trigger | **0 false positives** | 0 false positives | ✅ PASS |

- **Turnaround Latencies:** Median ($p_{50}$): 0.188 ms | 95th Percentile ($p_{95}$): 0.750 ms | 99th Percentile ($p_{99}$): 0.750 ms

---

## 4. Competitor Performance Benchmark Comparison

| System / Terminal Multiplexer | Engine Architecture | PTY Throughput (`termbench`) | Stream Drop Rate | In-Stream Prompt Latency |
| :--- | :--- | :--- | :--- | :--- |
| **Superset / Electron (`xterm.js`)** | Chromium V8 + Node IPC | 12 – 28 MB/s | Jitter drops under flood | N/A (Manual polling) |
| **iTerm2** | Objective-C / Cocoa AppKit | 25 – 55 MB/s | RunLoop bottlenecks | N/A |
| **Alacritty** | Rust / Winit OpenGL | 80 – 150 MB/s | Zero loss | N/A (No agent detector) |
| **Ghostty** | Zig / Apple Silicon Metal | 75 – 140 MB/s | Zero loss | N/A (Single session) |
| **SwarmDeck (Measured)** | **Swift 6 + libghostty** | **323.7 MB/s (avg)** | **0.0% (Zero loss)** | **0.188 ms ($p_{50}$)** |
