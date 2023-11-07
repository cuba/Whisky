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

extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, clearOutput: Bool) throws -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        standardOutput = pipe
        standardError = errorPipe

        let stream = AsyncStream<ProcessOutput> { continuation in
            continuation.yield(.started(self))

            pipe.fileHandleForReading.readabilityHandler = { pipe in
                let line = String(decoding: pipe.availableData, as: UTF8.self)
                guard !line.isEmpty else { return }
                continuation.yield(.message(line))
                Wine.wineLogger.info("\(line, privacy: .public)")
            }

            errorPipe.fileHandleForReading.readabilityHandler = { pipe in
                let line = String(decoding: pipe.availableData, as: UTF8.self)
                guard !line.isEmpty else { return }
                continuation.yield(.error(line))
                Wine.wineLogger.warning("\(line, privacy: .public)")
            }

            let completionHandler = { (process: Process) in
                do {
                    _ = try pipe.fileHandleForReading.readToEnd()
                    _ = try errorPipe.fileHandleForReading.readToEnd()
                } catch {
                    Wine.wineLogger.error("Error while clearing data: \(error)")
                }

                if process.terminationStatus == 0 {
                    Wine.wineLogger.info(
                        "Terminated \(name) with status code '\(process.terminationStatus, privacy: .public)'"
                    )
                } else {
                    Wine.wineLogger.warning(
                        "Terminated \(name) with status code '\(process.terminationStatus, privacy: .public)'"
                    )
                }

                continuation.yield(.terminated(process))
                continuation.finish()
            }

            if clearOutput {
                while true {
                    waitUntilExit()
                    //guard pipe.fileHandleForReading.availableData.count == 0 else { continue }
                    //guard errorPipe.fileHandleForReading.availableData.count == 0 else { continue }
                    break
                }

                completionHandler(self)
            } else {
                terminationHandler = completionHandler
            }
        }

        try run()
        return stream
    }
}
