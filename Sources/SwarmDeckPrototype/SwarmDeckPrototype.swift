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
        .commands {
            CommandMenu("Terminal") {
                Button("Clear Scrollback") {
                    SessionManager.shared.clearScrollbackOnActiveSession()
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                Button("Bigger") {
                    SessionManager.shared.increaseFontSizeOnActiveSession()
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Smaller") {
                    SessionManager.shared.decreaseFontSizeOnActiveSession()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Reset Font Size") {
                    SessionManager.shared.resetFontSizeOnActiveSession()
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Divider()
                
                Menu("Theme") {
                    Button("Default (System)") {
                        SessionManager.shared.setThemeOnActiveSession(named: nil)
                    }
                    
                    Divider()
                    
                    ForEach(TerminalThemePreset.allCases) { preset in
                        if let name = preset.themeName {
                            Button(preset.rawValue) {
                                SessionManager.shared.setThemeOnActiveSession(named: name)
                            }
                        }
                    }
                }
            }
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
            
        case "clear":
            if let idStr = request.params?["id"], let targetId = UUID(uuidString: idStr) {
                if let s = SessionManager.shared.sessions.first(where: { $0.id == targetId }) {
                    s.clearScrollback()
                }
            } else {
                SessionManager.shared.clearScrollbackOnActiveSession()
            }
            return .success(id: request.id, result: "{\"cleared\":true}")
            
        case "paste":
            let text = request.params?["text"] ?? ""
            if let idStr = request.params?["id"], let targetId = UUID(uuidString: idStr) {
                if let s = SessionManager.shared.sessions.first(where: { $0.id == targetId }) {
                    s.pasteText(text)
                }
            } else {
                SessionManager.shared.activeSession?.pasteText(text)
            }
            return .success(id: request.id, result: "{\"pasted\":true}")
            
        case "fontSize":
            let action = request.params?["action"] ?? "reset"
            switch action {
            case "increase": SessionManager.shared.increaseFontSizeOnActiveSession()
            case "decrease": SessionManager.shared.decreaseFontSizeOnActiveSession()
            case "set":
                if let sizeStr = request.params?["size"], let size = Double(sizeStr) {
                    SessionManager.shared.activeSession?.setFontSize(size)
                }
            default: SessionManager.shared.resetFontSizeOnActiveSession()
            }
            let current = SessionManager.shared.activeSession?.fontSize ?? Session.defaultFontSize
            return .success(id: request.id, result: "{\"fontSize\":\(current)}")
            
        case "theme":
            let themeName = request.params?["name"]
            SessionManager.shared.setThemeOnActiveSession(named: themeName)
            return .success(id: request.id, result: "{\"theme\":\"\(themeName ?? "default")\"}")
            
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

