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
            // If the client supplied a progressToken in `_meta`, wire a sink
            // that pushes `notifications/progress` back to it at each debate
            // stage boundary. Clients that don't pass a token get a no-op —
            // their spinner still shows, but no structured progress updates.
            // See https://modelcontextprotocol.io/specification/...utilities/progress
            let progressToken = request._meta?.progressToken
            let progressSink: JointChiefsReviewTool.ProgressSink = { current, total, message in
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
