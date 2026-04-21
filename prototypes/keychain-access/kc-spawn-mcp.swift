import Foundation

// Simulates Claude Desktop spawning the MCP server as a child process with piped stdio.
// If Keychain prompts silently fail in this context, this is where we'll see it.

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: kc-spawn-mcp <path-to-kc-reader-binary>\n".utf8))
    exit(1)
}

let readerPath = CommandLine.arguments[1]

let process = Process()
process.executableURL = URL(fileURLWithPath: readerPath)
process.arguments = ["mcp-headless"]

let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardOutput = stdoutPipe
process.standardError = stderrPipe
process.standardInput = Pipe()

do {
    try process.run()
    process.waitUntilExit()

    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    if let s = String(data: stdout, encoding: .utf8), !s.isEmpty {
        print("[spawner] child stdout: \(s)", terminator: "")
    }
    if let s = String(data: stderr, encoding: .utf8), !s.isEmpty {
        FileHandle.standardError.write(Data("[spawner] child stderr: \(s)".utf8))
    }

    print("[spawner] child exited with code \(process.terminationStatus)")
    exit(process.terminationStatus == 0 ? 0 : 10)
} catch {
    FileHandle.standardError.write(Data("[spawner] failed to spawn: \(error)\n".utf8))
    exit(11)
}
