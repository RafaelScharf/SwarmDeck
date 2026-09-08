import Foundation
import Darwin

/// Benchmark harness executing Protocol D (PTY Ingestion Throughput & Coalescing)
/// and Protocol E (Agent Prompt Turnaround Detection).
public final class PTYThroughputHarness: @unchecked Sendable {
    
    public struct Options: Sendable {
        public var iterations: Int
        public var targetBytesPerWorkload: Int
        public var workloads: [ANSISyntheticGenerator.Workload]
        public var verbose: Bool
        
        public init(
            iterations: Int = 3,
            targetBytesPerWorkload: Int = 50 * 1024 * 1024,
            workloads: [ANSISyntheticGenerator.Workload] = ANSISyntheticGenerator.Workload.allCases,
            verbose: Bool = true
        ) {
            self.iterations = iterations
            self.targetBytesPerWorkload = targetBytesPerWorkload
            self.workloads = workloads
            self.verbose = verbose
        }
    }
    
    private let options: Options
    private let generator: ANSISyntheticGenerator
    
    public init(options: Options = Options()) {
        self.options = options
        self.generator = ANSISyntheticGenerator()
    }
    
    // MARK: - Memory Footprint Measurement
    
    public static func currentDirtyMemoryBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
    
    // MARK: - Protocol D: Raw PTY Stream Ingestion Benchmark
    
