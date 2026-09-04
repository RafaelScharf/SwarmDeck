---
type: prototype-resolution
ticket: issue-6
status: resolved
date: 2026-09-04
url: https://github.com/RafaelScharf/SwarmDeck/issues/6
branch: feat/issue-6-notifications
---

# Resolution: Prototype - System Notifications via UNUserNotificationCenter

## Question
How do we reliably notify the user via macOS native notifications when a background agent transitions to `.blocked` or completes a task, and allow focusing the session upon clicking the notification?

## Findings & Implementation

1. **Notification Service & Delivery Backend:**
   - Created `NotificationService` actor wrapping a pluggable `NotificationDeliveryBackend`.
   - Implemented `SystemNotificationDeliveryBackend` using macOS `UNUserNotificationCenter` with safeguards against unbundled executions (`Bundle.main.bundleIdentifier != nil` check prevents uncaught `NSException` in CLI/test runs).
   - Implemented `MockNotificationDeliveryBackend` actor for deterministic, fast in-memory validation in headless and test environments.

2. **State Transition Triggers:**
   - Monitored session state transitions from `OutputStateDetector` and `ProcessLifecycleSupervisor`.
   - Foreground suppression: active sessions in active foreground windows do not trigger redundant notifications.
   - Background triggers:
     - `.blocked(reason)` -> Triggers `"Agent Blocked: <SessionName>"` with prompt/reason details.
     - `.working` -> `.idle` -> Triggers `"Task Completed: <SessionName>"`.
     - `.exited(code)` with code != 0 -> Triggers `"Process Failed: <SessionName>"` with exit code.

3. **Debounce & Rate-Limiting:**
   - Configured adaptive debounce rate-limiting per session (default 3.0s in production, configurable for tests) to prevent notification storms when an interactive agent rapidly prints prompts or status spinners.

4. **Deep-Link Navigation & AppDelegate Delegate:**
   - Included target session UUID in `UNNotificationContent.userInfo["sessionId"]`.
   - Configured `AppDelegate` as `UNUserNotificationCenterDelegate`:
     - In `userNotificationCenter(_:didReceive:withCompletionHandler:)`, parses `sessionId`, posts `.selectSessionNotification`, and activates SwarmDeck to bring its window to the front.
     - In `userNotificationCenter(_:willPresent:withCompletionHandler:)`, enables `.banner`, `.sound`, and `.badge` presentation even when the app is active.
   - Added observer in `ContentView` to automatically update `sessionManager.selectedSessionId`.

## Test Validation
- Created automated 27-point validation test suite in `temp/prototypes/test_notifications.swift`.
- All 27 tests passed with 100% success rate.
