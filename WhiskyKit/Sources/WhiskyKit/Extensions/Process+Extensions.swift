//
//  Process+Extensions.swift
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
import os.log

public enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

public extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        standardOutput = pipe
        standardError = errorPipe

        let stream = AsyncStream<ProcessOutput> { continuation in
            continuation.onTermination = { termination in
                switch termination {
                case .finished:
                    break
                case .cancelled:
                    guard self.isRunning else { return }
                    self.terminate()
                @unknown default:
                    break
                }
            }

            continuation.yield(.started(self))

            pipe.fileHandleForReading.readabilityHandler = { pipe in
                let line = String(decoding: pipe.availableData, as: UTF8.self)
                guard !line.isEmpty else { return }
                continuation.yield(.message(line))
                Logger.wineKit.info("\(line, privacy: .public)")

                do {
                    try fileHandle?.write(line: line)
                } catch {
                    Logger.wineKit.info("Failed to write line: \(error)")
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { pipe in
                let line = String(decoding: pipe.availableData, as: UTF8.self)
                guard !line.isEmpty else { return }
                continuation.yield(.error(line))
                Logger.wineKit.warning("\(line, privacy: .public)")

                do {
                    try fileHandle?.write(line: line)
                } catch {
                    Logger.wineKit.info("Failed to write line: \(error)")
                }
            }

            terminationHandler = { (process: Process) in
                do {
                    _ = try pipe.fileHandleForReading.readToEnd()
                    _ = try errorPipe.fileHandleForReading.readToEnd()
                    try fileHandle?.close()
                } catch {
                    Logger.wineKit.error("Error while clearing data: \(error)")
                }

                if process.terminationStatus == 0 {
                    Logger.wineKit.info(
                        "Terminated \(name) with status code '\(process.terminationStatus, privacy: .public)'"
                    )
                } else {
                    Logger.wineKit.warning(
                        "Terminated \(name) with status code '\(process.terminationStatus, privacy: .public)'"
                    )
                }

                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }

        var logParts: [String] = []
        if let arguments = arguments {
            logParts.append("\targuments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            logParts.append("\texecutable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            logParts.append("\tdirectory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            logParts.append("\tenvironment: \(environment)")
        }

        let logDetails = logParts.joined(separator: "\n")
        Logger.wineKit.info("Running process \(name)\n\(logDetails)")
        try fileHandle?.writeInfo(for: self)
        try run()
        return stream
    }
}
