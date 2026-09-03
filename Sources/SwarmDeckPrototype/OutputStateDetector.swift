import Foundation

// MARK: - State Definition
public enum AgentState: Equatable, Sendable, CustomStringConvertible {
    case working
    case idle
    case blocked(reason: String)
    case exited(code: Int32)
    
    public var description: String {
        switch self {
        case .working: return "Working"
        case .idle: return "Idle"
        case .blocked(let reason): return "Blocked (\(reason))"
        case .exited(let code): return "Exited (\(code))"
        }
    }
}

// MARK: - OutputStateDetector Actor
public actor OutputStateDetector {
    private var buffer: Data = Data()
    private var debounceTask: Task<Void, Never>?
    public private(set) var currentState: AgentState = .idle
    
    public var onStateChange: (@Sendable (AgentState) -> Void)?
    
    // Configurable debounce duration (250ms is optimal for LLM streaming gaps)
    private let debounceDuration: Duration = .milliseconds(250)
    
    // Compiled Regexes
    private let ansiRegex = try! NSRegularExpression(
        pattern: "\u{001B}(?:[@-Z\\\\-_]|\\[[0-?]*[ -/]*[@-~]|\\][^\\x07]*?(?:\\x07|\u{001B}\\\\))"
    )
    private let blockedRegex = try! NSRegularExpression(
        pattern: #"(?i)(?:do you want to (?:run|execute|proceed)|allow (?:this |execution)|confirm command|apply (?:these )?changes|proceed\?|\(y\/n\)|\(y\)es\/\(n\)o|\[y\/n\]|\[y\/N\]|\[Y\/n\]|^\s*❯\s*(?:\d+\.\s*)?Yes)"#
    )
    private let idlePromptRegex = try! NSRegularExpression(
        pattern: #"(?m)(?:^|[\r\n])\s*(?:❯|›|>|\$|➜)\s*$"#
    )
    private let busyRegex = try! NSRegularExpression(
        pattern: #"[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|(?i)\b(?:thinking|generating|running|searching)\b\.{1,3}"#
    )
    
    public init() {}
    
    public func feed(data: Data) {
        // Fast-path: Check for explicit escape signals in raw bytes
        if let stringChunk = String(data: data, encoding: .utf8) {
            // Check for OSC 133;B (Prompt End / Input Start)
            if stringChunk.contains("\u{001B}]133;B\u{0007}") || stringChunk.contains("\u{001B}]133;B\u{001B}\\") {
                transition(to: .idle)
                return
            }
            // Check for BEL (Approval alert)
            if stringChunk.contains("\u{0007}") {
                transition(to: .blocked(reason: "Terminal Bell Alert"))
            }
        }
        
        // Append to rolling buffer (keep last 8KB)
        buffer.append(data)
        if buffer.count > 8192 {
            buffer = buffer.suffix(8192)
        }
        
        // While bytes are actively streaming, state is working
        if currentState != .working, case .blocked = currentState {
            // do not transition from blocked to working automatically
        } else if currentState != .working {
            transition(to: .working)
        }
        
        // Reset debounce timer
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceDuration ?? .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.evaluateQuiescentBuffer()
        }
    }
    
    private func evaluateQuiescentBuffer() {
        guard let text = String(data: buffer, encoding: .utf8) else { return }
        
        // 1. Resolve carriage returns (\r) and extract active tail
        let lines = text.components(separatedBy: "\n")
        guard let lastLineRaw = lines.last(where: { !$0.isEmpty }) else { return }
        
        // The last segment after \r is what is visible on the line
        let visibleSegment = lastLineRaw.components(separatedBy: "\r").last ?? lastLineRaw
        
        // 2. Strip ANSI
        let cleanLine = ansiRegex.stringByReplacingMatches(
            in: visibleSegment,
            range: NSRange(location: 0, length: visibleSegment.utf16.count),
            withTemplate: ""
        )
        
        // Also clean the last 5 lines for multiline permission dialogs
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
        
        // 3. Priority Evaluation:
        // A. Is it busy? (If spinners/thinking remain visible, remain working)
        if busyRegex.firstMatch(in: multiLineTail, range: fullRange) != nil {
            transition(to: .working)
            return
        }
        
        // B. Is it blocked on approval/confirmation?
        if blockedRegex.firstMatch(in: multiLineTail, range: fullRange) != nil {
            transition(to: .blocked(reason: "Confirmation Required"))
            return
        }
        
        // C. Is it sitting at an idle prompt?
        if idlePromptRegex.firstMatch(in: cleanLine, range: lineRange) != nil {
            transition(to: .idle)
            return
        }
        
        // Default: If silent for 250ms and no other pattern matches, assume idle
        transition(to: .idle)
    }
    
    private func transition(to newState: AgentState) {
        guard currentState != newState else { return }
        currentState = newState
        onStateChange?(newState)
    }
}
