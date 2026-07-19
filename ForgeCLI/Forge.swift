import ArgumentParser
import ForgeCore
import Foundation

@main
struct Forge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forge",
        abstract: "Batch audiobook pipeline: scan a library, plan work, forge m4bs.",
        version: "0.1.0",
        subcommands: [Scan.self]
    )

    public static func main() async {
        // A bare tool has no app bundle to resolve the bundled ffmpeg
        // from — let the environment point at one (e.g. the repo's
        // Resources/bin, or the installed app's bundle).
        if let dir = ProcessInfo.processInfo.environment["FORGE_FFMPEG_DIR"] {
            Bundled.setOverrideDirectory(URL(fileURLWithPath: dir))
        }
        await Self.executeAsCommand()
    }
}

private extension AsyncParsableCommand {
    /// The default @main entry point, callable after our env setup.
    static func executeAsCommand() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}

/// Shared options for every subcommand.
struct GlobalOptions: ParsableArguments {
    @Option(name: [.short, .customLong("config")],
            help: "Path to forge.yml (default: ~/.forge/forge.yml)")
    var configPath: String = "~/.forge/forge.yml"

    func loadConfig() throws -> ForgeConfig {
        try ForgeConfig.load(from: configPath)
    }
}
