import Foundation

public enum AgentState: Equatable, Sendable, CustomStringConvertible {
    case working
    case idle
    case blocked(reason: String)
    case exited(code: Int32)
    
    public var description: String {
        switch self {
        case .working: return "working"
        case .idle: return "idle"
        case .blocked(let reason): return "blocked(\(reason))"
        case .exited(let code): return "exited(\(code))"
        }
    }
}

public actor OutputStateDetector {
    private var buffer: Data = Data()
    private var debounceTask: Task<Void, Never>?
    public private(set) var currentState: AgentState = .idle
    
    private var onStateChangeCallback: (@Sendable (AgentState) -> Void)?
    
    // Configurable debounce duration (250ms is optimal for LLM streaming gaps)
    private let debounceDuration: Duration = .milliseconds(250)
    
    public func setOnStateChange(_ callback: @escaping @Sendable (AgentState) -> Void) {
        self.onStateChangeCallback = callback
    }
    
    // Compiled Regexes
    private let ansiRegex = try! NSRegularExpression(
        pattern: "\u{001B}(?:[@-Z\\\\-_]|\\[[0-?]*[ -/]*[@-~]|\\][^\\x07]*?(?:\\x07|\u{001B}\\\\))"
    )
    private let blockedRegex = try! NSRegularExpression(
        pattern: #"(?im)(?:do you want to (?:run|execute|proceed)|allow (?:this |execution)|confirm command|apply (?:these )?changes|proceed\?|\(y\/n\)|\(y\)es\/\(n\)o|\[y\/n\]|\[y\/N\]|\[Y\/n\]|^\s*❯\s*(?:\d+\.\s*)?Yes)"#
    )
    private let idlePromptRegex = try! NSRegularExpression(
        pattern: #"(?m)(?:^|[\r\n])\s*(?:❯|›|>|\$|➜|%)\s*$"#
    )
    private let busyRegex = try! NSRegularExpression(
        pattern: #"[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|(?i)\b(?:thinking|generating|running|searching)\b\.{1,3}"#
    )
    
    public init() {}
    
    public func feed(data: Data) {
        buffer.append(data)
        if buffer.count > 16384 {
            buffer = buffer.suffix(16384)
        }
        
        // Check tail segment of incoming chunk for OSC 133 semantic prompt markers or bell
        let tailData = data.count > 4096 ? data.suffix(4096) : data
        if let stringChunk = String(data: tailData, encoding: .utf8) {
            if stringChunk.contains("\u{001B}]133;B\u{0007}") || stringChunk.contains("\u{001B}]133;B\u{001B}\\") {
                transition(to: .idle)
                return
            }
            if stringChunk.contains("\u{0007}") {
                transition(to: .blocked(reason: "Terminal Bell Alert"))
            }
        }
        
        if currentState != .working, case .blocked = currentState {
            // do not transition automatically
        } else if currentState != .working {
            transition(to: .working)
        }
        
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceDuration ?? .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.evaluateQuiescentBuffer()
        }
    }
    
    private func evaluateQuiescentBuffer() {
        guard let text = String(data: buffer, encoding: .utf8) else { return }
        
        let lines = text.components(separatedBy: "\n")
        guard let lastLineRaw = lines.last(where: { !$0.isEmpty }) else { return }
        let visibleSegment = lastLineRaw.components(separatedBy: "\r").last ?? lastLineRaw
        
        let cleanLine = ansiRegex.stringByReplacingMatches(
            in: visibleSegment,
            range: NSRange(location: 0, length: visibleSegment.utf16.count),
            withTemplate: ""
        )
        
        let multiLineTail = lines.suffix(5).map { line in
            let seg = line.components(separatedBy: "\r").last ?? line
            return ansiRegex.stringByReplacingMatches(
                in: seg,
                range: NSRange(location: 0, length: seg.utf16.count),
                withTemplate: ""
            )
        }.joined(separator: "\n")
        
        let fullRange = NSRange(location: 0, length: multiLineTail.utf16.count)
        let lineRange = NSRange(location: 0, length: cleanLine.utf16.count)
        
        if busyRegex.firstMatch(in: multiLineTail, range: fullRange) != nil {
            transition(to: .working)
            return
        }
        
        if blockedRegex.firstMatch(in: multiLineTail, range: fullRange) != nil {
            transition(to: .blocked(reason: "Confirmation Required"))
            return
        }
        
        if idlePromptRegex.firstMatch(in: cleanLine, range: lineRange) != nil {
            transition(to: .idle)
            return
        }
        
        transition(to: .idle)
    }
    
    private func transition(to newState: AgentState) {
        guard currentState != newState else { return }
        currentState = newState
        onStateChangeCallback?(newState)
    }
}
