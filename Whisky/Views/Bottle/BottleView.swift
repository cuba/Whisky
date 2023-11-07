//
//  BottleView.swift
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
import UniformTypeIdentifiers
import WhiskyKit

enum BottleStage {
    case config
    case programs
}

struct BottleView: View {
    @ObservedObject var bottle: Bottle
    @State private var path = NavigationPath()
    @State private var programLoading: Bool = false
    @State private var showWinetricksSheet: Bool = false
    @State private var showWineCommands: Bool = false

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let pinnedPrograms = bottle.programs.pinned
                if pinnedPrograms.count > 0 {
                    LazyVGrid(columns: gridLayout, alignment: .center) {
                        ForEach(bottle.settings.pins, id: \.url) { pin in
                            PinsView(
                                bottle: bottle, pin: pin, path: $path
                            )
                        }
                    }
                    .padding()
                }
                Form {
                    NavigationLink(value: BottleStage.programs) {
                        HStack {
                            Image(systemName: "list.bullet")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14, alignment: .center)
                            Text("tab.programs")
                        }
                    }
                    NavigationLink(value: BottleStage.config) {
                        HStack {
                            Image(systemName: "gearshape")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14, alignment: .center)
                            Text("tab.config")
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .bottomBar {
                HStack {
                    Spacer()
                    Button("run.command") {
                        showWineCommands.toggle()
                    }.sheet(isPresented: $showWineCommands) {
                        WineCommandView(bottle: bottle)
                    }
                    Button("button.cDrive") {
                        bottle.openCDrive()
                    }
                    Button("button.winetricks") {
                        showWinetricksSheet.toggle()
                    }
                    Button("button.run") {
                        Task {
                            guard let fileURL = await bottle.choseFileForRun() else { return }
                            programLoading = false

                            do {
                                try await bottle.openFileForRun(url: fileURL)
                                updateStartMenu()
                            } catch {
                                Bottle.logger.error("Failed to run external program: \(error)")
                            }

                            programLoading = false
                        }
                    }
                    .disabled(programLoading)
                    if programLoading {
                        Spacer()
                            .frame(width: 10)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding()
            }
            .onAppear {
                updateStartMenu()
            }
            .disabled(!bottle.isActive)
            .navigationTitle(bottle.settings.name)
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
            }
            .onChange(of: bottle.settings, { oldValue, newValue in
                guard oldValue != newValue else { return }
                // Trigger a reload
                BottleVM.shared.bottles = BottleVM.shared.bottles
            })
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(
                        bottle: bottle, path: $path
                    )
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    private func updateStartMenu() {
        bottle.programs = bottle.updateInstalledPrograms()
        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            // For some godforsaken reason "foo/bar" != "foo/Bar" so...
            program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                if !bottle.settings.pins.contains(where: { $0.url == program.url }) {
                    bottle.settings.pins.append(PinnedProgram(name: program.name
                                                                    .replacingOccurrences(of: ".exe", with: ""),
                                                              url: program.url))
                }
            }
        }
    }
}

struct WinetricksView: View {
    var bottle: Bottle
    @State var winetricksCommand: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            HStack {
                Text("winetricks.title")
                    .bold()
                Spacer()
            }
            Divider()
            TextField(String(), text: $winetricksCommand)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .labelsHidden()
            Spacer()
            HStack {
                Spacer()
                Button("create.cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("button.run") {
                    Task.detached(priority: .userInitiated) {
                        await Winetricks.runCommand(command: winetricksCommand, bottle: bottle)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 350, height: 140)
    }
}

struct WineCommandView: View {
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
                return try Wine.runWineProcess(args: args, bottle: bottle, clearOutput: false)
            case .wineserver:
                return try Wine.runWineserverProcess(args: args, bottle: bottle, clearOutput: false)
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @AppStorage("wineCommand") private var command = ""
    @AppStorage("wineCommandPrompt") private var prompt: CommandPrompt = .wine
    @State private var loading = false
    @State private var output: [ProcessOutput] = []
    @State private var runningTask: Task<(), Never>?

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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(output, id: \.self) { output in
                        switch output {
                        case .started(let process):
                            Text("Started process `\(process.processIdentifier)`")
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        case .message(let message):
                            Text(message)
                                .monospaced()
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        case .error(let message):
                            Text(message)
                                .monospaced()
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        case .terminated(let process):
                            Text("Terminated process `\(process.processIdentifier)` (\(process.terminationStatus))")
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            Divider()
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Button("wine.command.clear", systemImage: "trash") {
                    output = []
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

    private func run(command: String, prompt: CommandPrompt, showProcessInfo: Bool) {
        let command = command.isEmpty ? prompt.defaultCommand : command
        let commands = split(command: command)

        Task {
            await runningTask?.value

            let task = Task.detached {
                do {
                    for await output in try prompt.run(args: commands, for: bottle) {
                        switch output {
                        case .message, .error:
                            self.output.append(output)
                        case .terminated, .started:
                            guard showProcessInfo else { break }
                            self.output.append(output)

                            switch output {
                            case .started:
                                self.output.append(.message("$ \(commands.joined(separator: " "))"))
                            default:
                                break
                            }
                        }
                    }
                } catch {
                    self.output = [.error(String(describing: error))]
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
