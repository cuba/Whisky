//
//  Program.swift
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
import AppKit
import WhiskyKit
import os.log

extension Program {
    func run() {
        if NSEvent.modifierFlags.contains(.shift) {
            Task.detached(priority: .userInitiated) {
                print("Running in terminal...")
                await self.runInTerminal()
            }
        } else {
            self.runInWine()
        }
    }

    func runInWine() {
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = bottle.constructWineEnvironment(environment: generateEnvironment())

        Task.detached {
            do {
                let log = try Log(bottle: self.bottle, args: arguments, environment: environment)

                if self.bottle.settings.dxvk {
                    try Wine.enableDXVK(bottle: self.bottle)
                }

                var messages: [String] = []
                for await output in try Wine.runProgram(at: self.url, args: arguments, environment: environment) {
                    switch output {
                    case .started:
                        log.write(line: "Started process for '\(self.url.lastPathComponent)'")
                    case .message(let string):
                        messages.append(string)
                        log.write(line: string)
                    case .error(let string):
                        messages.append(string)
                        log.write(line: string)
                    case .terminated(let process):
                        if process.terminationStatus != 0 {
                            let message = messages.joined(separator: "\n")
                            await MainActor.run {
                                self.showRunError(message: message)
                            }
                        }

                        log.write(
                            line: "Terminated process for '\(self.url.lastPathComponent)' (\(process.terminationStatus)"
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.showRunError(message: error.localizedDescription)
                }
            }
        }
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }

    func generateTerminalCommand() -> String {
        var wineCmd = "\(Wine.wineBinary.esc) start /unix \(url.esc) \(settings.arguments)"
        let env = bottle.constructWineEnvironment(environment: generateEnvironment())
        for environment in env {
            wineCmd = "\(environment.key)=\(environment.value) " + wineCmd
        }

        return wineCmd
    }

    private func runInTerminal() async {
        let wineCmd = generateTerminalCommand().replacingOccurrences(of: "\\", with: "\\\\")

        let script = """
        tell application "Terminal"
            activate
            do script "\(wineCmd)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                Logger.wineKit.error("Failed to run terminal script \(error)")
                guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                await MainActor.run {
                    showRunError(message: String(describing: description))
                }
            }
        }
    }
}
