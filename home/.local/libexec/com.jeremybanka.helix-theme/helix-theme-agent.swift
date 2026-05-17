import AppKit
import Darwin
import Foundation

private let label = "com.jeremybanka.helix-theme"
private let stderrLogName = "\(label).err.log"
private let stdoutLogName = "\(label).out.log"

enum HelixThemeAgentError: Error, CustomStringConvertible {
  case missingHome
  case invalidArguments
  case missingHelixConfig(path: String)
  case refusingToReplaceNonSymlink(path: String)
  case missingExecutable(path: String)

  var description: String {
    switch self {
    case .missingHome:
      return "HOME is not set"
    case .invalidArguments:
      return """
        Usage:
          helix-theme-agent sync
          helix-theme-agent watch
          helix-theme-agent install-launch-agent
        """
    case .missingHelixConfig(let path):
      return "Missing Helix config: \(path)"
    case .refusingToReplaceNonSymlink(let path):
      return "Refusing to replace non-symlink Helix config: \(path)"
    case .missingExecutable(let path):
      return "Missing executable at: \(path)"
    }
  }
}

struct HelixThemeAgent {
  static func main() throws {
    let command = try parseCommand()
    let home = try homeDirectory()
    let agent = ThemeAgent(homeDirectory: home)

    switch command {
    case .sync:
      let mode = try agent.syncHelixTheme()
      print("Helix is using \(mode.rawValue) mode.")
    case .watch:
      let initialMode = try agent.syncHelixTheme()
      print("Watching macOS appearance for Helix theme changes.")
      let watcher = AppearanceWatcher(agent: agent, initialMode: initialMode)
      watcher.run()
    case .installLaunchAgent:
      let plistPath = try agent.installLaunchAgent()
      print(plistPath)
    }
  }

  private static func parseCommand() throws -> Command {
    guard CommandLine.arguments.count == 2,
      let command = Command(rawValue: CommandLine.arguments[1])
    else {
      throw HelixThemeAgentError.invalidArguments
    }

    return command
  }

  private static func homeDirectory() throws -> URL {
    guard let home = ProcessInfo.processInfo.environment["HOME"] else {
      throw HelixThemeAgentError.missingHome
    }

    return URL(fileURLWithPath: home, isDirectory: true)
  }
}

do {
  try HelixThemeAgent.main()
} catch let error as HelixThemeAgentError {
  fputs("\(error.description)\n", stderr)
  exit(1)
} catch {
  fputs("\(error.localizedDescription)\n", stderr)
  exit(1)
}

private enum Command: String {
  case sync = "sync"
  case watch = "watch"
  case installLaunchAgent = "install-launch-agent"
}

private enum AppearanceMode: String {
  case light
  case dark

  var configFileName: String {
    switch self {
    case .light:
      return "config.light.toml"
    case .dark:
      return "config.dark.toml"
    }
  }
}

private final class ThemeAgent {
  private let fileManager = FileManager.default
  private let homeDirectory: URL
  private let helixConfigDirectory: URL
  private let activeConfigPath: URL

  init(homeDirectory: URL) {
    self.homeDirectory = homeDirectory
    self.helixConfigDirectory =
      homeDirectory
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("helix", isDirectory: true)
    self.activeConfigPath = helixConfigDirectory.appendingPathComponent("config.toml")
  }

  func syncHelixTheme() throws -> AppearanceMode {
    let mode = currentAppearanceMode()
    let sourceName = mode.configFileName
    let sourcePath = helixConfigDirectory.appendingPathComponent(sourceName)

    guard fileManager.fileExists(atPath: sourcePath.path) else {
      throw HelixThemeAgentError.missingHelixConfig(path: sourcePath.path)
    }

    if fileManager.fileExists(atPath: activeConfigPath.path) {
      let attributes = try fileManager.attributesOfItem(atPath: activeConfigPath.path)
      let fileType = attributes[.type] as? FileAttributeType

      guard fileType == .typeSymbolicLink else {
        throw HelixThemeAgentError.refusingToReplaceNonSymlink(path: activeConfigPath.path)
      }

      let currentTarget = try fileManager.destinationOfSymbolicLink(atPath: activeConfigPath.path)
      if currentTarget == sourceName {
        return mode
      }

      try fileManager.removeItem(at: activeConfigPath)
    }

    try fileManager.createSymbolicLink(
      atPath: activeConfigPath.path, withDestinationPath: sourceName)
    print("Helix now uses \(mode.rawValue) mode via \(sourceName).")
    return mode
  }

