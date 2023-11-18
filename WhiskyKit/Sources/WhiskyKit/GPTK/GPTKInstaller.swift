//
//  GPTKInstaller.swift
//  WhiskyKit
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
import SemanticVersion

public class GPTKInstaller {
    /// The whisky application folder
    public static let applicationFolder = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    public static func isGPTKInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: libraryFolder.path)
    }

    public static func install(from zipFile: URL) throws {
        if !FileManager.default.fileExists(atPath: applicationFolder.path) {
            try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
        } else {
            // Recreate it
            try FileManager.default.removeItem(at: applicationFolder)
            try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
        }

        try Tar.untar(tarBall: zipFile, toURL: applicationFolder)
        let tarFile = applicationFolder.appending(path: "Libraries").appendingPathExtension("tar")
          .appendingPathExtension("gz")
        try Tar.untar(tarBall: tarFile, toURL: applicationFolder)
        try FileManager.default.removeItem(at: zipFile)
    }

    public static func uninstall() throws {
        try FileManager.default.removeItem(at: libraryFolder)
    }

    public static func shouldUpdateGPTK() async throws -> (shouldUpdate: Bool, version: SemanticVersion) {
        let localVersion = try gptkVersion()
        let versionPlistURL = "https://data.getwhisky.app/GPTKVersion.plist"
        guard let remoteUrl = URL(string: versionPlistURL) else { return (false, SemanticVersion(0, 0, 0)) }

        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: URLRequest(url: remoteUrl)) { data, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = data else {
                    continuation.resume(returning: (false, SemanticVersion(0, 0, 0)))
                    return
                }

                do {
                    let decoder = PropertyListDecoder()
                    let remoteInfo = try decoder.decode(GPTKVersion.self, from: data)
                    let remoteVersion = remoteInfo.version
                    let isRemoteNewer = remoteVersion > localVersion
                    continuation.resume(returning: (isRemoteNewer, remoteVersion))
                } catch {
                    print(error)
                    continuation.resume(throwing: error)
                }
            }.resume()
        }
    }

    public static func gptkVersion() throws -> SemanticVersion {
        let versionPlist = libraryFolder.appending(path: "GPTKVersion").appendingPathExtension("plist")
        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: versionPlist)
        let info = try decoder.decode(GPTKVersion.self, from: data)
        return info.version
    }
}

struct GPTKVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