    public func benchmarkPTYIngestion(
        workload: ANSISyntheticGenerator.Workload,
        targetBytes: Int
    ) async throws -> BenchmarkReport.WorkloadResult {
        if options.verbose {
            print("  ▶ Benchmarking Workload: \(workload.displayName) (\(targetBytes / (1024 * 1024)) MB)...")
        }
        
        let dataset = generator.generate(workload: workload, targetBytes: targetBytes)
        
        var masterFd: Int32 = -1
        var slaveFd: Int32 = -1
        guard openpty(&masterFd, &slaveFd, nil, nil, nil) == 0 else {
            throw NSError(domain: "PTYBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "openpty failed"])
        }
        
        // Configure slave terminal in raw mode (no echo, no canonical line buffering)
        var term = termios()
        tcgetattr(slaveFd, &term)
        cfmakeraw(&term)
        tcsetattr(slaveFd, TCSANOW, &term)
        
        let memBefore = Self.currentDirtyMemoryBytes()
        let writeChunkSize = 1024
        let totalBytes = dataset.count
        
        let capturedMasterFd = masterFd
        let capturedSlaveFd = slaveFd
        let bytesAccumulator = CoalescerMetricsAccumulator()
        let ready = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let timing = TimingBox()
        
        group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            var readBuffer = [UInt8](repeating: 0, count: 64 * 1024)
            var totalRead = 0
            ready.signal()
            while true {
                let bytesRead = Darwin.read(capturedMasterFd, &readBuffer, readBuffer.count)
                if bytesRead > 0 {
                    totalRead += bytesRead
                } else if bytesRead == 0 {
                    break // EOF
                } else {
                    if errno == EINTR { continue }
                    break
                }
            }
            timing.endTime = DispatchTime.now()
            Task {
                await bytesAccumulator.recordBatch(size: totalRead)
                group.leave()
            }
        }
        
        group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            ready.wait()
            timing.startTime = DispatchTime.now()
            dataset.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var offset = 0
                while offset < totalBytes {
                    let toWrite = min(writeChunkSize, totalBytes - offset)
                    let written = Darwin.write(capturedSlaveFd, base + offset, toWrite)
                    if written > 0 {
                        offset += written
                    } else if written < 0 {
                        if errno == EINTR { continue }
                        break
                    }
                }
            }
            Darwin.close(capturedSlaveFd)
            group.leave()
        }
        
        await withCheckedContinuation { continuation in
            group.notify(queue: DispatchQueue.global(qos: .userInteractive)) {
                continuation.resume()
            }
        }
        Darwin.close(capturedMasterFd)
        
        let elapsedNanos = timing.endTime.uptimeNanoseconds - timing.startTime.uptimeNanoseconds
        let elapsedSeconds = Double(elapsedNanos) / 1_000_000_000.0
        
        let memAfter = Self.currentDirtyMemoryBytes()
        let memoryDeltaMB = Double(max(0, Int64(memAfter) - Int64(memBefore))) / (1024.0 * 1024.0)
        let bytesReceived = await bytesAccumulator.totalBytes
        
        let result = BenchmarkReport.WorkloadResult(
            workload: workload.displayName,
            totalBytes: bytesReceived,
            elapsedSeconds: elapsedSeconds,
            memoryDeltaMB: memoryDeltaMB,
            targetThroughputMBs: 65.0
        )
        
        if options.verbose {
            print("    ↳ Result: \(String(format: "%.2f", result.throughputMBs)) MB/s | Elapsed: \(String(format: "%.3f", elapsedSeconds))s | RAM Delta: \(String(format: "%.2f", memoryDeltaMB)) MB | \(result.passed ? "✅ PASS" : "❌ FAIL")")
        }
        
        return result
    }
    
    // MARK: - Protocol D: Backpressure Coalescing Benchmark
    
    public func benchmarkCoalescingEfficiency(
        chunkCount: Int = 4000,
        chunkSize: Int = 128
    ) async -> BenchmarkReport.CoalescerResult {
        if options.verbose {
            print("  ▶ Benchmarking PTYStreamCoalescer Backpressure & Batching (\(chunkCount) chunks)...")
        }
        
        let counter = CoalescerMetricsAccumulator()
        let coalescer = PTYStreamCoalescer(
            maxBufferSize: 64 * 1024,
            coalesceInterval: .milliseconds(16)
        ) { batch in
            await counter.recordBatch(size: batch.count)
        }
        
        let sampleChunk = Data(repeating: 0x41, count: chunkSize)
        let totalInputBytes = chunkCount * chunkSize
        
        for _ in 0..<chunkCount {
            coalescer.yield(sampleChunk)
        }
        coalescer.finish()
        
        // Await complete batch dispatch
        try? await Task.sleep(for: .milliseconds(200))
        
        let batches = await counter.batchCount
        let emittedBytes = await counter.totalBytes
        
        let result = BenchmarkReport.CoalescerResult(
            chunksInput: chunkCount,
            bytesInput: totalInputBytes,
            batchesEmitted: batches,
            bytesEmitted: emittedBytes
        )
        
        if options.verbose {
            print("    ↳ Chunks: \(chunkCount) -> Batches: \(batches) (Reduction: \(String(format: "%.1f%%", result.coalescingReductionPercent))) | Drop Rate: \(String(format: "%.2f%%", result.dropRatePercent)) | \(result.passed ? "✅ PASS" : "❌ FAIL")")
        }
        
        return result
    }
    
    // MARK: - Protocol E: In-Stream Prompt Detection Turnaround
    
    public func benchmarkPromptDetectionTurnaround() async -> BenchmarkReport.PromptDetectionResult {
        if options.verbose {
            print("  ▶ Benchmarking Protocol E: In-Stream Agent Prompt Detection Latency...")
        }
        
        var scenarios: [BenchmarkReport.PromptDetectionScenario] = []
        var falsePositives = 0
        
        // Scenario 1: Semantic Prompt Marker (OSC 133;B) - Target < 0.5 ms
        do {
            let detector = AgentStateDetector()
            let floodData = generator.generateDenseText(targetBytes: 32 * 1024)
            await detector.feed(data: floodData) // Pre-warm with stream flood
            
            let trigger = "\u{001B}]133;B\u{0007}".data(using: .utf8)!
            let t0 = DispatchTime.now()
            await detector.feed(data: trigger)
            let t1 = DispatchTime.now()
            
            let state = await detector.currentState
            let latencyMs = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
            
            scenarios.append(BenchmarkReport.PromptDetectionScenario(
                name: "OSC 133;B Semantic Prompt Marker",
                latencyMs: latencyMs,
                targetLatencyMs: 0.5,
                detected: "\(state)"
            ))
            if options.verbose {
                print("    ↳ OSC 133;B Marker Latency: \(String(format: "%.4f", latencyMs)) ms (Target: < 0.5 ms) | State: \(state)")
            }
        }
        
        // Scenario 2: Terminal Bell (\u{0007}) Alert - Target < 0.5 ms
        do {
            let detector = AgentStateDetector()
            let floodData = generator.generateDenseText(targetBytes: 32 * 1024)
            await detector.feed(data: floodData)
            
            let trigger = "Task paused for inspection.\u{0007}".data(using: .utf8)!
            let t0 = DispatchTime.now()
            await detector.feed(data: trigger)
            let t1 = DispatchTime.now()
            
            let state = await detector.currentState
            let latencyMs = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
            
            scenarios.append(BenchmarkReport.PromptDetectionScenario(
                name: "Terminal Bell Alert (\\x07)",
                latencyMs: latencyMs,
                targetLatencyMs: 0.5,
                detected: "\(state)"
            ))
            if options.verbose {
                print("    ↳ Bell Alert Latency: \(String(format: "%.4f", latencyMs)) ms (Target: < 0.5 ms) | State: \(state)")
            }
        }
        
        // Scenario 3: Blocked Confirmation Prompt ((y/n)) - Sliding Tail Buffer Evaluation - Target < 3.0 ms
        do {
            let detector = AgentStateDetector()
            let floodData = generator.generateDenseText(targetBytes: 32 * 1024)
            await detector.feed(data: floodData)
            
            let prompt = "\nDo you want to run this command? (y/n)\n".data(using: .utf8)!
            await detector.feed(data: prompt)
            
            let t0 = DispatchTime.now()
            await detector.evaluateNow()
            let state = await detector.currentState
            let t1 = DispatchTime.now()
            
            let regexLatencyMs = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
            let isBlocked: Bool
            if case .blocked = state { isBlocked = true } else { isBlocked = false }
            
            scenarios.append(BenchmarkReport.PromptDetectionScenario(
                name: "Blocked Confirmation Prompt (y/n)",
                latencyMs: regexLatencyMs,
                targetLatencyMs: 3.0,
                detected: isBlocked ? "blocked" : "\(state)"
            ))
            if options.verbose {
                print("    ↳ Confirmation Regex Latency: \(String(format: "%.4f", regexLatencyMs)) ms (Target: < 3.0 ms) | State: \(state)")
            }
        }
        
        // Scenario 4: Interactive Shell Prompt (❯ ) - Target < 3.0 ms
        do {
            let detector = AgentStateDetector()
            let floodData = generator.generateDenseText(targetBytes: 32 * 1024)
            await detector.feed(data: floodData)
            
            let prompt = "\nrafael@macbook ~/projects ❯ \n".data(using: .utf8)!
            await detector.feed(data: prompt)
            
            let t0 = DispatchTime.now()
            await detector.evaluateNow()
            let state = await detector.currentState
            let t1 = DispatchTime.now()
            
            let regexLatencyMs = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
            
            scenarios.append(BenchmarkReport.PromptDetectionScenario(
                name: "Shell Interactive Prompt (❯)",
                latencyMs: regexLatencyMs,
                targetLatencyMs: 3.0,
                detected: "\(state)"
            ))
            if options.verbose {
                print("    ↳ Shell Prompt Regex Latency: \(String(format: "%.4f", regexLatencyMs)) ms (Target: < 3.0 ms) | State: \(state)")
            }
        }
        
        // Scenario 5: Negative Control - Continuous compiler warnings & errors
        do {
            let detector = AgentStateDetector()
            let compilerErrors = """
            Sources/Compiler/Lexer.swift:42:10: warning: variable 'tmp' was never mutated; consider changing to 'let' constant
            Sources/Compiler/Parser.swift:105:14: error: cannot find 'y' in scope
            [23/100] Compiling Target ...
            """
            
            for _ in 0..<10 {
                await detector.feed(data: compilerErrors.data(using: .utf8)!)
            }
            await detector.evaluateNow()
            
            let state = await detector.currentState
            if case .blocked = state {
                falsePositives += 1
            }
            if options.verbose {
                print("    ↳ Negative Control Flood: \(falsePositives == 0 ? "✅ 0 false positives" : "❌ \(falsePositives) false positives")")
            }
        }
        
        return BenchmarkReport.PromptDetectionResult(scenarios: scenarios, falsePositives: falsePositives)
    }
    
    // MARK: - Full Execution Suite
    
    public func runSuite() async throws -> BenchmarkReport {
        if options.verbose {
            print("==================================================================")
            print(" SwarmDeck PTY Throughput & Cycle Acceleration Benchmark Suite")
            print(" Baseline Specification: SWARM-SPEC-BENCH-001 (Protocols D & E)")
            print("==================================================================\n")
        }
        
        var workloadResults: [BenchmarkReport.WorkloadResult] = []
        
        // Run Protocol D Ingestion Benchmarks
        for workload in options.workloads {
            var bestResult: BenchmarkReport.WorkloadResult?
            
            for i in 1...options.iterations {
                if options.verbose && options.iterations > 1 {
                    print("  [Iteration \(i)/\(options.iterations)]")
                }
                let result = try await benchmarkPTYIngestion(
                    workload: workload,
                    targetBytes: options.targetBytesPerWorkload
                )
                if bestResult == nil || result.throughputMBs > (bestResult?.throughputMBs ?? 0) {
                    bestResult = result
                }
            }
            if let best = bestResult {
                workloadResults.append(best)
            }
        }
        
        // Run Protocol D Coalescing Benchmark
        let coalescerResult = await benchmarkCoalescingEfficiency()
        
        // Run Protocol E Prompt Turnaround Benchmark
        let promptResult = await benchmarkPromptDetectionTurnaround()
        
        let report = BenchmarkReport(
            rawIngestionResults: workloadResults,
            coalescerResult: coalescerResult,
            promptDetectionResult: promptResult
        )
        
        if options.verbose {
            print("\n" + report.toMarkdown())
        }
        
        return report
    }
}

actor CoalescerMetricsAccumulator {
    var batchCount = 0
    var totalBytes = 0
    
    func recordBatch(size: Int) {
        batchCount += 1
        totalBytes += size
    }
}

final class TimingBox: @unchecked Sendable {
    var startTime = DispatchTime.now()
    var endTime = DispatchTime.now()
}
