import ArgumentParser

struct CLIOptions: ParsableArguments {
    @Flag(name: .long, help: "Run without menu bar UI")
    var headless = false

    @Option(name: .long, help: "Path to config file")
    var config: String?

    @Flag(name: .long, help: "Set MQTT password in Keychain")
    var setPassword = false

    @Flag(name: .long, help: "Print version")
    var version = false

    @Flag(name: .long, help: "Print current config (password redacted)")
    var showConfig = false
}
