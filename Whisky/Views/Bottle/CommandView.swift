//
//  CommandView.swift
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

import SwiftUI
import WhiskyKit

struct CommandView: View {
    enum CommandPrompt: String, CaseIterable {
        case wine, wineserver

        var defaultCommand: String {
            switch self {
            case .wine:
                return "--help"
            case .wineserver:
                return "--help"
            }
        }

        func run(args: [String], for bottle: Bottle) throws -> AsyncStream<ProcessOutput> {
            switch self {
            case .wine:
                return try Wine.runWineProcess(args: args, bottle: bottle)
            case .wineserver:
                return try Wine.runWineserverProcess(args: args, bottle: bottle)
            }
        }
    }

    struct Message {
        let uuid: UUID
        let lineNumber: UInt?
        let output: ProcessOutput
    }

    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @AppStorage("wineCommand") private var command = ""
    @AppStorage("wineCommandPrompt") private var prompt: CommandPrompt = .wine
    @State private var loading = false
    @State private var messages: [Message] = []
    @State private var runningTask: Task<(), Never>?
    @State private var scrolledID: String?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "dollarsign")
                Picker("wine.command.prompt", selection: $prompt) {
                    ForEach(CommandPrompt.allCases, id: \.rawValue) { prompt in
                        Text(prompt.rawValue).tag(prompt)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.accessoryBar)
                .labelsHidden()
                .frame(width: 80)

                TextField("wine.command", text: $command, prompt: Text(verbatim: prompt.defaultCommand))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(runningTask != nil)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(messages, id: \.uuid) { message in
                            view(for: message)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: scrolledID) { oldValue, newValue in
                    guard oldValue != newValue, let newValue = newValue else { return }
                    proxy.scrollTo(newValue)
                }
            }
            HStack {
                Button("wine.command.clear", systemImage: "trash") {
                    messages = []
                }.labelStyle(.iconOnly)
                Spacer()
                Button("create.cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("button.run") {
                    run(command: command, prompt: prompt, showProcessInfo: true)
                }
                .disabled(runningTask != nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 800, height: 500)
        .onChange(of: prompt, {
            command = ""
            run(command: prompt.defaultCommand, prompt: prompt, showProcessInfo: false)
        })
        .onAppear {
            run(command: prompt.defaultCommand, prompt: prompt, showProcessInfo: false)
        }
    }

    @ViewBuilder private func view(for message: Message) -> some View {
        let id = message.uuid.uuidString

        switch message.output {
        case .started(let process):
            Text("Started process `\(process.processIdentifier)`")
                .monospaced()
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8)
                .selectionDisabled(false)
        case .message(let messageText):
            HStack(alignment: .firstTextBaseline) {
                if let lineNumber = message.lineNumber {
                    Text(String("\(lineNumber)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(messageText)
                    .monospaced()
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .selectionDisabled(false)
            }
            .id(id)
        case .error(let messageText):
            HStack(alignment: .firstTextBaseline) {
                if let lineNumber = message.lineNumber {
                    Text(String("\(lineNumber)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(messageText)
                    .monospaced()
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .selectionDisabled(false)
            }
            .id(id)
        case .terminated(let process):
            Text("Terminated process `\(process.processIdentifier)` (\(process.terminationStatus))")
                .id(id)
                .monospaced()
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8)
                .selectionDisabled(false)
        }
    }

    private func run(command: String, prompt: CommandPrompt, showProcessInfo: Bool) {
        let command = command.isEmpty ? prompt.defaultCommand : command
        let commands = split(command: command)

        Task {
            await runningTask?.value

            let task = Task.detached {
                var lineNumber: UInt = 0

                do {
                    for await output in try prompt.run(args: commands, for: bottle) {
                        var uuid = UUID()

                        switch output {
                        case .message(let message):
                            self.messages.append(Message(
                                uuid: uuid,
                                lineNumber: lineNumber,
                                output: .message(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                            )
                        case .error(let message):
                            self.messages.append(Message(
                                uuid: uuid,
                                lineNumber: lineNumber,
                                output: .error(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                            )
                            scrolledID = uuid.uuidString
                        case .terminated, .started:
                            guard showProcessInfo else { break }

                            self.messages.append(Message(
                                uuid: uuid,
                                lineNumber: lineNumber,
                                output: output
                            ))

                            switch output {
                            case .started:
                                uuid = UUID()
                                self.messages.append(Message(
                                    uuid: uuid,
                                    lineNumber: lineNumber,
                                    output: .message("$ \(commands.joined(separator: " "))")
                                ))

                                scrolledID = uuid.uuidString
                            default:
                                scrolledID = uuid.uuidString
                            }
                        }

                        scrolledID = uuid.uuidString
                        lineNumber += 1
                    }
                } catch {
                    let uuid = UUID()
                    self.messages.append(Message(
                        uuid: uuid,
                        lineNumber: lineNumber,
                        output: .error(String(describing: error))
                    ))
                    scrolledID = uuid.uuidString
                }
            }

            runningTask = task
            await task.value
            runningTask = nil
        }
    }

    func split(command: String) -> [String] {
        var start = command.startIndex
        var end = command.startIndex
        var foundPathBreak = false
        var results: [String] = []

        while end < command.endIndex {
            let char = command[end]

            switch char {
            case " ":
                if !foundPathBreak || !searchForClosingBreak(command: command, index: command.index(after: end)) {
                    foundPathBreak = false
                    results.append(String(command[start..<end]))
                    start = command.index(after: end)
                }
            case "\\":
                foundPathBreak = true
            default:
                break
            }

            end = command.index(after: end)
        }

        if start < end {
            results.append(String(command[start..<end]))
        }

        return results
    }

    private func searchForClosingBreak(command: String, index: String.Index) -> Bool {
        var index = index
        var previousIsSpace = false

        while index < command.endIndex {
            let char = command[index]

            switch char {
            case " ":
                // Another space could be possible
                previousIsSpace = true
            case "\\":
                return true
            case "-":
                guard previousIsSpace else { break }
                return true
            default:
                previousIsSpace = false
            }

            index = command.index(after: index)
        }

        return false
    }
}
