import Foundation
import UserNotifications

public extension Notification.Name {
    static let selectSessionNotification = Notification.Name("SwarmDeckSelectSessionNotification")
}

public protocol NotificationDeliveryBackend: Sendable {
    func requestAuthorization() async -> Bool
    func deliver(title: String, subtitle: String?, body: String, userInfo: [String: String]) async
}

public final class SystemNotificationDeliveryBackend: NotificationDeliveryBackend {
    public init() {}
    
    public func requestAuthorization() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
    
    public func deliver(title: String, subtitle: String?, body: String, userInfo: [String: String]) async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        try? await UNUserNotificationCenter.current().add(request)
    }
}

public actor NotificationService {
    public static let shared = NotificationService()
    
    private let backend: NotificationDeliveryBackend
    private var lastNotificationTimestamps: [UUID: Date] = [:]
    private var previousStates: [UUID: AgentState] = [:]
    private let rateLimitInterval: TimeInterval = 3.0
    
    public init(backend: NotificationDeliveryBackend = SystemNotificationDeliveryBackend()) {
        self.backend = backend
    }
    
    @discardableResult
    public func requestAuthorization() async -> Bool {
        await backend.requestAuthorization()
    }
    
    public func handleStateChange(
        sessionId: UUID,
        sessionName: String,
        newState: AgentState,
        isSessionActive: Bool,
        isAppActive: Bool
    ) async {
        let oldState = previousStates[sessionId]
        previousStates[sessionId] = newState
        
        guard let oldState = oldState else { return }
        guard !(isAppActive && isSessionActive) else { return }
        
        let now = Date()
        if let lastTime = lastNotificationTimestamps[sessionId],
           now.timeIntervalSince(lastTime) < rateLimitInterval {
            return
        }
        
        var shouldNotify = false
        var title = ""
        var body = ""
        
        switch newState {
        case .blocked(let reason):
            shouldNotify = true
            title = "\(sessionName) Needs Attention"
            body = "Action required: \(reason)"
            
        case .idle:
            if oldState == .working {
                shouldNotify = true
                title = "\(sessionName) Completed"
                body = "Agent has finished processing and is ready for commands."
            }
            
        case .exited(let code):
            if code != 0 {
                shouldNotify = true
                title = "\(sessionName) Exited with Error"
                body = "Process terminated unexpectedly with exit code \(code)."
            }
            
        case .working:
            shouldNotify = false
        }
        
        guard shouldNotify else { return }
        lastNotificationTimestamps[sessionId] = now
        
        await backend.deliver(
            title: title,
            subtitle: nil,
            body: body,
            userInfo: ["sessionId": sessionId.uuidString]
        )
    }
}
