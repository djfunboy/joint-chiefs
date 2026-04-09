import ArgumentParser
import Foundation
import JointChiefsCore

@main
struct JointChiefsCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jointchiefs",
        abstract: "Multi-model AI code review orchestrator",
        subcommands: [Review.self, Models.self],
        defaultSubcommand: Review.self
    )
}
