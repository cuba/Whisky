//
//  GPTKDownloadView.swift
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

struct GPTKDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var errorMessage: String?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    var body: some View {
        VStack {
            VStack {
                Text("setup.gptk.download")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.gptk.download.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack {
                    ProgressView(value: fractionProgress, total: 1)

                    if let errorMessage = errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    } else {
                        HStack {
                            HStack(spacing: 8) {
                                let progress = formatBytes(bytes: completedBytes)
                                let total = formatBytes(bytes: totalBytes)
                                Text("setup.gptk.progress\(progress).of\(total)")

                                if let remainingTime = formatRemainingTime(
                                    remainingBytes: totalBytes - completedBytes
                                ) {
                                    Text(verbatim: "-")
                                    Text("setup.gptk.eta.\(remainingTime)")
                                }
                            }
                            .font(.subheadline)
                            .monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task {
                if let url: URL = URL(string: "https://data.getwhisky.app/Libraries.zip") {
                    downloadTask = URLSession.shared.downloadTask(with: url) { url, _, _ in
                        guard let url = url else { return }
                        tarLocation = url
                        proceed()
                    }
                    observation = downloadTask?.observe(\.countOfBytesReceived) { task, _ in
                        Task {
                            await MainActor.run {
                                let currentTime = Date()
                                let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
                                if completedBytes > 0 {
                                    downloadSpeed = Double(completedBytes) / elapsedTime
                                }
                                totalBytes = task.countOfBytesExpectedToReceive
                                completedBytes = task.countOfBytesReceived
                                fractionProgress = Double(completedBytes) / Double(totalBytes)
                            }
                        }
                    }
                    startTime = Date()
                    downloadTask?.resume()
                }
            }
        }
    }

    private func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    private func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0
    }

    private func formatRemainingTime(remainingBytes: Int64) -> String? {
        guard shouldShowEstimate() else { return nil }

        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(remainingTimeInSeconds))
    }

    func proceed() {
        path.append(.gptkInstall)
    }
}
