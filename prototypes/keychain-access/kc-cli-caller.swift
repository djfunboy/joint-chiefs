import Foundation

// Simulates the CLI at ~/.local/bin/jointchiefs invoking the keygetter inside the .app bundle.

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: kc-cli-caller <keygetter-path> <account>\n".utf8))
    exit(64)
}

let keygetterPath = CommandLine.arguments[1]
let account = CommandLine.arguments[2]

let process = Process()
process.executableURL = URL(fileURLWithPath: keygetterPath)
process.arguments = ["read", account]

let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardOutput = stdoutPipe
process.standardError = stderrPipe
process.standardInput = Pipe()  // simulate headless parent — no terminal stdin

do {
    try process.run()
    process.waitUntilExit()

    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    if process.terminationStatus == 0, let key = String(data: stdout, encoding: .utf8), !key.isEmpty {
        let prefix = String(key.prefix(8))
        print("[cli-caller] success — keygetter returned key prefix: \(prefix)…")
        exit(0)
    } else {
        if let s = String(data: stderr, encoding: .utf8) {
            FileHandle.standardError.write(Data("[cli-caller] keygetter stderr: \(s)".utf8))
        }
        FileHandle.standardError.write(Data("[cli-caller] keygetter exited with code \(process.terminationStatus)\n".utf8))
        exit(10)
    }
} catch {
    FileHandle.standardError.write(Data("[cli-caller] failed to spawn: \(error)\n".utf8))
    exit(11)
}
