//
//  Wine.swift
//  Whisky
//
//  Created by Isaac Marovitz on 23/03/2023.
//

import Foundation

class Wine {
    static let binFolder: URL = (Bundle.main.resourceURL ?? URL(fileURLWithPath: ""))
        .appendingPathComponent("Libraries")
        .appendingPathComponent("Wine")
        .appendingPathComponent("bin")

    static let dxvkFolder: URL = (Bundle.main.resourceURL ?? URL(fileURLWithPath: ""))
        .appendingPathComponent("Libraries")
        .appendingPathComponent("DXVK")

    static let wineBinary: URL = binFolder
        .appendingPathComponent("wine64")

    static let wineserverBinary: URL = binFolder
        .appendingPathComponent("wineserver")

    static func run(_ args: [String],
                    bottle: Bottle? = nil,
                    environment: [String: String]? = nil) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = wineBinary
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        process.currentDirectoryURL = binFolder

        if let bottle = bottle {
            var env: [String: String]
            env = ["WINEPREFIX": bottle.url.path,
                   "WINEDEBUG": "fixme-all",
                   "WINEBOOT_HIDE_DIALOG": "1"]

            if let environment = environment {
                for variable in environment.keys {
                    env[variable] = environment[variable]
                }
            }

            bottle
                .settings
                .settings
                .baseSettings
                .environmentVariables(environment: &env)

            if bottle.settings.dxvk {
                enableDXVK(bottle: bottle)
            }

            process.environment = env
        }

        try process.run()

        if let output = try pipe.fileHandleForReading.readToEnd() {
            let outputString = String(decoding: output, as: UTF8.self)
            print(outputString)
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                throw outputString
            }

            return outputString
        }

        return ""
    }

    static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = wineserverBinary
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        process.currentDirectoryURL = binFolder
        process.environment = ["WINEPREFIX": bottle.url.path]

        try process.run()

        if let output = try pipe.fileHandleForReading.readToEnd() {
            let outputString = String(decoding: output, as: UTF8.self)
            print(outputString)
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                throw outputString
            }

            return outputString
        }

        return ""
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

    @discardableResult
    static func cfg(bottle: Bottle) async throws -> String {
        return try await run(["winecfg"], bottle: bottle)
    }

    @discardableResult
    static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        return try await run(["winecfg", "-v", win.rawValue], bottle: bottle)
    }

    @discardableResult
    static func runProgram(program: Program) async throws -> String {
        return try await run(["start", "/unix", program.url.path],
                             bottle: program.bottle,
                             environment: program.settings.environment)
    }

    @discardableResult
    static func killBottle(bottle: Bottle) async throws -> String {
        return try await runWineserver(["-k"], bottle: bottle)
    }

    static func enableDXVK(bottle: Bottle) {
        let enumerator64 = FileManager.default.enumerator(at: Wine.dxvkFolder
                                                                .appendingPathComponent("x64"),
                                                          includingPropertiesForKeys: [.isRegularFileKey])

        while let url = enumerator64?.nextObject() as? URL {
            if url.pathExtension == "dll" {
                let system32 = bottle.url
                    .appendingPathComponent("drive_c")
                    .appendingPathComponent("windows")
                    .appendingPathComponent("system32")

                let original = system32
                    .appendingPathComponent(url.lastPathComponent)

                do {
                    try FileManager.default.removeItem(at: original)
                    try FileManager.default.copyItem(at: url,
                                                     to: original)
                } catch {
                    print("Failed to replace \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        let enumerator32 = FileManager.default.enumerator(at: Wine.dxvkFolder
                                                                .appendingPathComponent("x32"),
                                                          includingPropertiesForKeys: [.isRegularFileKey])

        while let url = enumerator32?.nextObject() as? URL {
            if url.pathExtension == "dll" {
                let syswow64 = bottle.url
                    .appendingPathComponent("drive_c")
                    .appendingPathComponent("windows")
                    .appendingPathComponent("syswow64")

                let original = syswow64
                    .appendingPathComponent(url.lastPathComponent)

                do {
                    try FileManager.default.removeItem(at: original)
                    try FileManager.default.copyItem(at: url,
                                                     to: original)
                } catch {
                    print("Failed to replace \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }
}

extension String: Error {}

enum WineInterfaceError: Error {
    case invalidResponce
}
