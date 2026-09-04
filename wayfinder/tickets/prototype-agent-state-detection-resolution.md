---
type: prototype-resolution
ticket: issue-3
status: resolved
date: 2026-09-03
url: https://github.com/RafaelScharf/SwarmDeck/issues/3
branch: prototype/issue-3-state-detector
artifacts: temp/prototypes/prototype_state_detector.swift
---

# Resolution: Prototype - Agent State Detection Engine

## Question
Does the proposed Multi-Tier Detection Pipeline (debounce, OSC 133, ANSI stripping, regex) reliably detect agent states without false positives?

## Findings & Resolution
1. **Debounce for LLM Streaming Gaps:**
   - Raw tokens and chunks arrive piecemeal. A 250ms quiescence debounce window successfully prevents spurious state transitions while keeping the UI responsive.
2. **Carriage Return & ANSI Handling:**
   - CLI spinners and interactive prompts repeatedly emit `\r` without `\n`. Isolating `line.components(separatedBy: "\r").last` accurately extracts the visible text on the line.
   - ANSI escape sequences are stripped via compiled regex before matching.
3. **Semantic Shell Prompts & Alerts:**
   - OSC 133 prompt markers (`\u{001B}]133;B\u{0007}`) provide instant transitions to `.idle`.
   - Terminal bell (`\u{0007}`) immediately transitions to `.blocked(reason: "Terminal Bell Alert")`.
4. **State Taxonomy:**
   - Evaluates to `.working` (spinners, thinking/generating keywords), `.blocked` (permission queries like `(y/n)`, `allow execution`), or `.idle` (shell prompts `❯`, `$`).

## Archived Spike Artifacts
- `temp/prototypes/prototype_state_detector.swift` (Interactive CLI simulator and test runner).
