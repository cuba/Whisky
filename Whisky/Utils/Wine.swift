//
//  Wine.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import WhiskyKit
import os.log

enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

class Wine {
    /// A global logger for WineKit
    static let wineLogger = Logger(
        subsystem: Bundle.whiskyBundleIdentifier, category: "wine"
    )

    static let binFolder: URL = GPTKInstaller.libraryFolder
        .appending(path: "Wine")
        .appending(path: "bin")

    static let dxvkFolder: URL = GPTKInstaller.libraryFolder
        .appending(path: "DXVK")

    static let wineBinary: URL = binFolder
        .appending(path: "wine64")

    static let wineserverBinary: URL = binFolder
        .appending(path: "wineserver")

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL,
        clearOutput: Bool
    ) throws -> AsyncStream<ProcessOutput> {
        Self.wineLogger.info(
            "Running process '\(args.joined(separator: " "))'"
        )

        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = binFolder
        process.environment = environment
        process.qualityOfService = .userInitiated
        return try process.runStream(name: name ?? args.joined(separator: " "), clearOutput: clearOutput)
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String], clearOutput: Bool
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineBinary,
            clearOutput: clearOutput
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String], clearOutput: Bool
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineserverBinary,
            clearOutput: clearOutput
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:], clearOutput: Bool
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args,
            environment: bottle.constructWineEnvironment(environment: environment),
            executableURL: wineBinary, clearOutput: clearOutput
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:], clearOutput: Bool
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args,
            environment: bottle.constructWineServerEnvironment(environment: environment),
            executableURL: wineserverBinary, clearOutput: clearOutput
        )
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    static func run(
        _ args: [String], bottle: Bottle? = nil, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [ProcessOutput] = []
        let log = try Log(bottle: bottle, args: args, environment: environment)

        if let bottle = bottle {
            if bottle.settings.dxvk {
                try enableDXVK(bottle: bottle)
            }

            let environment = bottle.constructWineEnvironment(environment: environment)
            for await output in try runWineProcess(args: args, environment: environment, clearOutput: false) {
                result.append(output)
            }
        } else {
            for await output in try runWineProcess(args: args, environment: environment, clearOutput: false) {
                result.append(output)
            }
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                log.write(line: message)
                return message
            }
        }.joined()
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []
        let log = try Log(bottle: bottle, args: args, environment: [:])

        for await output in try runWineserverProcess(
            args: args, environment: ["WINEPREFIX": bottle.url.path], clearOutput: true
        ) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                log.write(line: message)
                return message
            }
        }.joined()
    }

    /// Execute a `wine start /unix {url}` command returning an async stream
    static func runProgram(
        at url: URL, args: [String], environment: [String: String]
    ) throws -> AsyncStream<ProcessOutput> {
        return try runWineProcess(
            name: url.lastPathComponent,
            args: ["start", "/unix", url.path(percentEncoded: false)] + args,
            environment: environment, clearOutput: true
        )
    }

    @discardableResult
    /// Execute a `wine start /unix {url}` command returning the output result
    static func runProgram(url: URL, bottle: Bottle) async throws -> String {
        return try await Self.run(
            ["start", "/unix", url.path(percentEncoded: false)],
            bottle: bottle,
            environment: [:]
        )
    }

    static func wineVersion() async throws -> String {
        var output = try await run(["--version"])
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func winVersion(bottle: Bottle) async throws -> WinVersion {
        let output = try await run(["winecfg", "-v"], bottle: bottle)
        let lines = output.split(whereSeparator: \.isNewline)

        if let lastLine = lines.last {
            let winString = String(lastLine)

            if let version = WinVersion(rawValue: winString) {
                return version
            }
        }

        throw WineInterfaceError.invalidResponce
    }

    static func buildVersion(bottle: Bottle) async throws -> String {
        return try await queryRegistyKey(bottle: bottle,
                                  key: #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#,
                                  name: "CurrentBuild",
                                  type: .string)
    }

    static func retinaMode(bottle: Bottle) async throws -> Bool {
        let output = try await queryRegistyKey(bottle: bottle,
                                        key: #"HKCU\Software\Wine\Mac Driver"#,
                                        name: "RetinaMode",
                                        type: .string,
                                        defaultValue: "n")
        if output == "" {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
        }
        return output == "y"
    }

    static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await addRegistyKey(bottle: bottle,
                                key: #"HKCU\Software\Wine\Mac Driver"#,
                                name: "RetinaMode",
                                data: retinaMode ? "y" : "n",
                                type: .string)
    }

    static func dpiResolution(bottle: Bottle) async throws -> Int {
        let output = try await queryRegistyKey(
            bottle: bottle,
            key: #"HKCU\Control Panel\Desktop"#,
            name: "LogPixels",
            type: .dword
        )
        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        if let intData = int {
            return intData
        }
        throw "Failed to convert str LogPixels to int (default 216)"
    }

    static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await addRegistyKey(bottle: bottle,
            key: #"HKCU\Control Panel\Desktop"#,
            name: "LogPixels",
            data: String(dpi),
            type: .dword
        )
    }

    @discardableResult
    static func control(bottle: Bottle) async throws -> String {
        return try await run(["control"], bottle: bottle)
    }

    @discardableResult
    static func regedit(bottle: Bottle) async throws -> String {
        return try await run(["regedit"], bottle: bottle)
    }

    @discardableResult
    static func cfg(bottle: Bottle) async throws -> String {
        return try await run(["winecfg"], bottle: bottle)
    }

    @discardableResult
    static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        return try await run(["winecfg", "-v", win.rawValue], bottle: bottle)
    }

    static func addRegistyKey(bottle: Bottle, key: String, name: String,
                              data: String, type: RegistryType) async throws {
        try await run(["reg", "add", key, "-v", name,
                       "-t", type.rawValue, "-d", data, "-f"], bottle: bottle)
    }

    static func queryRegistyKey(bottle: Bottle, key: String, name: String,
                                type: RegistryType, defaultValue: String? = "") async throws -> String {
        do {
            let output = try await run(["reg", "query", key, "-v", name], bottle: bottle)
            let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            if let line = lines.first(where: { $0.contains(type.rawValue) }) {
                let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
                if let value = array.last {
                    return String(value)
                }
            }
        } catch {
            return defaultValue ?? ""
        }

        throw WineInterfaceError.invalidResponce
    }

    static func changeBuildVersion(bottle: Bottle, version: Int) async throws {
        try await addRegistyKey(bottle: bottle, key: #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#,
                                name: "CurrentBuild", data: "\(version)", type: .string)
        try await addRegistyKey(bottle: bottle, key: #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#,
                                name: "CurrentBuildNumber", data: "\(version)", type: .string)
    }

    @discardableResult
    static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await run(["cmd", "/c", url.path(percentEncoded: false)],
                             bottle: bottle)
    }

    static func killBottle(bottle: Bottle) throws {
        Task.detached(priority: .userInitiated) {
            try await runWineserver(["-k"], bottle: bottle)
        }
    }

    static func enableDXVK(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
    }
}

enum WineInterfaceError: Error {
    case invalidResponce
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

actor WineOutput {
    var output: String = ""

    func append(_ line: String) {
        output.append(line)
    }
}
