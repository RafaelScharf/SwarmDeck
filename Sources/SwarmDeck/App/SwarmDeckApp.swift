import SwiftUI

@main
struct SwarmDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session...") {
                    SessionStore.shared.showingNewSessionSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("New Tab") {
                    SessionStore.shared.showingNewSessionSheet = true
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Divider()
                
                Button("Close Session") {
                    SessionStore.shared.requestCloseActiveSession()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            
            CommandMenu("Navigate") {
                ForEach(1...9, id: \.self) { num in
                    Button("Session \(num)") {
                        SessionStore.shared.selectSession(at: num - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(num)")), modifiers: .command)
                    .disabled(SessionStore.shared.sessions.count < num)
                }
            }
            
            CommandMenu("Terminal") {
                Button("Clear Scrollback") {
                    SessionStore.shared.clearScrollbackOnActiveSession()
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                Button("Bigger") {
                    SessionStore.shared.increaseFontSizeOnActiveSession()
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Smaller") {
                    SessionStore.shared.decreaseFontSizeOnActiveSession()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Reset Font Size") {
                    SessionStore.shared.resetFontSizeOnActiveSession()
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Divider()
                
                Menu("Theme") {
                    Button("Default (System)") {
                        SessionStore.shared.setThemeOnActiveSession(named: nil)
                    }
                    
                    Divider()
                    
                    ForEach(TerminalThemePreset.allCases) { preset in
                        if let name = preset.themeName {
                            Button(preset.rawValue) {
                                SessionStore.shared.setThemeOnActiveSession(named: name)
                            }
                        }
                    }
                }
            }
        }
    }
}
