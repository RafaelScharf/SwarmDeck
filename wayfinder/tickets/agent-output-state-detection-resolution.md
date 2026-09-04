---
type: research-resolution
ticket: agent-output-state-detection
status: resolved
date: 2026-09-03
---

# Agent Output State Detection: Technical Resolution & Implementation Guide

## 1. Executive Summary

Detecting when an arbitrary AI coding agent (Claude Code, Aider, Antigravity, or other CLI agents) is **"Waiting for User Input"** (Idle/Ready) or **"Blocked"** (Awaiting Tool Approval/Clarification) cannot be achieved reliably with a single naive regex on the raw PTY stdout stream. 

Modern AI agents are full Terminal User Interface (TUI) applications (built with React/Ink, Python `prompt_toolkit`, or Rich/Textual) rather than simple line-based REPLs. They employ:
1. Dynamic cursor positioning (`\x1b[<row>;<col>H`, `\x1b[1A`)
2. In-place line overwrites via carriage returns (`\r`) and erase sequences (`\x1b[2K`)
3. Cursor hiding (`\x1b[?25l`) during generation and cursor restoration (`\x1b[?25h`) when input is requested
4. Chunked, multi-byte UTF-8 and ANSI streaming from the PTY master file descriptor

To achieve 100% reliable state detection in **SwarmDeck** with zero false positives, we must implement a **Multi-Tier Detection Pipeline**:
- **Tier 1 (I/O Quiescence & Debouncing):** Filter out intermediate streaming pauses (200–300ms silence window).
- **Tier 2 (Semantic Escape Sequences):** Monitor native protocols such as **OSC 133** (Shell Integration) and **BEL (`\x07`)** terminal bells.
- **Tier 3 (ANSI Normalization & Trailing Text Parsing):** Resolve `\r` overwrites, strip ANSI sequences, and check for the "No Trailing Newline" invariant.
- **Tier 4 (Targeted Regex Classification):** Classify the normalized tail into `Blocked` (requires human permission/action) vs `Idle` (ready for next prompt) vs `Working` (active spinner or thinking).
- **Tier 5 (libghostty Terminal State Query):** Use libghostty's internal grid/cursor state as ground truth for visible lines.

---

## 2. Agent Output Behavior Breakdown

### 2.1. Claude Code
- **Engine/Framework:** Built with **Ink** (React for CLI).
- **Normal Input Prompt:**
  - Emits a sticky bottom prompt box or separator (`╭───`, `╰───`).
  - Active input glyph: `❯ ` (`\u{276F}\u{0020}`) or `› ` (`\u{203A}\u{0020}`).
  - Placeholder text when empty: `Type a message...` or `Ask Claude...`.
  - Crucial ANSI behavior: Sends `\x1b[?25h` (show cursor) immediately after placing the cursor after `❯ `.
- **Blocked / Permission Prompts:**
  - Halts execution when running Bash commands, editing critical files, or fetching web content.
  - Distinctive question prompts:
    - `"Do you want to run this command?"`
    - `"Allow this bash command?"`
    - `"Allow [tool_name]?"`
  - Rendered interactive menu choices (Ink `SelectInput`):
    - `❯ 1. Yes`
    - `❯ 2. Yes, and don't ask again`
    - `❯ 3. No`
    - Or arrow-navigable lists: `❯ Yes` / `  No`
  - Audio/Escape trigger: Emits `\x07` (`\a` / Terminal Bell) on blocking permission prompts (if terminal bell notifications are enabled).
  - Shell Integration: Emits **OSC 133** accessibility markers at turn boundaries (`\x1b]133;A\x07` for prompt start, `\x1b]133;B\x07` for input start).

### 2.2. Aider
- **Engine/Framework:** Built with **Python `prompt_toolkit`** and **`rich`**.
- **Normal Input Prompt:**
  - Classic REPL prompt: `> ` (or `{file} > ` or `aider> `).
  - Terminal state: During LLM streaming, cursor is hidden (`\x1b[?25l`). When streaming completes, Rich flushes output, `prompt_toolkit` shows the cursor (`\x1b[?25h`), prints `> `, and blocks on `select()` on stdin.
- **Blocked / Confirmation Prompts:**
  - Prompt format:
    - `Add {file} to the chat? (Y)es/(N)o [Yes]:`
    - `Run shell command? (Y)es/(N)o [Yes]:`
    - `(Y)es/(N)o/(D)on't ask again [Yes]:`
    - `Apply edits to {file}? [y/n]:`
  - Terminal Bell: Aider natively supports emitting `\a` upon task completion / notification when `--notifications` is enabled.

### 2.3. Antigravity CLI / Gemini CLI
- **Engine/Framework:** Custom TUI with a sticky bottom panel.
- **Normal Input Prompt:**
  - Bottom input line with prompt glyph: `❯ ` or input box placeholder: `Ask anything...` / `Type your prompt...`.
