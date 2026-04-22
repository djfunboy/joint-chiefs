import AppKit
import Foundation
import SwiftUI

struct InstallView: View {

    @Environment(SetupModel.self) private var model
    @State private var installResult: InstallResult?
    @State private var isInstalling = false

    var body: some View {
        SetupPage(
            title: "Install CLI + MCP",
            subtitle: "Copies `jointchiefs`, `jointchiefs-mcp`, and `jointchiefs-keygetter` to the chosen directory so your terminal and AI client can find them."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.lg) {
                destinationPanel

                if let installResult {
                    resultPanel(for: installResult)
                }
            }
        } footer: {
            if isInstalling {
                ProgressView().controlSize(.small)
            }
            Button("Install") {
                runInstall()
            }
            .buttonStyle(.agentPrimary)
            .disabled(isInstalling)

            Button("Next: MCP Config") {
                model.currentSection = .mcp
            }
            .buttonStyle(.agentSecondary)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Destination panel

    private var destinationPanel: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.sm) {
            AgentSectionHeader(text: "Destination")

            HStack(alignment: .center, spacing: AgentSpacing.sm) {
                Text(model.installDestination.path)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { pickDirectory() }
                    .buttonStyle(.agentSecondary(size: .small))
            }

            if let pathStatus = pathStatusMessage {
                AgentPill(
                    text: pathStatus.message,
                    kind: pathStatus.kind,
                    icon: pathStatus.systemImage
                )
            }
        }
        .agentPanel(tint: destinationTint)
    }

    private var destinationTint: Color {
        if case .success(let installedPath) = installResult,
           installedPath == model.installDestination.path {
            return Color.agentBgReady
        }
        return Color.agentBgPanel
    }

    // MARK: - Install result panel

    @ViewBuilder
    private func resultPanel(for result: InstallResult) -> some View {
        let tint: Color = {
            switch result {
            case .success: Color.agentBgReady
            case .failure: Color.agentBgPanel
            }
        }()

        VStack(alignment: .leading, spacing: AgentSpacing.xs) {
            HStack(spacing: AgentSpacing.sm) {
                AgentPill(
                    text: result.title,
                    kind: result.pillKind,
                    icon: result.systemImage
                )
                Spacer()
            }
            if !result.detail.isEmpty {
                Text(result.detail)
                    .font(.agentXS)
                    .foregroundStyle(Color.agentTextBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .agentPanel(tint: tint)
    }

    // MARK: - Pick

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.installDestination
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.installDestination = url
        }
    }

    // MARK: - Install

    private func runInstall() {
        isInstalling = true
        Task {
            defer { Task { @MainActor in isInstalling = false } }
            let sourceDir = Self.buildProductsDir() ?? URL(fileURLWithPath: ".")
            let binaries = ["jointchiefs", "jointchiefs-mcp", "jointchiefs-keygetter"]
            let destination = model.installDestination

            do {
                try FileManager.default.createDirectory(
                    at: destination,
                    withIntermediateDirectories: true
                )
                for name in binaries {
                    let src = sourceDir.appendingPathComponent(name)
                    let dst = destination.appendingPathComponent(name)
                    guard FileManager.default.fileExists(atPath: src.path) else {
                        await MainActor.run {
                            installResult = .failure(
                                "Missing binary",
                                detail: "Could not find \(name) next to the setup app at \(sourceDir.path)."
                            )
                        }
                        return
                    }
                    if FileManager.default.fileExists(atPath: dst.path) {
                        try FileManager.default.removeItem(at: dst)
                    }
                    try FileManager.default.copyItem(at: src, to: dst)
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: dst.path
                    )
                }
                await MainActor.run {
                    installResult = .success(destination.path)
                }
            } catch {
                await MainActor.run {
                    installResult = .failure("Install failed", detail: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - PATH detection

    private var pathStatusMessage: (message: String, systemImage: String, kind: AgentPill.Kind)? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = path.split(separator: ":").map(String.init)
        if dirs.contains(model.installDestination.path) {
            return (
                "On $PATH — jointchiefs will work from any terminal.",
                "checkmark.circle.fill",
                .success
            )
        }
        return (
            "Not on $PATH. Append export PATH=\"\(model.installDestination.path):$PATH\" to your shell profile.",
            "exclamationmark.triangle.fill",
            .warning
        )
    }

    // MARK: - Source binaries

    /// Finds the directory containing the three CLI binaries to copy. Two shapes:
    ///
    /// - `.build/release/` (development via `swift run`): the setup exe sits next
    ///   to its siblings. Return the exe's directory.
    /// - `Joint Chiefs.app/Contents/MacOS/jointchiefs-setup` (bundled): the setup
    ///   exe is in `Contents/MacOS/`, but the CLI binaries live in
    ///   `Contents/Resources/`. Return the Resources directory.
    ///
    /// We pick between them by checking which one actually contains `jointchiefs`.
    private static func buildProductsDir() -> URL? {
        let exe = CommandLine.arguments.first ?? ""
        let resolved = URL(fileURLWithPath: exe).resolvingSymlinksInPath()
        let exeDir = resolved.deletingLastPathComponent()
        let cliSibling = exeDir.appendingPathComponent("jointchiefs")
        if FileManager.default.isExecutableFile(atPath: cliSibling.path) {
            return exeDir
        }
        let resourcesDir = exeDir
            .deletingLastPathComponent()  // drop MacOS/
            .appendingPathComponent("Resources", isDirectory: true)
        let cliInResources = resourcesDir.appendingPathComponent("jointchiefs")
        if FileManager.default.isExecutableFile(atPath: cliInResources.path) {
            return resourcesDir
        }
        return exeDir
    }
}

private enum InstallResult {
    case success(String)
    case failure(String, detail: String)

    var title: String {
        switch self {
        case .success(let path): "Installed to \(path)"
        case .failure(let title, _): title
        }
    }

    var detail: String {
        switch self {
        case .success: ""
        case .failure(_, let detail): detail
        }
    }

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        }
    }

    var pillKind: AgentPill.Kind {
        switch self {
        case .success: .success
        case .failure: .error
        }
    }
}
