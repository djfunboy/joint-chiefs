import Foundation
import JointChiefsCore
import MCP

// The Joint Chiefs MCP server exposes a single tool, `joint_chiefs_review`, over stdio.
// Spawned by AI clients (Claude Code, Claude Desktop, Cursor, etc.) via JSON-RPC over
// stdin/stdout. Trust is inherited from the parent process — the MCP client owns our
// stdio by definition. See docs/SECURITY.md.
//
// Stdio-only invariant: network transports (HTTP, SSE, WebSocket) are architecturally
// prohibited. Every security assumption in this server depends on stdio-only.

@main
struct JointChiefsMCPServer {
    static func main() async throws {
        let server = Server(
            name: "joint-chiefs",
            version: "0.4.0",
            capabilities: .init(
                tools: .init(listChanged: false)
            )
        )

        // Register the single review tool.
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [JointChiefsReviewTool.definition])
        }

        await server.withMethodHandler(CallTool.self) { request in
            guard request.name == JointChiefsReviewTool.name else {
                return CallTool.Result(
                    content: [.text(text: "Unknown tool: \(request.name)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            return await JointChiefsReviewTool.invoke(arguments: request.arguments ?? [:])
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
