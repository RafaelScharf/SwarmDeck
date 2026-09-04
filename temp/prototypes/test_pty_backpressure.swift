import Foundation
import Darwin

@main
struct PTYBackpressureTests {
    static var passedCount = 0
    static var totalCount = 0

    static func assertTest(_ condition: Bool, _ description: String) {
        totalCount += 1
        if condition {
            passedCount += 1
            print("  ✓ PASS: \(description)")
        } else {
            print("  ✗ FAIL: \(description)")
            fatalError("Test assertion failed: \(description)")
        }
    }

    static func main() async throws {
        setbuf(stdout, nil)

        print("=================================================================")
        print(" SwarmDeck: PTY High-Throughput Backpressure & Stream Coalescing")
        print("=================================================================\n")

        // -------------------------------------------------------------
        // Test Group 1: Stream Coalescer Batching Behavior
        // -------------------------------------------------------------
        print("[Test Group 1: Stream Coalescer Batching Behavior]")
        let batchCounter = OutputBatchCounter()
        let coalescer = PTYStreamCoalescer(
            maxBufferSize: 16 * 1024,
            coalesceInterval: .milliseconds(20)
        ) { batch in
            await batchCounter.record(batch: batch)
        }

        // Pump 500 individual small chunks rapidly
        let chunkCount = 500
        let testChunk = "Lorem ipsum dolor sit amet, consectetur adipiscing elit.\n".data(using: .utf8)!
        let expectedTotalBytes = chunkCount * testChunk.count

        for _ in 0..<chunkCount {
            coalescer.yield(testChunk)
        }
        coalescer.finish()

        // Wait for pipeline to drain
        try await Task.sleep(for: .milliseconds(150))

        let totalDeliveredBytes = await batchCounter.totalBytes
        let totalBatches = await batchCounter.batchCount

        print("    Sent \(chunkCount) chunks (\(expectedTotalBytes) bytes) -> Received \(totalBatches) coalesced batches (\(totalDeliveredBytes) bytes)")
        assertTest(totalDeliveredBytes == expectedTotalBytes, "Zero data loss: all sent bytes successfully delivered")
        assertTest(totalBatches < chunkCount / 2, "Coalescer significantly reduced dispatch count (\(totalBatches) batches vs \(chunkCount) chunks)")

        // -------------------------------------------------------------
        // Test Group 2: OutputStateDetector Buffer Bounding Under Heavy Load
        // -------------------------------------------------------------
        print("\n[Test Group 2: Detector Memory Bounding Under Load]")
        let detector = OutputStateDetector()

        // Pump 2 MB of rapid text into detector
        let largeChunk = Data(repeating: UInt8(ascii: "A"), count: 64 * 1024) // 64 KB
        for _ in 0..<32 { // 32 * 64 KB = 2 MB
            await detector.feed(data: largeChunk)
        }

        // Feed prompt marker at the tail
        let promptMarker = "\n❯ Yes\n".data(using: .utf8)!
        await detector.feed(data: promptMarker)

        // Ensure state is .working while data was actively pouring
        let stateDuringBurst = await detector.currentState
        assertTest(stateDuringBurst == .working, "Detector identifies active burst as .working")

        // Wait for 250ms debounce quiescence window
        try await Task.sleep(for: .milliseconds(350))

        let quiescentState = await detector.currentState
        assertTest(quiescentState == .blocked(reason: "Confirmation Required"), "Evaluates prompt accurately on bounded tail buffer after quiescence")

        // -------------------------------------------------------------
        // Test Group 3: Real 50,000-Line High-Throughput PTY Stress Test
        // -------------------------------------------------------------
        print("\n[Test Group 3: 50,000-Line High-Throughput PTY Stress Test]")
        do {
            let ptyConfig = PTYConfiguration(
                command: "/bin/sh",
                arguments: ["-c", "seq 1 50000; echo 'DONE_SWARMDECK'; exit 0"]
            )
            let pty = try PTY(configuration: ptyConfig)
            let ptyDetector = OutputStateDetector()

            let ptyBatchCounter = OutputBatchCounter()
            let ptyCoalescer = PTYStreamCoalescer(
                maxBufferSize: 32 * 1024,
                coalesceInterval: .milliseconds(16)
            ) { batch in
                await ptyBatchCounter.record(batch: batch)
                await ptyDetector.feed(data: batch)
            }

            let startTimestamp = DispatchTime.now()

            let exitStream = AsyncStream<Int32> { cont in
                Task {
                    await pty.setOnData { data in
                        ptyCoalescer.yield(data)
                    }
                    await pty.setOnExit { exitCode in
                        ptyCoalescer.finish()
                        cont.yield(exitCode)
                        cont.finish()
                    }
                    await pty.start()
                }
            }

            var finalExitCode: Int32? = nil
            for await code in exitStream {
                finalExitCode = code
            }

            let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - startTimestamp.uptimeNanoseconds) / 1_000_000_000.0

            // Allow stream to flush final data
            try await Task.sleep(for: .milliseconds(100))

            let ptyTotalBytes = await ptyBatchCounter.totalBytes
            let ptyBatches = await ptyBatchCounter.batchCount
            let throughputMBs = (Double(ptyTotalBytes) / (1024.0 * 1024.0)) / elapsedSeconds

            print("    Processed 50,000 lines (\(ptyTotalBytes) bytes) in \(String(format: "%.2f", elapsedSeconds))s (\(String(format: "%.2f", throughputMBs)) MB/s)")
            print("    Coalesced into \(ptyBatches) batches (average \(ptyTotalBytes / max(1, ptyBatches)) bytes/batch)")

            assertTest(finalExitCode == 0, "PTY process completed successfully with exit code 0")
            assertTest(ptyTotalBytes > 250_000, "Received full 50,000 line dataset (>250KB stdout)")
            assertTest(ptyBatches < 5000, "Batches are constrained (<5000 dispatches for 50,000 lines)")

            // Clean zombie check
            var status: Int32 = 0
            let reaped = waitpid(pty.childPID, &status, WNOHANG)
            assertTest(reaped == -1 && errno == ECHILD, "High-throughput child process PID \(pty.childPID) cleanly reaped")
        } catch {
            fatalError("PTY stress test failed: \(error)")
        }

        print("\n=================================================================")
        print(" SUMMARY: \(passedCount)/\(totalCount) tests passed successfully!")
        print("=================================================================\n")
    }
}

actor OutputBatchCounter {
    var batchCount = 0
    var totalBytes = 0

    func record(batch: Data) {
        batchCount += 1
        totalBytes += batch.count
    }
}
