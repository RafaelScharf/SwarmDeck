import Foundation

/// Defines the execution phase of the latency benchmark.
public enum BenchmarkPhase: String, Codable, Sendable {
    case idle = "idle"
    case loaded = "loaded"
}

/// A single timestamped latency measurement sample.
public struct LatencySample: Codable, Sendable {
    public let sampleIndex: Int
    public let timestampSeconds: Double
    public let latencyMs: Double
    public let phase: BenchmarkPhase

    public init(sampleIndex: Int, timestampSeconds: Double, latencyMs: Double, phase: BenchmarkPhase) {
        self.sampleIndex = sampleIndex
        self.timestampSeconds = timestampSeconds
        self.latencyMs = latencyMs
        self.phase = phase
    }
}

/// Statistical metrics calculated over a series of latency samples.
public struct LatencyMetrics: Codable, Sendable {
    public let phase: String
    public let sampleCount: Int
    public let medianMs: Double         // p50
    public let p95Ms: Double            // p95
    public let p99Ms: Double            // p99
    public let meanMs: Double
    public let minMs: Double
    public let maxMs: Double
    public let standardDeviationMs: Double // sigma
    public let targetLimitMs: Double
    public let hardLimitMs: Double
    public let targetPassed: Bool
    public let hardLimitPassed: Bool

    public init(
        phase: String,
        sampleCount: Int,
        medianMs: Double,
        p95Ms: Double,
        p99Ms: Double,
        meanMs: Double,
        minMs: Double,
        maxMs: Double,
        standardDeviationMs: Double,
        targetLimitMs: Double,
        hardLimitMs: Double
    ) {
        self.phase = phase
        self.sampleCount = sampleCount
        self.medianMs = medianMs
        self.p95Ms = p95Ms
        self.p99Ms = p99Ms
        self.meanMs = meanMs
        self.minMs = minMs
        self.maxMs = maxMs
        self.standardDeviationMs = standardDeviationMs
        self.targetLimitMs = targetLimitMs
        self.hardLimitMs = hardLimitMs
        self.targetPassed = medianMs <= targetLimitMs && p99Ms <= (targetLimitMs * 1.67)
        self.hardLimitPassed = medianMs <= hardLimitMs && p99Ms <= (hardLimitMs * 1.6)
    }
}

/// Frame pacing stability and jitter metrics for Metal/ProMotion rendering.
public struct FramePacingMetrics: Codable, Sendable {
    public let targetFPS: Double
    public let targetFrameTimeMs: Double
    public let droppedThresholdMs: Double
    public let totalFramesMeasured: Int
    public let durationSeconds: Double
    public let averageFPS: Double
    public let droppedFrames: Int
    public let droppedFrameRatePerSec: Double
    public let minFrameDeltaMs: Double
    public let maxFrameDeltaMs: Double
    public let meanFrameDeltaMs: Double
    public let jitterMs: Double          // sigma
    public let visualTearingDetected: Bool
    public let targetJitterLimitMs: Double
    public let hardJitterLimitMs: Double
    public let targetPassed: Bool
    public let hardLimitPassed: Bool

    public init(
        targetFPS: Double = 120.0,
        targetFrameTimeMs: Double = 8.333,
        droppedThresholdMs: Double = 10.42,
        totalFramesMeasured: Int,
        durationSeconds: Double,
        averageFPS: Double,
        droppedFrames: Int,
        droppedFrameRatePerSec: Double,
        minFrameDeltaMs: Double,
        maxFrameDeltaMs: Double,
        meanFrameDeltaMs: Double,
        jitterMs: Double,
        visualTearingDetected: Bool = false,
        targetJitterLimitMs: Double = 0.5,
        hardJitterLimitMs: Double = 1.5
    ) {
        self.targetFPS = targetFPS
        self.targetFrameTimeMs = targetFrameTimeMs
        self.droppedThresholdMs = droppedThresholdMs
        self.totalFramesMeasured = totalFramesMeasured
        self.durationSeconds = durationSeconds
        self.averageFPS = averageFPS
        self.droppedFrames = droppedFrames
        self.droppedFrameRatePerSec = droppedFrameRatePerSec
        self.minFrameDeltaMs = minFrameDeltaMs
        self.maxFrameDeltaMs = maxFrameDeltaMs
        self.meanFrameDeltaMs = meanFrameDeltaMs
        self.jitterMs = jitterMs
        self.visualTearingDetected = visualTearingDetected
        self.targetJitterLimitMs = targetJitterLimitMs
        self.hardJitterLimitMs = hardJitterLimitMs
        self.targetPassed = droppedFrames == 0 && jitterMs < targetJitterLimitMs && !visualTearingDetected
        self.hardLimitPassed = droppedFrameRatePerSec <= 2.0 && jitterMs <= hardJitterLimitMs && !visualTearingDetected
    }
}

/// Hardware and runtime execution environment description.
public struct BenchmarkEnvironment: Codable, Sendable {
    public let osVersion: String
    public let hostArchitecture: String
    public let processorCount: Int
    public let physicalMemoryBytes: UInt64
    public let displayRefreshRateHz: Double
    public let metalDeviceName: String

    public init(
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        hostArchitecture: String = {
            #if arch(arm64)
            return "arm64 (Apple Silicon)"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }(),
        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory,
        displayRefreshRateHz: Double = 120.0,
        metalDeviceName: String = "Apple Silicon Metal GPU"
    ) {
        self.osVersion = osVersion
        self.hostArchitecture = hostArchitecture
        self.processorCount = processorCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.displayRefreshRateHz = displayRefreshRateHz
        self.metalDeviceName = metalDeviceName
    }
}

/// Full benchmark results container.
public struct BenchmarkSummary: Codable, Sendable {
    public let benchmarkId: String
    public let timestamp: String
    public let environment: BenchmarkEnvironment
    public let idleLatency: LatencyMetrics
    public let loadedLatency: LatencyMetrics
    public let framePacing: FramePacingMetrics
    public let overallPassed: Bool

    public init(
        benchmarkId: String = "SWARM-BENCH-LATENCY-PACING",
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        environment: BenchmarkEnvironment,
        idleLatency: LatencyMetrics,
        loadedLatency: LatencyMetrics,
        framePacing: FramePacingMetrics
    ) {
        self.benchmarkId = benchmarkId
        self.timestamp = timestamp
        self.environment = environment
        self.idleLatency = idleLatency
        self.loadedLatency = loadedLatency
        self.framePacing = framePacing
        self.overallPassed = idleLatency.targetPassed && loadedLatency.targetPassed && framePacing.targetPassed
    }
}
