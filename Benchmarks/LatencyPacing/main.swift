import Foundation

func printUsage() {
    print("""
    Usage: swift run LatencyPacingBenchmark [options]
       or: ./scripts/benchmark_latency.swift [options]

    Options:
      --quick                  Run fast 3s smoke benchmark
      --samples <n>            Number of keystrokes per latency phase (default: 300)
      --duration <seconds>     Seconds to run continuous frame pacing test (default: 5.0)
      --output-json <path>     JSON output path (default: Benchmarks/Results/latency_pacing_benchmark.json)
      --output-md <path>       Markdown output path (default: Benchmarks/Results/latency_pacing_benchmark.md)
      --strict                 Fail exit code on soft target violation instead of hard CI limit
      --help, -h               Show this help message
    """)
}

let args = CommandLine.arguments

        if args.contains("--help") || args.contains("-h") {
            printUsage()
            exit(0)
        }

        var samples = 300
        var duration = 5.0
        var jsonOutputPath = "Benchmarks/Results/latency_pacing_benchmark.json"
        var mdOutputPath = "Benchmarks/Results/latency_pacing_benchmark.md"
        var strictMode = false

        if args.contains("--quick") {
            samples = 100
            duration = 3.0
        }

        if args.contains("--strict") {
            strictMode = true
        }

        var idx = 1
        while idx < args.count {
            let arg = args[idx]
            if arg == "--samples" && idx + 1 < args.count {
                samples = Int(args[idx + 1]) ?? samples
                idx += 1
            } else if arg == "--duration" && idx + 1 < args.count {
                duration = Double(args[idx + 1]) ?? duration
                idx += 1
            } else if arg == "--output-json" && idx + 1 < args.count {
                jsonOutputPath = args[idx + 1]
                idx += 1
            } else if arg == "--output-md" && idx + 1 < args.count {
                mdOutputPath = args[idx + 1]
                idx += 1
            }
            idx += 1
        }

        print("================================================================================")
        print(" SwarmDeck Benchmark Harness: Latency & Metal Frame Pacing (Issue #37)")
        print("================================================================================")
        print("Samples per phase: \(samples) | Frame Pacing Duration: \(duration)s")
        print("Output JSON: \(jsonOutputPath)")
        print("Output MD:   \(mdOutputPath)")
        print("--------------------------------------------------------------------------------\n")

        let latencyConfig = LatencyBenchmark.Configuration(
            idleSamples: samples,
            loadedSamples: samples,
            minIntervalMs: 2.0,
            maxIntervalMs: 8.0,
            backgroundStreams: 4
        )
        let latencyBench = LatencyBenchmark(configuration: latencyConfig)

        let pacingConfig = FramePacingBenchmark.Configuration(
            targetFPS: 120.0,
            durationSeconds: duration,
            backgroundStreams: 4
        )
        let pacingBench = FramePacingBenchmark(configuration: pacingConfig)

        do {
            // Run Protocol A
            let (idleMetrics, loadedMetrics) = try await latencyBench.runBenchmark { msg in
                print("[Protocol A] \(msg)")
            }

            print("")
            // Run Protocol C
            let pacingMetrics = try await pacingBench.runBenchmark { msg in
                print("[Protocol C] \(msg)")
            }

            print("\n--------------------------------------------------------------------------------")
            print(" Benchmark Execution Completed. Generating Reports...")
            print("--------------------------------------------------------------------------------")

            let env = BenchmarkEnvironment()
            let summary = BenchmarkSummary(
                environment: env,
                idleLatency: idleMetrics,
                loadedLatency: loadedMetrics,
                framePacing: pacingMetrics
            )

            // Generate reports
            let jsonString = try BenchmarkReporter.generateJSON(summary: summary)
            let mdString = BenchmarkReporter.generateMarkdown(summary: summary)

            // Ensure output directories exist
            let jsonURL = URL(fileURLWithPath: jsonOutputPath)
            let mdURL = URL(fileURLWithPath: mdOutputPath)

            try? FileManager.default.createDirectory(at: jsonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: mdURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            try jsonString.write(to: jsonURL, atomically: true, encoding: .utf8)
            try mdString.write(to: mdURL, atomically: true, encoding: .utf8)

            print("✓ Saved JSON report to: \(jsonOutputPath)")
            print("✓ Saved Markdown report to: \(mdOutputPath)")
            print("\n" + mdString)

            let passed = strictMode ? summary.overallPassed : (idleMetrics.hardLimitPassed && loadedMetrics.hardLimitPassed && pacingMetrics.hardLimitPassed)

            if passed {
                print("\n>>> ALL BENCHMARK GATES PASSED SUCCESSFULLY <<<")
                exit(0)
            } else {
                print("\n>>> BENCHMARK HARD CI GATES FAILED <<<")
                exit(1)
            }
        } catch {
            print("Benchmark execution error: \(error.localizedDescription)")
            exit(2)
        }

