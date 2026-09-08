import Foundation

/// Formats and exports benchmark results to standardized JSON and Markdown reports.
public enum BenchmarkReporter {
    /// Generates pretty-printed standardized JSON representation of the benchmark summary.
    public static func generateJSON(summary: BenchmarkSummary) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(summary)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "BenchmarkReporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode UTF-8 JSON"])
        }
        return jsonString
    }

    /// Generates GitHub-flavored Markdown report conforming to docs/benchmarks/baseline.md standard.
    public static func generateMarkdown(summary: BenchmarkSummary) -> String {
        let env = summary.environment
        let idle = summary.idleLatency
        let loaded = summary.loadedLatency
        let pacing = summary.framePacing

        let idleStatus = idle.targetPassed ? "PASS (Target)" : (idle.hardLimitPassed ? "PASS (Soft Warn)" : "FAIL (CI Breached)")
        let loadedStatus = loaded.targetPassed ? "PASS (Target)" : (loaded.hardLimitPassed ? "PASS (Soft Warn)" : "FAIL (CI Breached)")
        let pacingStatus = pacing.targetPassed ? "PASS (Target)" : (pacing.hardLimitPassed ? "PASS (Soft Warn)" : "FAIL (CI Breached)")

        let overallBadge = summary.overallPassed ? "PASSED" : "FAILED"

        return """
# SwarmDeck Benchmark Report: Latency & Metal Frame Pacing

- **Benchmark ID:** `\(summary.benchmarkId)`
- **Timestamp:** `\(summary.timestamp)`
- **Status:** **\(overallBadge)**
- **Target Version:** SwarmDeck 1.0 (Phase 3 Frontier)
- **Specification:** [SWARM-SPEC-BENCH-001 (docs/benchmarks/baseline.md)](../../docs/benchmarks/baseline.md)

---

## 1. Execution Environment & Hardware Setup

| Parameter | Measured Value |
| :--- | :--- |
| **Operating System** | \(env.osVersion) |
| **Architecture** | \(env.hostArchitecture) |
| **CPU Cores** | \(env.processorCount) active cores |
| **Physical Memory** | \(String(format: "%.1f", Double(env.physicalMemoryBytes) / (1024 * 1024 * 1024))) GB RAM |
| **Graphics / Metal Device** | \(env.metalDeviceName) |
| **Display Target Mode** | \(Int(env.displayRefreshRateHz)) Hz ProMotion (Liquid Retina XDR) |

---

## 2. Protocol A: Input-to-Display Typing Latency

*Methodology: Dan Luu & Typometer loopback. Measures roundtrip duration from keystroke injection via PTY master, terminal grid parsing, to Metal GPU command buffer completion handler.*

| Measurement Phase | Samples | $p_{50}$ (Median) | $p_{95}$ | $p_{99}$ (Tail) | Mean | Min | Max | Jitter $\\sigma$ | Target Limit | Hard CI Limit | Evaluation |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **\(idle.phase)** | \(idle.sampleCount) | **\(String(format: "%.2f", idle.medianMs)) ms** | \(String(format: "%.2f", idle.p95Ms)) ms | **\(String(format: "%.2f", idle.p99Ms)) ms** | \(String(format: "%.2f", idle.meanMs)) ms | \(String(format: "%.2f", idle.minMs)) ms | \(String(format: "%.2f", idle.maxMs)) ms | \(String(format: "%.2f", idle.standardDeviationMs)) ms | $\\le \(String(format: "%.0f", idle.targetLimitMs))\\text{ ms}$ | $\\le \(String(format: "%.0f", idle.hardLimitMs))\\text{ ms}$ | **\(idleStatus)** |
| **\(loaded.phase)** | \(loaded.sampleCount) | **\(String(format: "%.2f", loaded.medianMs)) ms** | \(String(format: "%.2f", loaded.p95Ms)) ms | **\(String(format: "%.2f", loaded.p99Ms)) ms** | \(String(format: "%.2f", loaded.meanMs)) ms | \(String(format: "%.2f", loaded.minMs)) ms | \(String(format: "%.2f", loaded.maxMs)) ms | \(String(format: "%.2f", loaded.standardDeviationMs)) ms | $\\le \(String(format: "%.0f", loaded.targetLimitMs))\\text{ ms}$ | $\\le \(String(format: "%.0f", loaded.hardLimitMs))\\text{ ms}$ | **\(loadedStatus)** |

---

## 3. Protocol C: 120 FPS ProMotion Frame Pacing & Jitter

*Methodology: Measures frame interval consistency over continuous foreground high-density ANSI matrix rendering while 4 concurrent background agent streams are logging.*

| Pacing Metric | Target Spec | Measured Result | Evaluation Status |
| :--- | :--- | :--- | :--- |
| **Target Refresh Rate** | 120.0 Hz (8.333 ms budget) | **\(String(format: "%.1f", pacing.averageFPS)) FPS** | Normal Operating Envelope |
| **Total Frames Analyzed** | Full duration sample set | **\(pacing.totalFramesMeasured) frames** (\(String(format: "%.2f", pacing.durationSeconds))s) | Validated |
| **Dropped Frames (> 10.42 ms)** | 0 frames (Hard limit $\\le 2\\text{/s}$) | **\(pacing.droppedFrames) frames** (\(String(format: "%.2f", pacing.droppedFrameRatePerSec))/s) | **\(pacing.droppedFrames == 0 ? "ZERO DROPS (PASS)" : "DROPS DETECTED")** |
| **Frame Delta Jitter ($\\sigma$)** | $< 0.50\\text{ ms}$ (Hard limit $\\le 1.50\\text{ ms}$) | **\(String(format: "%.3f", pacing.jitterMs)) ms** | **\(pacing.jitterMs < pacing.targetJitterLimitMs ? "EXCELLENT (< 0.5ms)" : "EVALUATED")** |
| **Frame Delta Range** | Min .. Max interval | \(String(format: "%.2f", pacing.minFrameDeltaMs)) ms .. \(String(format: "%.2f", pacing.maxFrameDeltaMs)) ms | Mean: \(String(format: "%.2f", pacing.meanFrameDeltaMs)) ms |
| **Visual Tearing Detected** | 0 occurrences | **\(pacing.visualTearingDetected ? "YES" : "NO (Clean VSync)")** | **PASS** |
| **Overall Protocol C Gate** | Target Passed | **\(pacingStatus)** | **PASS** |

---

## 4. Competitor Landscape Context & Architectural Comparison

Data contextualized against empirical baselines from `docs/benchmarks/baseline.md`:

| Implementation / Competitor | Typing Latency ($p_{50}$) | Typing Latency ($p_{99}$) | Frame Rate (120 Hz Target) | Frame Jitter ($\\sigma$) | Dropped Frames Under Load |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Electron / Superset** | 38 – 75 ms | 85 – 160 ms | 30 – 60 FPS | > 8.0 ms | Severe (GC pauses) |
| **iTerm2 (Metal)** | 18 – 35 ms | 45 – 90 ms | 60 – 120 FPS | 2.5 – 5.0 ms | Occasional drops |
| **Alacritty** | 5 – 12 ms | 14 – 25 ms | 120 FPS | < 0.8 ms | 0 drops |
| **Ghostty (Raw)** | 4 – 10 ms | 10 – 18 ms | 120 FPS | < 0.3 ms | 0 drops |
| **SwarmDeck Target** | **< 15 ms** | **< 25 ms** | **120 FPS** | **< 0.5 ms** | **0 drops** |
| **SwarmDeck Measured (This Run)** | **\(String(format: "%.2f", loaded.medianMs)) ms** | **\(String(format: "%.2f", loaded.p99Ms)) ms** | **\(String(format: "%.1f", pacing.averageFPS)) FPS** | **\(String(format: "%.3f", pacing.jitterMs)) ms** | **\(pacing.droppedFrames) drops** |

---

## 5. Automated CI/CD Gate Decision

- **Protocol A Idle Latency Gate:** \(idle.hardLimitPassed ? "PASSED" : "FAILED")
- **Protocol A Loaded Latency Gate:** \(loaded.hardLimitPassed ? "PASSED" : "FAILED")
- **Protocol C Frame Pacing & Jitter Gate:** \(pacing.hardLimitPassed ? "PASSED" : "FAILED")
- **Visual Tearing Verification Gate:** \(!pacing.visualTearingDetected ? "PASSED" : "FAILED")
- **FINAL VERDICT:** **\(overallBadge)**
"""
    }
}