- **Blocked / Approval Prompts:**
  - Tool execution confirmation:
    - `"Allow execution of: <command>"`
    - `"Confirm command: [y/n]"`
    - Modal options: `[Yes]   [No]`

---

## 3. Standard ANSI & Semantic Escape Protocols

These escape sequences provide explicit, machine-readable state boundaries before any regex matching is needed:

| Escape Sequence | Name / Standard | State Indicated | Description |
|---|---|---|---|
| `\x1b]133;A\x07` | OSC 133;A | **Prompt Rendering** | FinalTerm / Semantic Shell Integration: Prompt is starting to draw. |
| `\x1b]133;B\x07` | OSC 133;B | **Idle / Waiting for Input** | **Gold standard.** Prompt rendering is complete; process is now waiting for user keystrokes. |
| `\x1b]133;C\x07` | OSC 133;C | **Working** | User pressed Enter; command/turn execution has started. |
| `\x1b]133;D[;exit]\x07` | OSC 133;D | **Turn Complete** | Command or agent turn has finished; returning to prompt. |
| `\x07` (`\a`) | ASCII BEL | **Blocked / Attention** | Emitted by Claude Code, Aider, and Unix tools when blocked on approval or task complete. |
| `\x1b[?25h` | DECTCSR (Show Cursor) | **Interactive Ready** | TUIs hide the cursor (`\x1b[?25l`) while computing/spinning and unhide it (`\x1b[?25h`) when waiting for input. |
| `\x1b[?25l` | DECTCSR (Hide Cursor) | **Busy / Processing** | Indicates active spinner, streaming text, or tool execution. |
| `\x1b[?2004h` | Bracketed Paste Mode | **Interactive Ready** | REPL frameworks enable bracketed paste when accepting user input. |
| `\x1b[6n` | DSR (Cursor Report) | **Interactive Prep** | Ink and prompt_toolkit emit this right before rendering interactive menus. |

> **Note on Ghostty:** Because SwarmDeck uses `libghostty`, Ghostty natively understands and parses OSC 133 sequences.

---

## 4. Normalization Pipeline: Handling ANSI and Carriage Returns

Raw PTY output is heavily polluted with ANSI sequences and carriage returns. If an agent writes:
```text
Thinking...\r                \r❯ 
```
Stripping ANSI without handling `\r` leaves `Thinking...                ❯ `, which can cause regexes to falsely detect "Thinking".

### 4.1. ANSI Stripping Regex (Swift)
```swift
// Matches CSI (ESC [ ...), OSC (ESC ] ... BEL/ST), and 2-byte escape sequences
let ansiPattern = #"\u{001B}(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\].*?(?:\u{0007}|\u{001B}\\))"#
```

### 4.2. Carriage Return (`\r`) Normalization Algorithm
When a terminal receives `\r` (without `\n`), it moves the cursor to column 0 of the current line, allowing subsequent text to overwrite previous text.
To extract the **actual visible last line**:
1. Split the raw buffer by `\n` into lines.
2. Take the last non-empty line.
3. Split that line by `\r`. The **last non-empty segment** represents the active line after all overwrites.
4. Strip ANSI escape sequences from that segment.
5. Trim trailing whitespace (except when checking for prompt space).

### 4.3. The "No Trailing Newline" Invariant
- When an AI agent outputs markdown, code, or logs, lines end with `\n` or `\r\n`.
- When an AI agent is **waiting for user input**, the PTY stdout stream **DOES NOT end with a newline**. The cursor remains stationed immediately after the prompt glyph or input placeholder.
- **Rule:** If the buffer ends with `\n` and has been silent, the agent is likely idle after printing, but if it ends with `❯ ` or `> ` *without a trailing newline*, it is unambiguously waiting at a prompt.

---

## 5. Regular Expression Catalog for Agent State Classification

The detector classifies normalized text into three states:

### 5.1. State: `Blocked` (Action Required — Red Badge / Push Notification)
Matches when an agent is paused awaiting user confirmation, permission, or a selection:

```regex
(?i)(?:do you want to (?:run|execute|proceed|continue)|allow (?:this |execution of )?(?:bash command|tool|operation)?|confirm (?:command|action)|apply (?:these )?(?:edits?|changes?)|proceed\?|\(y\/n\)|\(y\)es\/\(n\)o(?:/\(d\)on't ask again)?|\[y\/n\]|\[y\/N\]|\[Y\/n\]|\bpassword:|\bpress enter to continue|esc to cancel)
```

**Specific TUI Menu Patterns (Claude Code Ink Selectors):**
```regex
(?m)^\s*❯\s*(?:\d+\.\s*)?(?:Yes|Allow|Proceed|Accept)\b
```

