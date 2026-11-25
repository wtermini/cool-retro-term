/*
 * Copyright (c) 2026 cool-retro-term contributors
 * https://github.com/Swordfish90/cool-retro-term
 *
 * This file is part of cool-retro-term.
 *
 * cool-retro-term is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import AppKit
import Foundation

/// Command-line options, the same as the Qt app's (app/main.cpp).
struct LaunchOptions {
    var profile: String?
    var workdir: String?
    var command: [String]?
    var fullscreen = false

    static var current = LaunchOptions()

    static let usage = """
        Usage: CoolRetroTerm [--default-settings] [--workdir <dir>] [--program <prog>] \
        [-p|--profile <prof>] [--fullscreen] [-h|--help]
          --default-settings  Run cool-retro-term with the default settings
          --workdir <dir>     Change working directory to 'dir'
          --program <prog>    Run 'prog' instead of the shell
          -e <cmd>            Command to execute. This option will catch all following arguments, so use it as the last option.
          --fullscreen        Run cool-retro-term in fullscreen.
          -p|--profile <prof> Run cool-retro-term with the given profile.
          -h|--help           Print this help.
          -v|--version        Print the version.
          --mcp               Run the office desk MCP server on stdin/stdout (for agents), not the terminal.
        """

    /// Parses the arguments; prints and exits for --help and --version.
    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        var index = 1
        func value() -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        while index < arguments.count {
            switch arguments[index] {
            case "-h", "--help":
                print(usage)
                exit(0)
            case "-v", "--version":
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
                print("cool-retro-term \(version)")
                exit(0)
            case "--default-settings":
                ProfileStore.useDefaultSettings = true
            case "--workdir":
                options.workdir = value()
            case "-p", "--profile":
                options.profile = value()
            case "--program":
                if let program = value() { options.command = [program] }
            case "-e":
                let rest = Array(arguments[(index + 1)...])
                options.command = rest.isEmpty ? nil : rest
                index = arguments.count
            case "--fullscreen":
                options.fullscreen = true
            default:
                break   // Including arguments macOS itself passes.
            }
            index += 1
        }
        return options
    }
}

// The office desk's MCP server, started by an agent: no windows.
if CommandLine.arguments.dropFirst().first == "--mcp" {
    OfficeDeskMCPServer.run()
}

LaunchOptions.current = LaunchOptions.parse(CommandLine.arguments)

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
