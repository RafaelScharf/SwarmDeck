import Foundation
import Darwin

@main
struct IPCTests {
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
        print(" SwarmDeck: Unix Domain Socket IPC & CLI Dispatcher Test Suite")
        print("=================================================================\n")

        let testSocketPath = "/tmp/swarmdeck_test_\(UUID().uuidString).sock"
        let client = IPCClient(socketPath: testSocketPath)

        // -------------------------------------------------------------
        // Test Group 1: Graceful Fallback When Server Is Not Running
        // -------------------------------------------------------------
        print("[Test Group 1: Fallback When Server Is Inactive]")
        let isRunningInitial = client.isServerRunning()
        assertTest(!isRunningInitial, "IPCClient detects server is not running when socket is absent")

        do {
            _ = try await client.sendRequest(IPCRequest(method: "ping"), timeout: 0.5)
            assertTest(false, "Should throw error when connecting to inactive server")
        } catch {
            assertTest(true, "Client throws informative error on connection refusal: \(error.localizedDescription)")
        }

        // -------------------------------------------------------------
        // Test Group 2: IPC Server Startup & Lifecycle
        // -------------------------------------------------------------
        print("\n[Test Group 2: IPC Server Lifecycle]")
        let server = IPCServer(socketPath: testSocketPath)
        
        let mockStore = MockSessionStore()

        await server.setHandler { request in
            switch request.method {
            case "ping":
                return .success(id: request.id, result: "pong")
                
            case "spawn":
                let preset = request.params?["preset"] ?? "shell"
                let name = request.params?["name"] ?? "\(preset.capitalized) 1"
                let cwd = request.params?["cwd"] ?? "/tmp"
                let newId = await mockStore.spawn(preset: preset, name: name, cwd: cwd)
                return .success(id: request.id, result: "{\"sessionId\":\"\(newId)\"}")
                
            case "list":
                let result = await mockStore.list()
                return .success(id: request.id, result: result)
                
            case "terminate":
                guard let targetId = request.params?["id"] else {
                    return .failure(id: request.id, code: -32602, message: "Missing id parameter")
                }
                _ = await mockStore.terminate(id: targetId)
                return .success(id: request.id, result: "{\"terminated\":true}")
                
            default:
                return .failure(id: request.id, code: -32601, message: "Method not found: \(request.method)")
            }
        }

        try await server.start()
        assertTest(FileManager.default.fileExists(atPath: testSocketPath), "Server creates Unix Domain Socket file at \(testSocketPath)")
        assertTest(client.isServerRunning(), "IPCClient detects server is active and accepting connections")

        // -------------------------------------------------------------
        // Test Group 3: Bi-Directional JSON-RPC Methods
        // -------------------------------------------------------------
        print("\n[Test Group 3: JSON-RPC Method Dispatching]")
        
        // 1. Ping
        let pingResp = try await client.sendRequest(IPCRequest(id: "req-1", method: "ping"))
        assertTest(pingResp.id == "req-1", "Response preserves request id")
        assertTest(pingResp.result == "pong", "Ping returned pong")
        assertTest(pingResp.error == nil, "Ping returned no error")

        // 2. Spawn Claude Agent
        let spawnParams = ["preset": "claude", "name": "Code Reviewer", "cwd": "/Users/test/repo"]
        let spawnResp = try await client.sendRequest(IPCRequest(id: "req-2", method: "spawn", params: spawnParams))
        assertTest(spawnResp.id == "req-2", "Spawn preserves request id")
        assertTest(spawnResp.result?.contains("sessionId") == true, "Spawn response returned valid session ID JSON")
        
        // Extract spawned session ID
        let sessionIdData = spawnResp.result!.data(using: .utf8)!
        let spawnObj = try JSONSerialization.jsonObject(with: sessionIdData) as! [String: Any]
        let createdSessionId = spawnObj["sessionId"] as! String
        assertTest(!createdSessionId.isEmpty, "Spawned session ID is non-empty")

        // 3. List Sessions
        let listResp = try await client.sendRequest(IPCRequest(id: "req-3", method: "list"))
        assertTest(listResp.result?.contains(createdSessionId) == true, "List response includes newly created session ID")
        assertTest(listResp.result?.contains("Code Reviewer") == true, "List response includes session name")

        // 4. Terminate Session
        let termResp = try await client.sendRequest(IPCRequest(id: "req-4", method: "terminate", params: ["id": createdSessionId]))
        assertTest(termResp.result?.contains("\"terminated\":true") == true, "Terminate response confirms session deletion")

        // Verify session is no longer in list
        let listRespAfter = try await client.sendRequest(IPCRequest(id: "req-5", method: "list"))
        assertTest(listRespAfter.result?.contains(createdSessionId) == false, "Terminated session removed from list")

        // 5. Error Handling: Unknown Method
        let unknownResp = try await client.sendRequest(IPCRequest(id: "req-6", method: "non_existent_method"))
        assertTest(unknownResp.error?.code == -32601, "Server returns JSON-RPC -32601 for unknown method")

        // -------------------------------------------------------------
        // Test Group 4: Concurrent Client Connections
        // -------------------------------------------------------------
        print("\n[Test Group 4: Concurrent Client Connections]")
        let concurrentClients = 8
        let results = await withTaskGroup(of: (Int, Bool).self) { group in
            for i in 0..<concurrentClients {
                group.addTask {
                    do {
                        let c = IPCClient(socketPath: testSocketPath)
                        let resp = try await c.sendRequest(
                            IPCRequest(id: "conc-\(i)", method: "spawn", params: ["preset": "shell", "name": "Agent \(i)"])
                        )
                        return (i, resp.result?.contains("sessionId") == true)
                    } catch {
                        print("Concurrent client \(i) failed: \(error)")
                        return (i, false)
                    }
                }
            }
            
            var collected: [(Int, Bool)] = []
            for await r in group {
                collected.append(r)
            }
            return collected
        }

        assertTest(results.count == concurrentClients, "All \(concurrentClients) concurrent client requests completed")
        let allSuccess = results.allSatisfy { $0.1 }
        assertTest(allSuccess, "All \(concurrentClients) concurrent clients successfully received session IDs without deadlock")

        // -------------------------------------------------------------
        // Test Group 5: Server Clean Teardown
        // -------------------------------------------------------------
        print("\n[Test Group 5: Server Teardown & Socket Cleanup]")
        await server.stop()
        assertTest(!FileManager.default.fileExists(atPath: testSocketPath), "Server cleanly unlinks socket file on stop()")
        assertTest(!client.isServerRunning(), "IPCClient detects server is no longer running after stop()")

        print("\n=================================================================")
        print(" SUMMARY: \(passedCount)/\(totalCount) tests passed successfully!")
        print("=================================================================\n")
    }
}

actor MockSessionStore {
    var sessions: [String: [String: String]] = [:]

    func spawn(preset: String, name: String, cwd: String) -> String {
        let newId = UUID().uuidString
        sessions[newId] = ["id": newId, "name": name, "preset": preset, "cwd": cwd, "state": "idle"]
        return newId
    }

    func list() -> String {
        let array = sessions.values.map { dict in
            "{\"id\":\"\(dict["id"]!)\",\"name\":\"\(dict["name"]!)\",\"state\":\"\(dict["state"]!)\"}"
        }.joined(separator: ",")
        return "[\(array)]"
    }

    func terminate(id: String) -> Bool {
        sessions.removeValue(forKey: id) != nil
    }
}