### 5.2. State: `Idle` (Ready for Input — Amber/Neutral Badge)
Matches standard interactive prompt glyphs positioned at the end of the visible text without subsequent commands:

```regex
(?m)(?:^|[\r\n])\s*(?:❯|›|>|\$|#|%|➜|»|\?)\s*$
```

**Placeholder Text Patterns:**
```regex
(?i)(?:type a message|ask anything|send a message|type your prompt)\.{0,3}\s*$
```

### 5.3. State: `Working` (Busy — Green Badge / Spinner Indicator)
Negative-matching filter to prevent false positives when words like `>` appear in streaming markdown:

```regex
[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|(?i)\b(?:thinking|generating|processing|running tool|executing|working|searching|indexing)\b\.{1,3}
```

---

## 6. Architecture for SwarmDeck (Swift + libghostty)

### 6.1. Detection State Machine
```
                       Raw PTY stdout Stream
                                │
                                ├──► [libghostty Terminal] ──► Metal Render Surface
                                │
                                ▼
               ┌─────────────────────────────────┐
               │    OutputStateDetector Actor    │
               └────────────────┬────────────────┘
                                │
         [Contains OSC 133;B?] ─┼─► YES ──► State: .idle
         [Contains BEL (\x07)?] ─┼─► Flag ──► State: .blocked(reason: "Alert")
                                │
                       (Debounce: 250ms silence)
                                │
                                ▼
               ┌─────────────────────────────────┐
               │   Tail Extraction & Cleaning    │
               │  - Last 2KB of stream           │
               │  - Split \r -> last segment     │
               │  - Strip ANSI regex             │
               └────────────────┬────────────────┘
                                │
               ┌────────────────┼────────────────┐
               ▼                ▼                ▼
        Matches Blocked?   Matches Idle?   Matches Working?
               │                │                │
               ▼                ▼                ▼
         🔴 BLOCKED         🟡 IDLE          🟢 WORKING
       (Notification,      (Badge: Amber,   (Badge: Green,
        Badge: Red)         Ready)           Spinner)
```

### 6.2. Swift Actor Implementation Blueprint

```swift
import Foundation

public enum AgentState: Equatable, Sendable {
    case working
    case idle
    case blocked(reason: String)
    case exited(code: Int32)
}

public actor OutputStateDetector {
    private var buffer: Data = Data()
    private var debounceTask: Task<Void, Never>?
    private var currentState: AgentState = .idle
    
    public var onStateChange: (@Sendable (AgentState) -> Void)?
    
    // Configurable debounce duration (250ms is optimal for LLM streaming gaps)
    private let debounceDuration: Duration = .milliseconds(250)
    
    // Compiled Regexes
    private let ansiRegex = try! NSRegularExpression(
        pattern: #"\u{001B}(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\].*?(?:\u{0007}|\u{001B}\\))"#
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
        if currentState != .working && currentState != .blocked(reason: "Terminal Bell Alert") {
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
```

---

## 7. Edge Cases & Mitigations Summary

1. **LLM Chunk Delays (Token Stutter):**  
   *Risk:* LLMs pause for 100ms between tokens; detector might trigger prematurely.  
   *Mitigation:* 250ms debounce window guarantees that only genuine pauses trigger evaluation.
2. **Markdown Blockquotes & CLI Examples in Output:**  
   *Risk:* Model prints `> cargo test` in response markdown.  
   *Mitigation:* Streaming markdown ends with `\n`, whereas interactive prompts have no trailing newline. Furthermore, while generating, cursor is hidden (`\x1b[?25l`).
3. **Carriage Return Animation Spinners:**  
   *Risk:* Previous lines contain prompt characters that were subsequently overwritten.  
   *Mitigation:* Split line by `\r` and take the final segment.
4. **Multibyte UTF-8 Boundary Splitting:**  
   *Risk:* `❯` (`\xE2\x9D\xAF`) is split across two PTY chunks.  
   *Mitigation:* Rolling 8KB `Data` buffer preserves contiguous byte streams; regex operates on decoded UTF-8 string only during debounce.

---

## 8. Final Recommendation for SwarmDeck

1. **Adopt the Multi-Tier Pipeline:** Implement the `OutputStateDetector` actor in Swift to wrap every background PTY master.
2. **Wire System Notifications:** When `state == .blocked(...)`, trigger macOS `UNUserNotificationCenter` and a red badge in the sidebar. When `state == .idle`, clear the alert badge and show a neutral/amber dot.
3. **Use Manifest-Driven Rules:** Allow regex definitions to be stored in an external configuration (e.g. `AgentRules.json` or `AgentRules.toml` modeled after Herdr), enabling zero-recompile additions of future AI agents.
