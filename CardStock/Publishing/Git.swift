import Foundation

/// Runs the Mac's built-in git in a site folder.
struct Git: Sendable {
    let root: URL
    /// GitHub token for fetch and push. Passed through the environment for
    /// each run and never written to disk.
    var token: String?

    struct Result: Sendable {
        var status: Int32
        var output: String
        var error: String
        var succeeded: Bool { status == 0 }
    }

    struct Failure: LocalizedError {
        var command: String
        var message: String

        /// A network problem behind the failure, for commands that talk to GitHub.
        var problem: NetworkProblem? {
            Git.networkCommands.contains(command) ? Git.networkProblem(in: message) : nil
        }

        /// git's own words, for the activity log.
        var rawDescription: String { "git \(command) failed: \(message)" }

        var errorDescription: String? {
            switch problem {
            case .gitHubTrouble:
                command == "push"
                    ? "GitHub had a problem on its side and didn't take your changes. Nothing is wrong with your site, and nothing was lost: your changes are saved on this Mac. Try again in a few minutes."
                    : "GitHub had a problem on its side and couldn't send the latest version. Nothing is wrong with your site, and nothing on this Mac was changed. Try again in a few minutes."
            case .offline:
                "Couldn't reach GitHub. Check that this Mac is connected to the internet, then try again. Nothing was lost."
            case nil:
                rawDescription
            }
        }
    }

    /// Trouble getting to GitHub that has nothing to do with the site.
    enum NetworkProblem: Sendable, Equatable {
        /// GitHub answered with a server error (5xx): an outage or a hiccup.
        case gitHubTrouble
        /// GitHub couldn't be reached at all.
        case offline
    }

    static let networkCommands: Set<String> = ["push", "fetch", "pull", "ls-remote", "clone"]

    /// What git's error text says went wrong on the network, if anything.
    static func networkProblem(in message: String) -> NetworkProblem? {
        let text = message.lowercased()
        let server = ["internal server error", "service unavailable", "bad gateway", "gateway time",
                      "returned error: 50", "http 50", "remote: unexpected error", "temporarily unavailable"]
        if server.contains(where: text.contains) { return .gitHubTrouble }
        let offline = ["could not resolve host", "failed to connect to", "network is unreachable",
                       "couldn't connect to server", "operation timed out", "connection timed out",
                       "no route to host", "internet connection appears to be offline"]
        if offline.contains(where: text.contains) { return .offline }
        return nil
    }

    static let executable = URL(filePath: "/usr/bin/git")

    /// Whether git is usable. On a Mac without Apple's Command Line Tools,
    /// /usr/bin/git is a stub that asks to install them.
    static func isAvailable() async -> Bool {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/xcode-select")
            p.arguments = ["-p"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }.value
    }

    /// Opens Apple's "install Command Line Tools" prompt.
    static func installCommandLineTools() {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        try? p.run()
    }

    var isRepository: Bool {
        FileManager.default.fileExists(atPath: root.appending(path: ".git").path)
    }

    /// Runs git and throws if it fails.
    @discardableResult
    func run(_ args: String...) async throws -> String {
        try await run(args)
    }

    @discardableResult
    func run(_ args: [String]) async throws -> String {
        let result = await attempt(args)
        guard result.succeeded else {
            let message = result.error.isEmpty ? result.output : result.error
            throw Failure(command: args.first ?? "", message: redact(message.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return result.output
    }

    /// Runs git and returns the result, even when it fails.
    func attempt(_ args: [String]) async -> Result {
        let root = root
        let env = environment()
        return await Task.detached { Self.runBlocking(args, root: root, env: env) }.value
    }

    private static func runBlocking(_ args: [String], root: URL, env: [String: String]) -> Result {
        let p = Process()
        p.executableURL = Git.executable
        p.arguments = args
        p.currentDirectoryURL = root
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }
        // Drain stderr on another thread so a full pipe can't stall git.
        let errData = LockedData()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData.set(err.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        group.wait()
        return Result(status: p.terminationStatus,
                      output: String(decoding: outData, as: UTF8.self),
                      error: String(decoding: errData.get(), as: UTF8.self))
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_EDITOR"] = "true"
        env["LC_ALL"] = "C"
        if let token {
            let basic = Data("x-access-token:\(token)".utf8).base64EncodedString()
            env["GIT_CONFIG_COUNT"] = "2"
            env["GIT_CONFIG_KEY_0"] = "http.https://github.com/.extraheader"
            env["GIT_CONFIG_VALUE_0"] = "AUTHORIZATION: basic \(basic)"
            // Don't let a saved credential helper override or store anything.
            env["GIT_CONFIG_KEY_1"] = "credential.helper"
            env["GIT_CONFIG_VALUE_1"] = ""
        }
        return env
    }

    private func redact(_ s: String) -> String {
        guard let token, !token.isEmpty else { return s }
        return s.replacingOccurrences(of: token, with: "••••")
    }
}

private final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func set(_ d: Data) { lock.withLock { data = d } }
    func get() -> Data { lock.withLock { data } }
}
