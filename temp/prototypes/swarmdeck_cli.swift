import Foundation

@main
struct SwarmDeckCLI {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            printUsage()
            exit(1)
        }
        
        if args.contains("--help") || args.contains("-h") || args.contains("help") {
            printUsage()
            exit(0)
        }
        
        let client = IPCClient()
        guard client.isServerRunning() else {
            print("Error: SwarmDeck is not currently running. Please launch SwarmDeck first.")
            exit(2)
        }
        
        let command = args[1]
        do {
            switch command {
            case "ping":
                let resp = try await client.sendRequest(IPCRequest(method: "ping"))
                print("SwarmDeck Server: \(resp.result ?? "OK")")
                
            case "list":
                let resp = try await client.sendRequest(IPCRequest(method: "list"))
                if let result = resp.result {
                    print("Active SwarmDeck Sessions:")
                    print(result)
                } else if let err = resp.error {
                    print("Error (\(err.code)): \(err.message)")
                    exit(1)
                }
                
            case "run", "spawn":
                var preset = "shell"
                var cwd = FileManager.default.currentDirectoryPath
                var customName: String? = nil
                var focus = true
                
                var idx = 2
                while idx < args.count {
                    let arg = args[idx]
                    if arg == "--preset" && idx + 1 < args.count {
                        preset = args[idx + 1]
                        idx += 2
                    } else if arg == "--cwd" && idx + 1 < args.count {
                        cwd = args[idx + 1]
                        idx += 2
                    } else if arg == "--name" && idx + 1 < args.count {
                        customName = args[idx + 1]
                        idx += 2
                    } else if arg == "--no-focus" {
                        focus = false
                        idx += 1
                    } else {
                        idx += 1
                    }
                }
                
                var params: [String: String] = [
                    "preset": preset,
                    "cwd": cwd,
                    "focus": focus ? "true" : "false"
                ]
                if let name = customName {
                    params["name"] = name
                }
                
                let resp = try await client.sendRequest(IPCRequest(method: "spawn", params: params))
                if let result = resp.result {
                    print("Spawned agent session: \(result)")
                } else if let err = resp.error {
                    print("Failed to spawn session: \(err.message)")
                    exit(1)
                }
                
            case "terminate":
                guard args.count > 2 else {
                    print("Usage: swarmdeck terminate <sessionId>")
                    exit(1)
                }
                let targetId = args[2]
                let resp = try await client.sendRequest(IPCRequest(method: "terminate", params: ["id": targetId]))
                if let result = resp.result {
                    print("Terminated session \(targetId): \(result)")
                } else if let err = resp.error {
                    print("Failed to terminate session: \(err.message)")
                    exit(1)
                }
                
            default:
                print("Unknown command: '\(command)'")
                printUsage()
                exit(1)
            }
        } catch {
            print("IPC Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    static func printUsage() {
        print("""
        Usage: swarmdeck <command> [options]

        Commands:
          ping                               Check if SwarmDeck is running
          run [--preset <name>] [--cwd <dir>] Spawn a new agent session (e.g. claude, aider, agy, shell)
          list                               List all active sessions
          terminate <sessionId>              Terminate an agent session
        """)
    }
}
