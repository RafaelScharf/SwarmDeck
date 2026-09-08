#!/usr/bin/env swift
import Foundation

// Benchmark runner script for SwarmDeck Latency and Metal Frame Pacing (Issue #37)
let currentDir = FileManager.default.currentDirectoryPath
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.currentDirectoryURL = URL(fileURLWithPath: currentDir)

var args = ["run", "LatencyPacingBenchmark"]
args.append(contentsOf: CommandLine.arguments.dropFirst())

process.arguments = args
process.standardInput = FileHandle.standardInput
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError

do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    fputs("Error executing benchmark harness: \(error.localizedDescription)\n", stderr)
    exit(1)
}
