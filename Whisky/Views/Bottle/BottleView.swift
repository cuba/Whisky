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
    @State private var repairing: Bool = false

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
                        CommandView(bottle: bottle)
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
