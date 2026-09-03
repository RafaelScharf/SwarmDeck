import Foundation
@testable import SwarmDeckPrototype

let pty = try PTY()
pty.setOnData { data in
    print("Received: \(String(data: data, encoding: .utf8) ?? "")")
}
try pty.spawn(executable: "/bin/zsh", arguments: ["-c", "echo hello"])
sleep(1)
