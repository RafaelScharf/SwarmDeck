import Foundation

func runBenchmark() async {
    let args = CommandLine.arguments
        
        if args.contains("--help") || args.contains("-h") {
            print("""
            SwarmDeck PTY Throughput & Cycle Acceleration Benchmark Harness
            Usage: swift run PTYThroughputBenchmark [options]
            
            Options:
              --iterations <n>        Number of iterations per workload (default: 3)
              --bytes <mb>            Data volume per workload in MB (default: 50)
              --workload <type>       Specific workload: 'dense', 'truecolor', 'cursor', 'diff', or 'all' (default: all)
              --json <path>           Path to export structured JSON benchmark report
              --markdown <path>       Path to export Markdown benchmark report
              --export-dir <path>     Directory to export both JSON and Markdown reports
              --quiet                 Suppress verbose console streaming progress
              --help, -h              Show this help message
            """)
            return
        }
        
        var iterations = 3
        var bytesPerWorkloadMB = 50
        var workloadFilter: String? = nil
        var jsonExportPath: String? = nil
        var markdownExportPath: String? = nil
        var exportDir: String? = nil
        var verbose = true
        
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--iterations":
                if i + 1 < args.count, let val = Int(args[i + 1]) {
                    iterations = max(1, val)
                    i += 1
                }
            case "--bytes":
                if i + 1 < args.count, let val = Int(args[i + 1]) {
                    bytesPerWorkloadMB = max(1, val)
                    i += 1
                }
            case "--workload":
                if i + 1 < args.count {
                    workloadFilter = args[i + 1]
                    i += 1
                }
            case "--json":
                if i + 1 < args.count {
                    jsonExportPath = args[i + 1]
                    i += 1
                }
            case "--markdown":
                if i + 1 < args.count {
                    markdownExportPath = args[i + 1]
                    i += 1
                }
            case "--export-dir":
                if i + 1 < args.count {
                    exportDir = args[i + 1]
                    i += 1
                }
            case "--quiet":
                verbose = false
            default:
                break
            }
            i += 1
        }
        
        var workloads: [ANSISyntheticGenerator.Workload] = ANSISyntheticGenerator.Workload.allCases
        if let filter = workloadFilter, filter != "all" {
            if let matched = ANSISyntheticGenerator.Workload(rawValue: filter) {
                workloads = [matched]
            } else {
                print("⚠️ Unknown workload '\(filter)', defaulting to all workloads.")
            }
        }
        
        let options = PTYThroughputHarness.Options(
            iterations: iterations,
            targetBytesPerWorkload: bytesPerWorkloadMB * 1024 * 1024,
            workloads: workloads,
            verbose: verbose
        )
        
        let harness = PTYThroughputHarness(options: options)
        
        do {
            let report = try await harness.runSuite()
            
            // Handle directory export
            if let dir = exportDir {
                let fm = FileManager.default
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                jsonExportPath = "\(dir)/pty_throughput_report.json"
                markdownExportPath = "\(dir)/pty_throughput_report.md"
            }
            
            // Export JSON
            if let jsonPath = jsonExportPath {
                let json = report.toJSON()
                try json.write(toFile: jsonPath, atomically: true, encoding: .utf8)
                print("📄 Exported JSON benchmark report to: \(jsonPath)")
            }
            
            // Export Markdown
            if let mdPath = markdownExportPath {
                let md = report.toMarkdown()
                try md.write(toFile: mdPath, atomically: true, encoding: .utf8)
                print("📄 Exported Markdown benchmark report to: \(mdPath)")
            }
            
            if !report.overallPassed {
            print("❌ Benchmark did not meet baseline performance thresholds.")
            exit(1)
        } else {
            print("✅ Benchmark successfully met all baseline performance thresholds.")
            exit(0)
        }
    } catch {
        print("❌ Benchmark run failed with error: \(error)")
        exit(1)
    }
}

await runBenchmark()
