import Foundation

/// High-density synthetic ANSI data generator simulating real-world and adversarial agent terminal workloads.
public struct ANSISyntheticGenerator: Sendable {
    
    public enum Workload: String, CaseIterable, Codable, Sendable {
        case denseText = "dense"
        case trueColor = "truecolor"
        case cursorTUI = "cursor"
        case diffBurst = "diff"
        
        public var displayName: String {
            switch self {
            case .denseText: return "Dense UTF-8 Text (Cat/Logs)"
            case .trueColor: return "24-bit TrueColor Matrix"
            case .cursorTUI: return "Cursor Repositioning & Selective Erasure"
            case .diffBurst: return "Syntax Diffs (Git/Patch)"
            }
        }
    }
    
    public init() {}
    
    /// Generates dense UTF-8 text with randomized line lengths between 80 and 200 characters.
    public func generateDenseText(targetBytes: Int) -> Data {
        var data = Data()
        data.reserveCapacity(targetBytes + 4096)
        
        let sampleWords = [
            "autonomous", "agent", "multiplexer", "throughput", "concurrency",
            "backpressure", "coalescing", "libghostty", "mach_absolute_time",
            "terminal", "stream", "pipeline", "buffer", "allocation", "footprint",
            "compilation", "diagnostics", "optimization", "subagent", "dispatch"
        ]
        
        var currentBytes = 0
        var lineIndex = 1
        
        while currentBytes < targetBytes {
            var line = "[\(String(format: "%06d", lineIndex))] "
            let targetCols = 80 + (lineIndex % 120)
            while line.count < targetCols {
                line.append(sampleWords[(lineIndex + line.count) % sampleWords.count])
                line.append(" ")
            }
            line.append("\n")
            
            if let lineData = line.data(using: .utf8) {
                data.append(lineData)
                currentBytes += lineData.count
            }
            lineIndex += 1
        }
        
        return data.prefix(targetBytes)
    }
    
    /// Generates high-density 24-bit TrueColor ANSI escape sequences: `\x1b[38;2;R;G;Bm` and `\x1b[48;2;R;G;Bm`.
    public func generateTrueColorMatrix(targetBytes: Int) -> Data {
        var data = Data()
        data.reserveCapacity(targetBytes + 4096)
        
        var currentBytes = 0
        var step = 0
        
        while currentBytes < targetBytes {
            let r = UInt8((step * 7) % 256)
            let g = UInt8((step * 13) % 256)
            let b = UInt8((step * 29) % 256)
            let bgR = 255 - r
            let bgG = 255 - g
            let bgB = 255 - b
            
            let seq = "\u{001B}[38;2;\(r);\(g);\(b)m\u{001B}[48;2;\(bgR);\(bgG);\(bgB)m[RGB:\(r),\(g),\(b)]\u{001B}[0m "
            if let seqData = seq.data(using: .utf8) {
                data.append(seqData)
                currentBytes += seqData.count
            }
            
            if step % 16 == 0 {
                data.append(contentsOf: [0x0A]) // Newline
                currentBytes += 1
            }
            step += 1
        }
        
        return data.prefix(targetBytes)
    }
    
    /// Generates rapid cursor repositioning and selective line/screen erasure escape codes.
    public func generateCursorTUI(targetBytes: Int) -> Data {
        var data = Data()
        data.reserveCapacity(targetBytes + 4096)
        
        var currentBytes = 0
        var frame = 0
        
        while currentBytes < targetBytes {
            var frameBuffer = "\u{001B}[H\u{001B}[2J" // Cursor home + clear screen
            for row in 1...24 {
                let col = (frame + row * 3) % 80 + 1
                frameBuffer += "\u{001B}[\(row);\(col)H\u{001B}[K" // Move to row,col and erase line
                frameBuffer += "\u{001B}[1;32m● Process #\(row): CPU \(col)% MEM \(row * 4)MB\u{001B}[0m"
            }
            frameBuffer += "\n"
            
            if let frameData = frameBuffer.data(using: .utf8) {
                data.append(frameData)
                currentBytes += frameData.count
            }
            frame += 1
        }
        
        return data.prefix(targetBytes)
    }
    
    /// Generates massive syntax-highlighted git diffs with hunks, additions, deletions, and file headers.
    public func generateDiffBurst(targetBytes: Int) -> Data {
        var data = Data()
        data.reserveCapacity(targetBytes + 4096)
        
        var currentBytes = 0
        var fileIdx = 1
        
        while currentBytes < targetBytes {
            let diffChunk = """
            \u{001B}[1;37mdiff --git a/Sources/Module\(fileIdx)/File\(fileIdx).swift b/Sources/Module\(fileIdx)/File\(fileIdx).swift\u{001B}[0m
            \u{001B}[1mindex a1b2c3d..e4f5a6b 100644\u{001B}[0m
            \u{001B}[1;37m--- a/Sources/Module\(fileIdx)/File\(fileIdx).swift\u{001B}[0m
            \u{001B}[1;37m+++ b/Sources/Module\(fileIdx)/File\(fileIdx).swift\u{001B}[0m
            \u{001B}[36m@@ -120,8 +120,10 @@ public actor WorkerService\(fileIdx) {\u{001B}[0m
              public func processStream() async throws {
            \u{001B}[31m-    let legacyBuffer = UnsafeMutableRawPointer.allocate(byteCount: 1024, alignment: 1)\u{001B}[0m
            \u{001B}[31m-    defer { legacyBuffer.deallocate() }\u{001B}[0m
            \u{001B}[32m+    let modernStream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(2000))\u{001B}[0m
            \u{001B}[32m+    let coalescer = PTYStreamCoalescer(maxBufferSize: 65536)\u{001B}[0m
            \u{001B}[32m+    await coalescer.yield(modernStream)\u{001B}[0m
                  return true
              }
            
            """
            
            if let chunkData = diffChunk.data(using: .utf8) {
                data.append(chunkData)
                currentBytes += chunkData.count
            }
            fileIdx += 1
        }
        
        return data.prefix(targetBytes)
    }
    
    /// Generates dataset for the requested workload.
    public func generate(workload: Workload, targetBytes: Int) -> Data {
        switch workload {
        case .denseText: return generateDenseText(targetBytes: targetBytes)
        case .trueColor: return generateTrueColorMatrix(targetBytes: targetBytes)
        case .cursorTUI: return generateCursorTUI(targetBytes: targetBytes)
        case .diffBurst: return generateDiffBurst(targetBytes: targetBytes)
        }
    }
}
