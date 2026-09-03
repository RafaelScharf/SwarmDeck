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
        if let stringChunk = String(data: data, encoding: .utf8) {
            if stringChunk.contains("\u{001B}]133;B\u{0007}") || stringChunk.contains("\u{001B}]133;B\u{001B}\\") {
                transition(to: .idle)
                return
            }
            if stringChunk.contains("\u{0007}") {
                transition(to: .blocked(reason: "Terminal Bell Alert"))
            }
        }
        
        buffer.append(data)
        if buffer.count > 8192 {
            buffer = buffer.suffix(8192)
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
        print("\n\n🟢 [STATE MACHINE DETECTED TRANSITION] \(currentState) ---> \(newState) 🟢\n")
        currentState = newState
        onStateChange?(newState)
    }
}

// MARK: - Interactive Runner
func printMenu() {
    print("""
    
    ================================================
    🤖 Interactive Agent State Detection Prototype
    ================================================
    Escolha uma ação para injetar na stream do PTY:
    
    1. Simular Aider boot & Idle Prompt (aider>)
    2. Simular animação de Spinner (\\r overwrites)
    3. Simular comando bloqueado (Allow? y/n)
    4. Simular OSC 133 Shell Integration
    5. Modo manual: Digite texto livre
    0. Sair
    
    > Escolha (0-5): \
    """, terminator: "")
}

Task {
    var running = true
    
    while running {
        printMenu()
        guard let choice = readLine() else { continue }
        
        let detector = OutputStateDetector()
        
        switch choice {
        case "1":
            print("\n> Injetando chunks...")
            let chunks = ["Initializing...\n", "Loading...\n", "aid", "er", "> "]
            for c in chunks {
                print(c, terminator: "")
                fflush(stdout)
                await detector.feed(data: c.data(using: .utf8)!)
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(500))
            
        case "2":
            print("\n> Injetando chunks de spinner...")
            let chunks = [
                "Processing... \u{1b}[32m[ \u{1b}[0m",
                "\rProcessing... \u{1b}[32m[=\u{1b}[0m",
                "\rProcessing... \u{1b}[32m[==\u{1b}[0m",
                "\rProcessing... \u{1b}[32m[===\u{1b}[0m",
                "\nDone!\n",
                "aider> "
            ]
            for c in chunks {
                // Ao imprimir o spinner com \r no terminal interativo real, vai sobrescrever!
                print(c, terminator: "")
                fflush(stdout)
                await detector.feed(data: c.data(using: .utf8)!)
                try? await Task.sleep(for: .milliseconds(300))
            }
            try? await Task.sleep(for: .milliseconds(500))
            
        case "3":
            print("\n> Injetando pedido de permissão...")
            await detector.feed(data: "Run command: rm -rf / ?\n".data(using: .utf8)!)
            print("Run command: rm -rf / ?")
            try? await Task.sleep(for: .milliseconds(100))
            
            await detector.feed(data: "Allow? (y/n): ".data(using: .utf8)!)
            print("Allow? (y/n): ", terminator: "")
            fflush(stdout)
            try? await Task.sleep(for: .milliseconds(500))
            
        case "4":
            print("\n> Injetando OSC 133 (Invisível na tela, mas lido pelo detector)...")
            let chunk = "\n\u{1b}]133;A\u{7}user@host $ "
            print("user@host $ ", terminator: "")
            fflush(stdout)
            await detector.feed(data: chunk.data(using: .utf8)!)
            try? await Task.sleep(for: .milliseconds(100))
            
            await detector.feed(data: "\u{1b}]133;B\u{7}".data(using: .utf8)!)
            try? await Task.sleep(for: .milliseconds(500))
            
        case "5":
            print("\n> Modo manual ativado. Escreva linhas. Digite 'voltar' para sair do modo manual.")
            let manualDetector = OutputStateDetector()
            while true {
                print(">> ", terminator: "")
                guard let input = readLine() else { continue }
                if input.lowercased() == "voltar" { break }
                
                await manualDetector.feed(data: input.data(using: .utf8)!)
                // Espera um pouco pra dar o tempo do debounce atuar e printar na tela
                try? await Task.sleep(for: .milliseconds(350))
            }
            
        case "0":
            running = false
            print("Saindo...")
            exit(0)
            
        default:
            print("Opção inválida.")
        }
    }
}
RunLoop.main.run()
