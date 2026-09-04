import SwiftUI
import GhosttyTerminal
import UserNotifications

@main
struct SwarmDeckPrototypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            Task {
                await NotificationService.shared.requestAuthorization()
            }
        }
        
        // Asynchronously harvest login shell environment in background
        Task.detached(priority: .userInitiated) {
            await ShellEnvironmentHarvester.shared.harvest()
        }
        
        // Start local Unix Domain Socket IPC server
        Task {
            await IPCServer.shared.setHandler { request in
                await AppDelegate.handleIPCRequest(request)
            }
            
            do {
                try await IPCServer.shared.start()
            } catch {
                print("IPCServer startup notice: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    static func handleIPCRequest(_ request: IPCRequest) async -> IPCResponse {
        switch request.method {
        case "ping":
            return .success(id: request.id, result: "pong")
            
        case "spawn":
            let presetName = request.params?["preset"] ?? "shell"
            let cwd = request.params?["cwd"]
            let customName = request.params?["name"]
            
            let preset: AgentPreset
            switch presetName.lowercased() {
            case "claude", "claude-code": preset = .claudeCode
            case "aider": preset = .aider
            case "agy", "antigravity": preset = .antigravity
            default: preset = .standardShell
            }
            
            let newId = await SessionManager.shared.addSession(
                preset: preset,
                customName: customName,
                workingDirectory: cwd
            )
            
            if request.params?["focus"] == "true" {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            return .success(id: request.id, result: "{\"sessionId\":\"\(newId.uuidString)\"}")
            
        case "list":
            let list = SessionManager.shared.sessions.map { s in
                "{\"id\":\"\(s.id.uuidString)\",\"name\":\"\(s.name)\",\"state\":\"\(s.state)\"}"
            }.joined(separator: ",")
            return .success(id: request.id, result: "[\(list)]")
            
        case "terminate":
            guard let idStr = request.params?["id"], let targetId = UUID(uuidString: idStr) else {
                return .failure(id: request.id, code: -32602, message: "Missing or invalid 'id' parameter")
            }
            await SessionManager.shared.terminateSession(id: targetId)
            return .success(id: request.id, result: "{\"terminated\":true}")
            
        default:
            return .failure(id: request.id, code: -32601, message: "Method not found: \(request.method)")
        }
    }
    
    // Handle notification click / deep-link
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let sessionIdString = userInfo["sessionId"] as? String,
           let sessionId = UUID(uuidString: sessionIdString) {
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .selectSessionNotification,
                    object: nil,
                    userInfo: ["sessionId": sessionId]
                )
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        completionHandler()
    }
    
    // Present banner even when foregrounded
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

