//
//  Logger.swift
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
import OSLog
import WhiskyKit

class Log {
    static let logsFolder = FileManager.default.urls(for: .libraryDirectory,
                                                    in: .userDomainMask)[0]
        .appending(path: "Logs")
        .appending(path: Bundle.whiskyBundleIdentifier)

    let fileHandle: FileHandle

    init(bottle: Bottle?, args: [String], environment: [String: String]?) throws {
        if !FileManager.default.fileExists(atPath: Log.logsFolder.path) {
            try FileManager.default.createDirectory(at: Log.logsFolder, withIntermediateDirectories: true)
        }

        let dateString = Date.now.ISO8601Format()
        let fileURL = Log.logsFolder
            .appending(path: dateString)
            .appendingPathExtension("log")

        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        fileHandle = try FileHandle(forWritingTo: fileURL)
        write(line: Log.constructHeader(bottle, args, environment))
    }

    // swiftlint:disable line_length
    static func constructHeader(_ bottle: Bottle?, _ args: [String], _ environment: [String: String]?) -> String {
        var header = String()
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersion

        header += "Whisky Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")\n"
        header += "Date: \(ISO8601DateFormatter().string(from: Date.now))\n"
        header += "macOS Version: \(macOSVersion.majorVersion).\(macOSVersion.minorVersion).\(macOSVersion.patchVersion)\n\n"
        if let bottle = bottle {
            header += "Bottle Name: \(bottle.settings.name)\n"
            header += "Bottle URL: \(bottle.url.path)\n\n"

            header += "Wine Version: \(bottle.settings.wineVersion)\n"
            header += "Windows Version: \(bottle.settings.windowsVersion)\n"
            header += "Enhanced Sync: \(bottle.settings.enhancedSync)\n\n"

            header += "Metal HUD: \(bottle.settings.metalHud)\n"
            header += "Metal Trace: \(bottle.settings.metalTrace)\n\n"

            if bottle.settings.dxvk {
                header += "DXVK: \(bottle.settings.dxvk)\n"
                header += "DXVK Async: \(bottle.settings.dxvkAsync)\n"
                header += "DXVK HUD: \(bottle.settings.dxvkHud)\n\n"
            }
        }

        header += "Arguments: "
        for arg in args {
            header += "\(arg) "
        }
        header += "\n\n"

        if let environment = environment {
            if environment.count > 0 {
                header += "Environment:\n"
                header += "\(environment as AnyObject)\n\n"
            }
        }

        return header
    }
    // swiftlint:enable line_length

    func write(line: String) {
        if let data = line.data(using: .utf8) {
            do {
                try fileHandle.write(contentsOf: data)
            } catch {
                print("Failed to write line to log: \"\(line)\"!")
            }
        }
    }

    deinit {
        do {
            try fileHandle.close()
        } catch {
            print("Failed to close log file handle!")
        }
    }
}
