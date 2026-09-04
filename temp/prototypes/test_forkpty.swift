import Darwin

var master: Int32 = 0
let pid = forkpty(&master, nil, nil, nil)
if pid == 0 {
    // child
    let args = ["/bin/zsh", "-l"]
    var cArgs = args.map { strdup($0) }
    cArgs.append(nil)
    
    var env = ["TERM=xterm-256color", "COLORTERM=truecolor"]
    var cEnv = env.map { strdup($0) }
    cEnv.append(nil)
    
    execve("/bin/zsh", &cArgs, &cEnv)
    exit(1)
} else if pid > 0 {
    print("Spawned child with pid \(pid), master fd \(master)")
}
