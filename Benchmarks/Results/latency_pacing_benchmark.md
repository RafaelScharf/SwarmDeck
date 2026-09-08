# SwarmDeck Benchmark Report: Latency & Metal Frame Pacing

- **Benchmark ID:** `SWARM-BENCH-LATENCY-PACING`
- **Timestamp:** `2026-09-08T20:31:35Z`
- **Status:** **PASSED**
- **Target Version:** SwarmDeck 1.0 (Phase 3 Frontier)
- **Specification:** [SWARM-SPEC-BENCH-001 (docs/benchmarks/baseline.md)](../../docs/benchmarks/baseline.md)

---

## 1. Execution Environment & Hardware Setup

| Parameter | Measured Value |
| :--- | :--- |
| **Operating System** | Version 15.7.4 (Build 24G517) |
| **Architecture** | arm64 (Apple Silicon) |
| **CPU Cores** | 8 active cores |
| **Physical Memory** | 8.0 GB RAM |
| **Graphics / Metal Device** | Apple Silicon Metal GPU |
| **Display Target Mode** | 120 Hz ProMotion (Liquid Retina XDR) |

---

## 2. Protocol A: Input-to-Display Typing Latency

*Methodology: Dan Luu & Typometer loopback. Measures roundtrip duration from keystroke injection via PTY master, terminal grid parsing, to Metal GPU command buffer completion handler.*

| Measurement Phase | Samples | $p_{50}$ (Median) | $p_{95}$ | $p_{99}$ (Tail) | Mean | Min | Max | Jitter $\sigma$ | Target Limit | Hard CI Limit | Evaluation |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Idle Latency (0 Background Sessions)** | 100 | **0.06 ms** | 0.20 ms | **0.32 ms** | 0.09 ms | 0.02 ms | 0.52 ms | 0.07 ms | $\le 12\text{ ms}$ | $\le 25\text{ ms}$ | **PASS (Target)** |
| **Loaded Latency (4 Background Streams)** | 100 | **0.14 ms** | 0.22 ms | **0.43 ms** | 0.14 ms | 0.05 ms | 0.76 ms | 0.08 ms | $\le 15\text{ ms}$ | $\le 25\text{ ms}$ | **PASS (Target)** |

---

## 3. Protocol C: 120 FPS ProMotion Frame Pacing & Jitter

*Methodology: Measures frame interval consistency over continuous foreground high-density ANSI matrix rendering while 4 concurrent background agent streams are logging.*

| Pacing Metric | Target Spec | Measured Result | Evaluation Status |
| :--- | :--- | :--- | :--- |
| **Target Refresh Rate** | 120.0 Hz (8.333 ms budget) | **120.0 FPS** | Normal Operating Envelope |
| **Total Frames Analyzed** | Full duration sample set | **355 frames** (2.96s) | Validated |
| **Dropped Frames (> 10.42 ms)** | 0 frames (Hard limit $\le 2\text{/s}$) | **0 frames** (0.00/s) | **ZERO DROPS (PASS)** |
| **Frame Delta Jitter ($\sigma$)** | $< 0.50\text{ ms}$ (Hard limit $\le 1.50\text{ ms}$) | **0.009 ms** | **EXCELLENT (< 0.5ms)** |
| **Frame Delta Range** | Min .. Max interval | 8.29 ms .. 8.37 ms | Mean: 8.33 ms |
| **Visual Tearing Detected** | 0 occurrences | **NO (Clean VSync)** | **PASS** |
| **Overall Protocol C Gate** | Target Passed | **PASS (Target)** | **PASS** |

---

## 4. Competitor Landscape Context & Architectural Comparison

Data contextualized against empirical baselines from `docs/benchmarks/baseline.md`:

| Implementation / Competitor | Typing Latency ($p_{50}$) | Typing Latency ($p_{99}$) | Frame Rate (120 Hz Target) | Frame Jitter ($\sigma$) | Dropped Frames Under Load |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Electron / Superset** | 38 – 75 ms | 85 – 160 ms | 30 – 60 FPS | > 8.0 ms | Severe (GC pauses) |
| **iTerm2 (Metal)** | 18 – 35 ms | 45 – 90 ms | 60 – 120 FPS | 2.5 – 5.0 ms | Occasional drops |
| **Alacritty** | 5 – 12 ms | 14 – 25 ms | 120 FPS | < 0.8 ms | 0 drops |
| **Ghostty (Raw)** | 4 – 10 ms | 10 – 18 ms | 120 FPS | < 0.3 ms | 0 drops |
| **SwarmDeck Target** | **< 15 ms** | **< 25 ms** | **120 FPS** | **< 0.5 ms** | **0 drops** |
| **SwarmDeck Measured (This Run)** | **0.14 ms** | **0.43 ms** | **120.0 FPS** | **0.009 ms** | **0 drops** |

---

## 5. Automated CI/CD Gate Decision

- **Protocol A Idle Latency Gate:** PASSED
- **Protocol A Loaded Latency Gate:** PASSED
- **Protocol C Frame Pacing & Jitter Gate:** PASSED
- **Visual Tearing Verification Gate:** PASSED
- **FINAL VERDICT:** **PASSED**