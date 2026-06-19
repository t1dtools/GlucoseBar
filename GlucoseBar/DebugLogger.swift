//
//  DebugLogger.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2026-06-12.
//

import Foundation
import OSLog

// MARK: - DebugLogger

final class DebugLogger: @unchecked Sendable {

    static let shared = DebugLogger()

    private let queue = DispatchQueue(label: "tools.t1d.GlucoseBar.debugLogger")
    private var fileHandle: FileHandle?
    private(set) var currentLogURL: URL?

    private let maxLogFiles = 10

    private init() {}

    // MARK: - Public API

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debugMode")
    }

    /// Opens a fresh debug.log, archiving any existing one with a datestamp.
    func enable() {
        queue.async { [weak self] in
            self?.openLog()
        }
    }

    /// Flushes and closes the current log file.
    func disable() {
        queue.async { [weak self] in
            self?.closeLog()
        }
    }

    /// Write a message to the log file if debug mode is active.
    static func log(_ message: String, category: String, level: OSLogType) {
        guard shared.isEnabled else { return }
        shared.queue.async {
            shared.write(message, category: category, level: level)
        }
    }

    // MARK: - Private helpers

    private func logsDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = appSupport
            .appendingPathComponent("tools.t1d.GlucoseBar", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func openLog() {
        guard let dir = logsDirectory() else { return }

        let live = dir.appendingPathComponent("debug.log")

        // Archive any existing session file
        if FileManager.default.fileExists(atPath: live.path) {
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")   // Windows-safe filename
            let archive = dir.appendingPathComponent("debug-\(timestamp).log")
            try? FileManager.default.moveItem(at: live, to: archive)
        }

        // Create fresh file
        FileManager.default.createFile(atPath: live.path, contents: nil)

        pruneOldLogs(in: dir)

        do {
            let handle = try FileHandle(forWritingTo: live)
            fileHandle = handle
            currentLogURL = live
            let header = "--- GlucoseBar debug log opened \(isoNow()) ---\n"
            handle.write(Data(header.utf8))
        } catch {
            // Can't write to log file — silently bail
            fileHandle = nil
            currentLogURL = nil
        }
    }

    private func pruneOldLogs(in dir: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let archives = contents
            .filter { $0.lastPathComponent.hasPrefix("debug-") && $0.pathExtension == "log" }
            .sorted { url1, url2 in
                let d1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let d2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return d1 > d2
            }

        let keep = maxLogFiles - 1
        for url in archives.dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func closeLog() {
        guard let handle = fileHandle else { return }
        let footer = "--- GlucoseBar debug log closed \(isoNow()) ---\n"
        handle.write(Data(footer.utf8))
        try? handle.close()
        fileHandle = nil
    }

    private func write(_ message: String, category: String, level: OSLogType) {
        guard let handle = fileHandle else { return }
        let levelTag: String
        switch level {
        case .debug:   levelTag = "DEBUG  "
        case .info:    levelTag = "INFO   "
        case .error:   levelTag = "ERROR  "
        case .fault:   levelTag = "FAULT  "
        default:       levelTag = "NOTICE "
        }
        let line = "\(isoNow()) [\(levelTag)] [\(category)] \(message)\n"
        handle.write(Data(line.utf8))
    }

    private func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

// MARK: - Logger extension

extension Logger {
    /// Logs to OSLog and, when debug mode is enabled, also writes to the debug log file.
    func dlog(_ message: String, category: String, level: OSLogType = .default) {
        switch level {
        case .debug:
            self.debug("\(message, privacy: .public)")
        case .error:
            self.error("\(message, privacy: .public)")
        case .fault:
            self.fault("\(message, privacy: .public)")
        case .info:
            self.info("\(message, privacy: .public)")
        default:
            self.notice("\(message, privacy: .public)")
        }
        DebugLogger.log(message, category: category, level: level)
    }
}