  func reloadHelix() {
    let pids = getHelixPids()

    guard !pids.isEmpty else {
      print("No running hx sessions found.")
      return
    }

    for pid in pids {
      kill(pid, SIGUSR1)
    }

    let suffix = pids.count == 1 ? "" : "s"
    print("Reloaded \(pids.count) hx session\(suffix).")
  }

  func installLaunchAgent() throws -> String {
    let launchAgentsDirectory =
      homeDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LaunchAgents", isDirectory: true)
    let logsDirectory =
      homeDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Logs", isDirectory: true)
    let plistPath = launchAgentsDirectory.appendingPathComponent("\(label).plist")
    let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()

    guard fileManager.fileExists(atPath: executablePath.path) else {
      throw HelixThemeAgentError.missingExecutable(path: executablePath.path)
    }

    try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

    if fileManager.fileExists(atPath: plistPath.path) {
      let attributes = try fileManager.attributesOfItem(atPath: plistPath.path)
      if (attributes[.type] as? FileAttributeType) == .typeSymbolicLink {
        try fileManager.removeItem(at: plistPath)
      }
    }

    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      	<key>Label</key>
      	<string>\(label)</string>
      	<key>ProgramArguments</key>
      	<array>
      		<string>\(executablePath.path)</string>
      		<string>watch</string>
      	</array>
      	<key>RunAtLoad</key>
      	<true/>
      	<key>KeepAlive</key>
      	<true/>
      	<key>StandardErrorPath</key>
      	<string>\(logsDirectory.appendingPathComponent(stderrLogName).path)</string>
      	<key>StandardOutPath</key>
      	<string>\(logsDirectory.appendingPathComponent(stdoutLogName).path)</string>
      </dict>
      </plist>
      """

    try plist.write(to: plistPath, atomically: true, encoding: .utf8)
    return plistPath.path
  }

  func currentAppearanceMode() -> AppearanceMode {
    do {
      let output = try runCommand(
        "/usr/bin/defaults",
        arguments: ["read", "-g", "AppleInterfaceStyle"],
        ignoreNonZeroExit: false
      )
      return output.trimmingCharacters(in: .whitespacesAndNewlines) == "Dark" ? .dark : .light
    } catch {
      return .light
    }
  }

  private func getHelixPids() -> [pid_t] {
    var pidSet = Set<pid_t>()

    for processName in ["hx", "helix-term"] {
      guard
        let output = try? runCommand(
          "/usr/bin/pgrep",
          arguments: ["-x", processName],
          ignoreNonZeroExit: true
        )
      else {
        continue
      }

      for line in output.split(separator: "\n") {
        if let pid = pid_t(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
          pidSet.insert(pid)
        }
      }
    }

    return pidSet.sorted()
  }

  private func runCommand(
    _ executablePath: String,
    arguments: [String],
    ignoreNonZeroExit: Bool
  ) throws -> String {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(decoding: stdoutData, as: UTF8.self)
    let stderr = String(decoding: stderrData, as: UTF8.self)

    if process.terminationStatus != 0 && !ignoreNonZeroExit {
      throw NSError(
        domain: "HelixThemeAgent",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr]
      )
    }

    return stdout
  }
}

private final class AppearanceWatcher {
  private let agent: ThemeAgent
  private var lastMode: AppearanceMode
  private var observers: [NSObjectProtocol] = []

  init(agent: ThemeAgent, initialMode: AppearanceMode) {
    self.agent = agent
    self.lastMode = initialMode
  }

  func run() {
    observers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.handlePotentialThemeChange()
      }
    )

    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.handlePotentialThemeChange()
      }
    )

    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.screensDidWakeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.handlePotentialThemeChange()
      }
    )

    RunLoop.main.run()
  }

  private func handlePotentialThemeChange() {
    let nextMode = agent.currentAppearanceMode()
    guard nextMode != lastMode else {
      return
    }

    do {
      lastMode = try agent.syncHelixTheme()
      agent.reloadHelix()
    } catch {
      fputs("\(error.localizedDescription)\n", stderr)
    }
  }
}
