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
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
    }

    /// URL to the installed `DXVK` folder
    private static let dxvkFolder: URL = GPTKInstaller.libraryFolder.appending(path: "DXVK")
    /// Path to the `wine64` binary
    static let wineBinary: URL = GPTKInstaller.binFolder.appending(path: "wine64")
    /// Parth to the `wineserver` binary
    private static let wineserverBinary: URL = GPTKInstaller.binFolder.appending(path: "wineserver")

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated
        return try process.runStream(name: name ?? args.joined(separator: " "))
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineBinary
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineserverBinary
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        return try runWineProcess(
            name: name, args: args,
            environment: bottle.constructWineEnvironment(environment: environment)
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        return try runWineserverProcess(
            name: name, args: args,
            environment: bottle.constructWineServerEnvironment(environment: environment)
        )
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    static func run(
        _ args: [String], bottle: Bottle? = nil, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let log = try Log(bottle: bottle, args: args, environment: environment)
        var environment = environment

        if let bottle = bottle {
            environment = bottle.constructWineEnvironment(environment: environment)
        }

        for await output in try runWineProcess(args: args, environment: environment) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                log.write(line: message)
                result.append(message)
            }
        }

        return result.joined()
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []
        let log = try Log(bottle: bottle, args: args, environment: [:])

        for await output in try runWineserverProcess(
            args: args, environment: ["WINEPREFIX": bottle.url.path]
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
        at url: URL, args: [String] = [], environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        return try runWineProcess(
            name: url.lastPathComponent,
            args: ["start", "/unix", url.path(percentEncoded: false)] + args,
            environment: environment
        )
    }

    /// Execute a `wine start /unix {url}` command returning the output result
    static func runProgram(at url: URL, bottle: Bottle, environment: [String: String] = [:]) async throws {
        for await _ in try runProgram(at: url, environment: environment) { }
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

    static func buildVersion(bottle: Bottle) async throws -> String? {
        return try await queryRegistyKey(
            bottle: bottle, key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild", type: .string
        )
    }

    static func retinaMode(bottle: Bottle) async throws -> Bool {
        let values: Set<String> = ["y", "n"]
        guard let output = try await queryRegistyKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        ), values.contains(output) else {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
            return false
        }
        return output == "y"
    }

    static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await addRegistyKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", data: retinaMode ? "y" : "n",
            type: .string
        )
    }

    static func dpiResolution(bottle: Bottle) async throws -> Int? {
        guard let output = try await queryRegistyKey(bottle: bottle, key: RegistryKey.desktop.rawValue,
            name: "LogPixels", type: .dword
        ) else { return nil }

        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        guard let int = int else { return nil }
        return int
    }

    static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await addRegistyKey(
            bottle: bottle, key: RegistryKey.desktop.rawValue, name: "LogPixels", data: String(dpi),
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
                                type: RegistryType) async throws -> String? {
        let output = try await run(["reg", "query", key, "-v", name], bottle: bottle)
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        guard let line = lines.first(where: { $0.contains(type.rawValue) }) else { return nil }
        let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let value = array.last else { return nil }
        return String(value)
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
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
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
