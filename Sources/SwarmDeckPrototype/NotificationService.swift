import Foundation
import UserNotifications
import AppKit

public extension Notification.Name {
    static let selectSessionNotification = Notification.Name("SwarmDeck.selectSession")
}

public protocol NotificationDeliveryBackend: Sendable {
    func requestAuthorization() async throws -> Bool
    func deliverNotification(
        id: String,
        title: String,
        subtitle: String?,
        body: String,
        userInfo: [String: String]
    ) async throws
}

public final class SystemNotificationDeliveryBackend: NotificationDeliveryBackend {
    public init() {}
    
    private var isCenterAvailable: Bool {
        // UNUserNotificationCenter throws an uncatchable NSException if bundleIdentifier is nil
        Bundle.main.bundleIdentifier != nil
    }
    
    public func requestAuthorization() async throws -> Bool {
        guard isCenterAvailable else {
            return false
        }
        return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    public func deliverNotification(
        id: String,
        title: String,
        subtitle: String?,
        body: String,
        userInfo: [String: String]
    ) async throws {
        guard isCenterAvailable else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        try await UNUserNotificationCenter.current().add(request)
    }
}

public struct DeliveredNotificationRecord: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let body: String
    public let userInfo: [String: String]
    public let timestamp: Date
}

public actor MockNotificationDeliveryBackend: NotificationDeliveryBackend {
    private var _records: [DeliveredNotificationRecord] = []
    public var authorizationGranted: Bool = true
    
    public init() {}
    
    public var records: [DeliveredNotificationRecord] {
        _records
    }
    
    public func clear() {
        _records.removeAll()
    }
    
    public func setAuthorizationGranted(_ granted: Bool) {
        self.authorizationGranted = granted
    }
    
    public func requestAuthorization() async throws -> Bool {
        return authorizationGranted
    }
    
    public func deliverNotification(
        id: String,
        title: String,
        subtitle: String?,
        body: String,
        userInfo: [String: String]
    ) async throws {
        _records.append(
            DeliveredNotificationRecord(
                id: id,
                title: title,
                subtitle: subtitle,
                body: body,
                userInfo: userInfo,
                timestamp: Date()
            )
        )
    }
}

public actor NotificationService {
    public static let shared = NotificationService()
    
    private let backend: NotificationDeliveryBackend
    private var lastNotificationTimes: [UUID: Date] = [:]
    private var previousStates: [UUID: AgentState] = [:]
    public var debounceInterval: TimeInterval
    
    public init(backend: NotificationDeliveryBackend = SystemNotificationDeliveryBackend(), debounceInterval: TimeInterval = 3.0) {
        self.backend = backend
        self.debounceInterval = debounceInterval
    }
    
    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            return try await backend.requestAuthorization()
        } catch {
            print("NotificationService: Failed to request authorization: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Evaluates agent state transitions and delivers notification if conditions are met.
    /// Returns true if a notification was sent, false otherwise.
    @discardableResult
    public func handleStateChange(
        sessionId: UUID,
        sessionName: String,
        newState: AgentState,
        isSessionActive: Bool,
        isAppActive: Bool
    ) async -> Bool {
        let prevState = previousStates[sessionId]
        previousStates[sessionId] = newState
        
        // 1. If the user is actively focused on this session in an active window, do not notify.
        if isSessionActive && isAppActive {
            return false
        }
        
        // 2. Determine if state transition qualifies for notification
        let notificationContent: (title: String, body: String)?
        switch newState {
        case .blocked(let reason):
            notificationContent = (
                title: "Agent Blocked: \(sessionName)",
                body: "Agent requires input: \(reason)"
            )
        case .idle:
            if prevState == .working {
                notificationContent = (
                    title: "Task Completed: \(sessionName)",
                    body: "Agent finished running and is now idle."
                )
            } else {
                notificationContent = nil
            }
        case .exited(let code):
            if code != 0 {
                notificationContent = (
                    title: "Process Failed: \(sessionName)",
                    body: "Process terminated unexpectedly with exit code \(code)."
                )
            } else {
                notificationContent = nil
            }
        case .working:
            notificationContent = nil
        }
        
        guard let content = notificationContent else {
            return false
        }
        
        // 3. Rate-limiting / Debounce per session
        let now = Date()
        if let lastTime = lastNotificationTimes[sessionId] {
            if now.timeIntervalSince(lastTime) < debounceInterval {
                // Suppressed by rate limit
                return false
            }
        }
        
        lastNotificationTimes[sessionId] = now
        
        let notificationId = UUID().uuidString
        let userInfo = ["sessionId": sessionId.uuidString]
        
        do {
            try await backend.deliverNotification(
                id: notificationId,
                title: content.title,
                subtitle: nil,
                body: content.body,
                userInfo: userInfo
            )
            return true
        } catch {
            print("NotificationService: Failed to deliver notification: \(error.localizedDescription)")
            return false
        }
    }
    
    public func resetHistory(for sessionId: UUID) {
        lastNotificationTimes.removeValue(forKey: sessionId)
        previousStates.removeValue(forKey: sessionId)
    }
    
    public func resetAll() {
        lastNotificationTimes.removeAll()
        previousStates.removeAll()
    }
}
