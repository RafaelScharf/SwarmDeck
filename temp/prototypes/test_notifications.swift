import Foundation
import AppKit

@main
struct NotificationTests {
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
        print(" SwarmDeck: System Notifications & Deep-Link Test Suite")
        print("=================================================================\n")

        // -------------------------------------------------------------
        // Test Group 1: Permission Authorization
        // -------------------------------------------------------------
        print("[Test Group 1: Permission Authorization]")
        let mockBackend = MockNotificationDeliveryBackend()
        let notificationService = NotificationService(backend: mockBackend, debounceInterval: 0.3)

        let authResult = await notificationService.requestAuthorization()
        assertTest(authResult == true, "NotificationService reports authorization granted from backend")

        await mockBackend.setAuthorizationGranted(false)
        let authDenied = await notificationService.requestAuthorization()
        assertTest(authDenied == false, "NotificationService reports authorization denied when backend denies")
        await mockBackend.setAuthorizationGranted(true)

        // -------------------------------------------------------------
        // Test Group 2: Active Session & App Foreground Suppression
        // -------------------------------------------------------------
        print("\n[Test Group 2: Active Session Foreground Suppression]")
        let session1 = UUID()
        await notificationService.resetAll()
        await mockBackend.clear()

        // Session is active and app is active -> no notification should fire
        let fired1 = await notificationService.handleStateChange(
            sessionId: session1,
            sessionName: "Active Claude",
            newState: .blocked(reason: "Permission prompt (y/n)"),
            isSessionActive: true,
            isAppActive: true
        )
        assertTest(fired1 == false, "Active session in active app does not trigger notification (user is focused)")
        let records1 = await mockBackend.records
        assertTest(records1.isEmpty, "No notification record was delivered to backend")

        // -------------------------------------------------------------
        // Test Group 3: Background Session Transitions (.blocked)
        // -------------------------------------------------------------
        print("\n[Test Group 3: Background Session .blocked Trigger]")
        await notificationService.resetAll()
        await mockBackend.clear()

        // Session is in background (isSessionActive = false, isAppActive = true)
        let firedBlocked = await notificationService.handleStateChange(
            sessionId: session1,
            sessionName: "Background Aider",
            newState: .blocked(reason: "Waiting for human confirmation"),
            isSessionActive: false,
            isAppActive: true
        )
        assertTest(firedBlocked == true, "Background session transitioning to .blocked triggers notification")
        let recordsBlocked = await mockBackend.records
        assertTest(recordsBlocked.count == 1, "Exactly one notification record delivered")
        assertTest(recordsBlocked.first?.title == "Agent Blocked: Background Aider", "Notification title matches expected template")
        assertTest(recordsBlocked.first?.body.contains("Waiting for human confirmation") == true, "Notification body contains blocked reason")
        assertTest(recordsBlocked.first?.userInfo["sessionId"] == session1.uuidString, "Notification userInfo contains session UUID deep link payload")

        // -------------------------------------------------------------
        // Test Group 4: Long-Running Task Completion (.working -> .idle)
        // -------------------------------------------------------------
        print("\n[Test Group 4: Task Completion .working -> .idle Trigger]")
        let session2 = UUID()
        await notificationService.resetAll()
        await mockBackend.clear()

        // Initial idle state -> should not notify
        let firedInitialIdle = await notificationService.handleStateChange(
            sessionId: session2,
            sessionName: "Antigravity Task",
            newState: .idle,
            isSessionActive: false,
            isAppActive: false
        )
        assertTest(firedInitialIdle == false, "Initial idle transition does not notify")

        // Transition to .working -> should not notify yet
        let firedWorking = await notificationService.handleStateChange(
            sessionId: session2,
            sessionName: "Antigravity Task",
            newState: .working,
            isSessionActive: false,
            isAppActive: false
        )
        assertTest(firedWorking == false, "Transition to .working does not notify")

        // Transition from .working to .idle -> should notify completion!
        let firedCompleted = await notificationService.handleStateChange(
            sessionId: session2,
            sessionName: "Antigravity Task",
            newState: .idle,
            isSessionActive: false,
            isAppActive: false
        )
        assertTest(firedCompleted == true, "Transition from .working to .idle triggers task completed notification")
        let recordsCompleted = await mockBackend.records
        assertTest(recordsCompleted.count == 1, "Exactly one completion notification delivered")
        assertTest(recordsCompleted.first?.title == "Task Completed: Antigravity Task", "Notification title is 'Task Completed: <name>'")
        assertTest(recordsCompleted.first?.userInfo["sessionId"] == session2.uuidString, "Notification userInfo contains target session UUID")

