import Foundation
import Darwin
import AppKit
@testable import SwarmDeck

@main
struct SidebarNavigationUXTests {
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

    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)

        print("=================================================================")
        print(" SwarmDeck: Session Multiplexer Sidebar & Navigation UX Tests")
        print("=================================================================\n")

        let store = SessionStore()

        // -------------------------------------------------------------
        // Test Group 1: Agent Presets & Icons
        // -------------------------------------------------------------
        print("[Test Group 1: Agent Presets & Icons]")
        
        let standardPresets = AgentPreset.allStandard
        assertTest(standardPresets.count == 4, "4 standard presets configured")
        
        let shell = AgentPreset.standardShell
        assertTest(shell.iconName == "apple.terminal", "Standard Shell uses 'apple.terminal' icon")
        assertTest(!shell.command.isEmpty, "Shell command resolved to valid path (\(shell.command))")
        
        let claude = AgentPreset.claudeCode
        assertTest(claude.iconName == "brain.head.profile", "Claude Code uses 'brain.head.profile' icon")
        
        let aider = AgentPreset.aider
        assertTest(aider.iconName == "sparkles", "Aider uses 'sparkles' icon")
        
        let agy = AgentPreset.antigravity
        assertTest(agy.iconName == "bolt.horizontal", "Antigravity uses 'bolt.horizontal' icon")
        
        let custom = AgentPreset.custom(
            name: "Python Worker",
            command: "/usr/bin/python3",
            arguments: ["-m", "http.server", "8000"],
            workingDirectory: "/tmp"
        )
        assertTest(custom.iconName == "slider.horizontal.3", "Custom preset uses 'slider.horizontal.3' icon")
        assertTest(custom.workingDirectory == "/tmp", "Custom working directory recorded accurately")

        // -------------------------------------------------------------
        // Test Group 2: Session Spawning & Metadata
        // -------------------------------------------------------------
        print("\n[Test Group 2: Session Spawning & Metadata]")
        
        let id1 = await store.addSession(preset: .standardShell, customName: "Session Alpha")
        assertTest(store.sessions.count == 1, "SessionStore contains 1 session after spawn")
        assertTest(store.selectedSessionId == id1, "First spawned session is automatically selected")
        assertTest(store.activeSession?.id == id1, "activeSession points to Session Alpha")
        assertTest(store.activeSession?.name == "Session Alpha", "Session Alpha name matches")
        
        let id2 = await store.addSession(preset: .claudeCode, customName: "Session Beta")
        let id3 = await store.addSession(preset: .aider, customName: "Session Gamma")
        let id4 = await store.addSession(preset: .antigravity, customName: "Session Delta")
        
        assertTest(store.sessions.count == 4, "SessionStore contains 4 multiplexed sessions")
        assertTest(store.selectedSessionId == id4, "Latest spawned session is automatically selected")

        // -------------------------------------------------------------
        // Test Group 3: Keyboard Navigation by Index (Cmd+1..Cmd+9)
        // -------------------------------------------------------------
        print("\n[Test Group 3: Keyboard Navigation by Index (Cmd+1..Cmd+9)]")
        
        // Cmd+1 -> index 0 (Session Alpha)
        store.selectSession(at: 0)
        assertTest(store.selectedSessionId == id1, "Cmd+1 selects Session Alpha (index 0)")
        assertTest(store.activeSession?.name == "Session Alpha", "activeSession is Session Alpha")
        
        // Cmd+2 -> index 1 (Session Beta)
        store.selectSession(at: 1)
        assertTest(store.selectedSessionId == id2, "Cmd+2 selects Session Beta (index 1)")
        assertTest(store.activeSession?.name == "Session Beta", "activeSession is Session Beta")
        
        // Cmd+3 -> index 2 (Session Gamma)
        store.selectSession(at: 2)
        assertTest(store.selectedSessionId == id3, "Cmd+3 selects Session Gamma (index 2)")
        
        // Cmd+4 -> index 3 (Session Delta)
        store.selectSession(at: 3)
        assertTest(store.selectedSessionId == id4, "Cmd+4 selects Session Delta (index 3)")
        
        // Out of bounds selection (index 8, 9, -1) -> should be safely ignored
        store.selectSession(at: 8)
        assertTest(store.selectedSessionId == id4, "Out-of-bounds Cmd+9 safely ignored (retains active session)")
        store.selectSession(at: -1)
        assertTest(store.selectedSessionId == id4, "Negative index safely ignored")

        // -------------------------------------------------------------
        // Test Group 4: Session Renaming & Restarting
        // -------------------------------------------------------------
        print("\n[Test Group 4: Session Renaming & Restarting]")
        
        store.renameSession(id: id1, newName: "Renamed Shell")
        let renamedSession = store.sessions.first(where: { $0.id == id1 })
        assertTest(renamedSession?.name == "Renamed Shell", "Session renamed successfully to 'Renamed Shell'")
        
        // Empty rename check
        store.renameSession(id: id1, newName: "   ")
        assertTest(renamedSession?.name == "Renamed Shell", "Empty/whitespace rename is safely rejected")
        
        // Session Restart
        await store.restartSession(id: id1)
        let restartedSession = store.sessions.first(where: { $0.id == id1 })
        assertTest(restartedSession != nil, "Session preserved after restart")
        assertTest(restartedSession?.name == "Renamed Shell", "Restart preserves session name")
        assertTest(restartedSession?.preset.id == AgentPreset.standardShell.id, "Restart preserves agent preset")

        // -------------------------------------------------------------
        // Test Group 5: Session Closure & Working State Guard (Cmd+W)
        // -------------------------------------------------------------
        print("\n[Test Group 5: Session Closure & Working State Guard (Cmd+W)]")
        
        // Select Session Beta
        store.selectSession(at: 1)
        let beta = store.activeSession!
        
        // Scenario A: Idle session closes immediately without confirmation
        beta.state = .idle
        store.requestCloseActiveSession()
        assertTest(!store.showingCloseConfirmation, "Idle session closes without confirmation alert")
        
        // Wait for async closure
        var closedBeta = false
        for _ in 0..<30 {
            if !store.sessions.contains(where: { $0.id == id2 }) {
                closedBeta = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        assertTest(closedBeta, "Session Beta removed from store")
        assertTest(store.sessions.count == 3, "Remaining session count is 3")
        
        // Scenario B: Active (.working) session triggers confirmation dialog
        store.selectSession(at: 0)
        let activeWorking = store.activeSession!
        activeWorking.state = .working
        
        store.requestCloseActiveSession()
        assertTest(store.showingCloseConfirmation, "Active .working session triggers confirmation dialog on Cmd+W")
        assertTest(store.sessionPendingClose?.id == activeWorking.id, "sessionPendingClose points to active working session")
        
        // User clicks Cancel
        store.cancelCloseSession()
        assertTest(!store.showingCloseConfirmation, "Cancel resets confirmation dialog")
        assertTest(store.sessionPendingClose == nil, "sessionPendingClose cleared on cancel")
        assertTest(store.sessions.contains(where: { $0.id == activeWorking.id }), "Session retained on cancel")
        
        // User triggers Cmd+W again and clicks Confirm
        store.requestCloseActiveSession()
        assertTest(store.showingCloseConfirmation, "Confirmation re-triggers on subsequent Cmd+W")
        store.confirmCloseSession()
        assertTest(!store.showingCloseConfirmation, "Confirmation dismissed on confirm")
        
        var confirmedClosed = false
        for _ in 0..<30 {
            if !store.sessions.contains(where: { $0.id == activeWorking.id }) {
                confirmedClosed = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        assertTest(confirmedClosed, "Session successfully closed after confirmation")

        // -------------------------------------------------------------
        // Test Group 6: Blocked State Indicators & Reasons
        // -------------------------------------------------------------
        print("\n[Test Group 6: Blocked State Indicators & Reasons]")
        
        let remaining = store.sessions.first!
        remaining.state = .blocked(reason: "Waiting for approval (y/n)")
        
        if case .blocked(let reason) = remaining.state {
            assertTest(reason == "Waiting for approval (y/n)", "Blocked reason accurately records confirmation prompt")
        } else {
            assertTest(false, "Expected blocked state")
        }
        
        // Transition back to idle
        remaining.state = .idle
        assertTest(remaining.state == .idle, "State transitions back to idle when unblocked")

        // Clean up remaining sessions
        for s in store.sessions {
            await store.closeSession(id: s.id)
        }
        assertTest(store.sessions.isEmpty, "All test sessions cleanly torn down")

        print("\n=================================================================")
        print(" SUMMARY: \(passedCount)/\(totalCount) tests passed successfully!")
        print("=================================================================\n")
    }
}
