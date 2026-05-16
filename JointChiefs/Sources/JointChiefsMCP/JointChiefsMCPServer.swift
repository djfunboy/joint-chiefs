import Foundation
import JointChiefsCore
import MCP

// The Joint Chiefs MCP server exposes a single tool, `joint_chiefs_review`, over stdio.
// Spawned by any MCP client via JSON-RPC over stdin/stdout. Trust is inherited from the
// parent process — the MCP client owns our stdio by definition. See docs/SECURITY.md.
//
// Stdio-only invariant: network transports (HTTP, SSE, WebSocket) are architecturally
// prohibited. Every security assumption in this server depends on stdio-only.

@main
struct JointChiefsMCPServer {
    static func main() async throws {
        let server = Server(
            name: "joint-chiefs",
            version: "0.5.0",
            capabilities: .init(
                tools: .init(listChanged: false)
            )
        )

        // Register the single review tool.
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [JointChiefsReviewTool.definition])
        }

        await server.withMethodHandler(CallTool.self) { [server] request in
            guard request.name == JointChiefsReviewTool.name else {
                return CallTool.Result(
                    content: [.text(text: "Unknown tool: \(request.name)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            // Three side channels for round/phase visibility on long debate runs.
            // Realistic latency for a 4-model panel including a local model is
            // several minutes — without progress signal a host's tool-call UI
            // looks indistinguishable from a hang. See tasks/lessons.md 2026-04-30.
            //   1. notifications/progress — fires only if the client opted in via
            //      `_meta.progressToken`. Many hosts don't.
            //   2. stderr — stdio MCP convention is stdout=JSON-RPC, stderr=log.
            //      Hosts that surface a log/debug pane show round-by-round progress.
            //   3. ~/Library/Caches/Joint Chiefs/current-review.json — a single
            //      JSON object overwritten on every milestone, cheap `cat` target
            //      for users whose host shows nothing.
            let progressToken = request._meta?.progressToken
            let broadcaster = ProgressBroadcaster()
            let progressSink: JointChiefsReviewTool.ProgressSink = { current, total, message in
                await broadcaster.report(current: current, total: total, message: message)
                guard let token = progressToken else { return }
                let notification = Message<ProgressNotification>(
                    method: ProgressNotification.name,
                    params: ProgressNotification.Parameters(
                        progressToken: token,
                        progress: current,
                        total: total,
                        message: message
                    )
                )
                // Failing to send progress shouldn't fail the whole review —
                // clients may disconnect mid-call, or transport may hiccup.
                try? await server.notify(notification)
            }
            return await JointChiefsReviewTool.invoke(
                arguments: request.arguments ?? [:],
                progress: progressSink
            )
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

// MARK: - ProgressBroadcaster

/// Writes review-progress milestones to stderr and a JSON status file in
/// addition to whatever the MCP client gets via `notifications/progress`.
/// See the comment in the `CallTool` handler above for the rationale.
actor ProgressBroadcaster {
    static let defaultStatusFileURL: URL = {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches
            .appendingPathComponent("Joint Chiefs", isDirectory: true)
            .appendingPathComponent("current-review.json")
    }()

    private let stderr: FileHandle
    private let statusFileURL: URL
    private let startedAt: Date
    private let isoFormatter: ISO8601DateFormatter
    private let encoder: JSONEncoder

    init(
        stderr: FileHandle = .standardError,
        statusFileURL: URL = ProgressBroadcaster.defaultStatusFileURL
    ) {
        self.stderr = stderr
        self.statusFileURL = statusFileURL
        self.startedAt = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
        try? FileManager.default.createDirectory(
            at: statusFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func report(current: Double, total: Double, message: String) {
        let now = Date()
        let timestamp = isoFormatter.string(from: now)
        let elapsed = Int(now.timeIntervalSince(startedAt))

        let line = "[\(timestamp)] \(message) (\(elapsed)s elapsed)\n"
        if let data = line.data(using: .utf8) {
            try? stderr.write(contentsOf: data)
        }

        let payload = StatusPayload(
            updatedAt: timestamp,
            startedAt: isoFormatter.string(from: startedAt),
            elapsedSeconds: elapsed,
            current: current,
            total: total,
            message: message
        )
        if let data = try? encoder.encode(payload) {
            try? data.write(to: statusFileURL, options: .atomic)
        }
    }

    private struct StatusPayload: Codable {
        let updatedAt: String
        let startedAt: String
        let elapsedSeconds: Int
        let current: Double
        let total: Double
        let message: String
    }
}