        // -------------------------------------------------------------
        // Test Group 5: Process Exit Failure Trigger
        // -------------------------------------------------------------
        print("\n[Test Group 5: Process Exit Failure Trigger]")
        let session3 = UUID()
        await notificationService.resetAll()
        await mockBackend.clear()

        // Clean exit (0) -> no failure notification
        let firedCleanExit = await notificationService.handleStateChange(
            sessionId: session3,
            sessionName: "Shell Job",
            newState: .exited(code: 0),
            isSessionActive: false,
            isAppActive: false
        )
        assertTest(firedCleanExit == false, "Clean exit (code 0) does not trigger error notification")

        // Non-zero exit code (e.g. 137 or 1) -> failure notification
        let firedCrashExit = await notificationService.handleStateChange(
            sessionId: session3,
            sessionName: "Crashing Agent",
            newState: .exited(code: 137),
            isSessionActive: false,
            isAppActive: false
        )
        assertTest(firedCrashExit == true, "Non-zero process exit triggers failure notification")
        let recordsExit = await mockBackend.records
        assertTest(recordsExit.count == 1, "Exactly one failure notification delivered")
        assertTest(recordsExit.first?.title == "Process Failed: Crashing Agent", "Notification title is 'Process Failed: <name>'")
        assertTest(recordsExit.first?.body.contains("137") == true, "Notification body contains exit code")

        // -------------------------------------------------------------
        // Test Group 6: Rate Limiting & Debounce
        // -------------------------------------------------------------
        print("\n[Test Group 6: Rate Limiting & Debounce]")
        let session4 = UUID()
        await notificationService.resetAll()
        await mockBackend.clear()

        // First blocked transition -> should fire
        let firstBurst = await notificationService.handleStateChange(
            sessionId: session4,
            sessionName: "Spammy Agent",
            newState: .blocked(reason: "Prompt 1"),
            isSessionActive: false,
            isAppActive: false
        )
        assertTest(firstBurst == true, "First prompt in burst triggers notification")

        // Immediate second blocked transition within debounceInterval -> should be suppressed
        let secondBurst = await notificationService.handleStateChange(
            sessionId: session4,
            sessionName: "Spammy Agent",
            newState: .blocked(reason: "Prompt 2"),
            isSessionActive: false,
            isAppActive: false
        )
        assertTest(secondBurst == false, "Rapid consecutive prompt within debounce window is suppressed by rate limiter")

        let recordsBurst = await mockBackend.records
        assertTest(recordsBurst.count == 1, "Only single notification dispatched during burst")

        // Wait for debounceInterval (0.3s) to elapse
        try await Task.sleep(for: .milliseconds(350))

        let thirdBurst = await notificationService.handleStateChange(
            sessionId: session4,
            sessionName: "Spammy Agent",
            newState: .blocked(reason: "Prompt 3"),
            isSessionActive: false,
            isAppActive: false
        )
        assertTest(thirdBurst == true, "Prompt after debounce interval elapses triggers notification")
        let recordsPostWait = await mockBackend.records
        assertTest(recordsPostWait.count == 2, "Second notification dispatched after debounce interval expired")

        // -------------------------------------------------------------
        // Test Group 7: Deep-Link & Session Navigation via NotificationCenter
        // -------------------------------------------------------------
        print("\n[Test Group 7: Deep-Link & Navigation]")
        let targetSessionId = UUID()
        var navigatedSessionId: UUID? = nil

        let observer = NotificationCenter.default.addObserver(
            forName: .selectSessionNotification,
            object: nil,
            queue: .main
        ) { notification in
            navigatedSessionId = notification.userInfo?["sessionId"] as? UUID
        }

        NotificationCenter.default.post(
            name: .selectSessionNotification,
            object: nil,
            userInfo: ["sessionId": targetSessionId]
        )

        // Allow async notifications to deliver
        try await Task.sleep(for: .milliseconds(50))

        assertTest(navigatedSessionId == targetSessionId, "Deep link NotificationCenter post navigates to target session ID")
        NotificationCenter.default.removeObserver(observer)

        // -------------------------------------------------------------
        // Test Group 8: System Backend CLI Safety
        // -------------------------------------------------------------
        print("\n[Test Group 8: System Backend Bundle Safety]")
        let systemBackend = SystemNotificationDeliveryBackend()
        let systemAuth = try await systemBackend.requestAuthorization()
        assertTest(systemAuth == false, "SystemNotificationDeliveryBackend safely returns false outside app bundle without throwing exception")

        print("\n=================================================================")
        print(" SUMMARY: \(passedCount)/\(totalCount) tests passed successfully!")
        print("=================================================================\n")
    }
}
