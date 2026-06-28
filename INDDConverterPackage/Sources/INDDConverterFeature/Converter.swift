import Foundation
import AppKit

public struct ConversionResult: Sendable {
    public let path: String
    public let success: Bool
    public let error: String?
}

// Thread-safe cancellation flag that the background scan can read.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func reset() { lock.lock(); cancelled = false; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

@MainActor
public class Converter: ObservableObject {
    @Published public var isRunning = false
    @Published public var progress: Double = 0
    @Published public var currentFile = ""
    @Published public var results: [ConversionResult] = []

    public init() {}

    public static func inDesignInstalled() -> Bool {
        let appDir = URL(fileURLWithPath: "/Applications")
        let items = (try? FileManager.default.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)) ?? []
        return items.contains { $0.lastPathComponent.hasPrefix("Adobe InDesign") }
    }

    // Synchronous (used by the drop handler for individual files).
    public func findInddFiles(in folderURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "indd" }
    }

    // Folders that trigger macOS privacy prompts or never contain .indd files.
    // We skip these by name *before* reading their contents, so no prompt appears.
    private nonisolated static let skippedDirectoryNames: Set<String> = [
        "Music", "Pictures", "Movies", "Photos Library.photoslibrary",
        "Library", ".Trash", "node_modules", ".git"
    ]

    // Absolute system paths skipped when scanning from "/" (no .indd there).
    private nonisolated static let skippedRootPaths: Set<String> = [
        "/System", "/usr", "/bin", "/sbin", "/private",
        "/dev", "/cores", "/opt", "/etc", "/var", "/tmp",
        "/Volumes"  // volumes are handled separately as their own roots
    ]

    // A folder is skipped if its absolute path or its name is on the lists above.
    private nonisolated static func shouldSkip(_ url: URL) -> Bool {
        skippedRootPaths.contains(url.path) || skippedDirectoryNames.contains(url.lastPathComponent)
    }

    // Entry point: scan several roots at once, summing total bytes across all of them.
    public func findInddFilesAsync(in roots: [URL]) async -> [URL] {
        cancelFlag.reset()
        isSearching = true
        searchCount = 0
        scannedBytes = 0
        scanBytesPerSecond = 0
        etaSeconds = 0
        volumeTotalBytes = 0
        liveFoundFiles = []
        scanStartTime = Date()

        // Sum the total capacity of all roots up front.
        for root in roots {
            let isVol = (try? root.resourceValues(forKeys: [.isVolumeKey]).isVolume) ?? false
            if isVol {
                let cap = (try? root.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity).flatMap { Int64($0) } ?? 0
                volumeTotalBytes += cap
            } else {
                // Run `du` in the background — does not block the scan.
                let rootPath = root.path
                DispatchQueue.global(qos: .background).async {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                    p.arguments = ["-sk", rootPath]
                    let pipe = Pipe(); p.standardOutput = pipe
                    try? p.run(); p.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if let kb = Int64(out.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "") {
                        DispatchQueue.main.async { self.volumeTotalBytes += kb * 1024 }
                    }
                }
            }
        }

        // Scan runs on a GCD thread (not a Swift concurrency task) — more stable across TCC prompts.
        let startTime = scanStartTime
        let result: [URL] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                // Accumulators span ALL roots — otherwise volume 2 would overwrite
                // volume 1's matches in the live display.
                var all: [URL] = []
                var totalBytes: Int64 = 0
                for root in roots {
                    if self.isScanCancelled() { break }
                    self._scanFolderGCD(root, startTime: startTime,
                                        allFound: &all, totalBytes: &totalBytes)
                }
                let finalCount = all.count
                let finalSnapshot = all
                let finalBytes = totalBytes
                DispatchQueue.main.async {
                    self.isSearching = false
                    self.currentSearchPath = ""
                    self.scannedBytes = finalBytes
                    self.searchCount = finalCount
                    self.liveFoundFiles = finalSnapshot
                    cont.resume(returning: all)
                }
            }
        }
        return result
    }

    // Iterative depth-first scan on a GCD thread.
    //
    // We deliberately do NOT use FileManager.enumerator: it prefetches a directory's
    // contents before we get a chance to skip it, which makes macOS show a privacy
    // prompt for Music / Pictures even though we never want to enter them. Here we
    // check `shouldSkip` *before* ever reading a folder's contents, so protected
    // folders are never touched and no prompt appears.
    //
    // allFound/totalBytes are cumulative across all roots so the live counter never
    // jumps back when the next volume starts.
    private nonisolated func _scanFolderGCD(_ rootURL: URL, startTime: Date,
                                            allFound: inout [URL], totalBytes: inout Int64) {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]   // for contentsOfDirectory
        let keySet: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]  // for resourceValues

        var stack: [URL] = [rootURL]          // explicit work stack (avoids deep recursion)
        var pendingBytes: Int64 = 0
        var pendingPath = ""
        var lastUIUpdate = Date()
        var loopCounter = 0

        while let dir = stack.popLast() {
            if isScanCancelled() { return }
            if Converter.shouldSkip(dir) { continue }   // never read protected/irrelevant folders

            pendingPath = dir.path.replacingOccurrences(of: home, with: "~")

            // Reading the directory's contents is what could trigger a TCC prompt —
            // but only for Desktop/Documents/Downloads, which the user actually wants scanned.
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                loopCounter += 1
                if loopCounter & 0xFF == 0, isScanCancelled() { return }
                if Converter.shouldSkip(entry) { continue }   // skip before stat → no prompt

                let vals = try? entry.resourceValues(forKeys: keySet)
                if vals?.isDirectory == true {
                    stack.append(entry)
                } else {
                    pendingBytes += Int64(vals?.fileSize ?? 0)
                    if entry.pathExtension.lowercased() == "indd"
                        && entry.lastPathComponent != "_indd_convert_work.indd" {  // ignore our own temp file
                        allFound.append(entry)
                    }
                }

                // Push UI updates only every 0.5s — fewer re-renders, smoother window/divider dragging.
                let now = Date()
                if now.timeIntervalSince(lastUIUpdate) >= 0.5 {
                    lastUIUpdate = now
                    totalBytes += pendingBytes
                    pendingBytes = 0
                    let bytes = totalBytes
                    let count = allFound.count
                    let path = pendingPath
                    let snapshot = Array(allFound)
                    let elapsed = Date().timeIntervalSince(startTime)
                    DispatchQueue.main.async {
                        self.scannedBytes = bytes
                        self.searchCount = count
                        self.liveFoundFiles = snapshot
                        if !path.isEmpty { self.currentSearchPath = path }
                        if elapsed > 1 { self.scanBytesPerSecond = Double(bytes) / elapsed }
                        // ETA only ever decreases: starts at 0.5% progress, never jumps up.
                        if self.volumeTotalBytes > 0 {
                            let progress = Double(bytes) / Double(self.volumeTotalBytes)
                            if progress > 0.005, elapsed > 2 {
                                let remaining = (elapsed / progress) - elapsed
                                if self.etaSeconds == 0 || remaining < self.etaSeconds {
                                    self.etaSeconds = remaining
                                }
                            }
                        }
                    }
                }
            }
        }

        // Carry this root's leftover bytes into the running total.
        totalBytes += pendingBytes
    }

    @Published public var isSearching = false
    @Published public var searchCount = 0
    @Published public var currentSearchPath = ""
    @Published public var scannedBytes: Int64 = 0
    @Published public var volumeTotalBytes: Int64 = 0
    @Published public var scanBytesPerSecond: Double = 0
    @Published public var etaSeconds: Double = 0
    @Published public var liveFoundFiles: [URL] = []
    public var scanStartTime: Date = Date()

    // Cancellation flag, thread-safe and usable from nonisolated code (its own Sendable class).
    private let cancelFlag = CancelFlag()
    public func cancelScan() { cancelFlag.cancel() }
    private nonisolated func isScanCancelled() -> Bool { cancelFlag.isCancelled }

    public func convert(files: [URL]) async {
        isRunning = true
        progress = 0
        results = []
        let total = Double(files.count)

        for (index, file) in files.enumerated() {
            currentFile = file.lastPathComponent
            let result = await convertSingle(file)
            results.append(result)
            progress = Double(index + 1) / total
        }

        isRunning = false
        currentFile = ""
    }

    private func convertSingle(_ url: URL) async -> ConversionResult {
        return await Task.detached(priority: .userInitiated) {
            await self._convertSingle(url)
        }.value
    }

    private nonisolated func _convertSingle(_ url: URL) async -> ConversionResult {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let tempIndd = desktop.appendingPathComponent("_indd_convert_work.indd")
        let tempIdml = desktop.appendingPathComponent("_indd_convert_work.idml")
        let idmlURL = url.deletingPathExtension().appendingPathExtension("idml")

        // Skip if the IDML already exists.
        if FileManager.default.fileExists(atPath: idmlURL.path) {
            return ConversionResult(path: url.path, success: true, error: "bereits konvertiert")
        }

        try? FileManager.default.removeItem(at: tempIndd)
        try? FileManager.default.removeItem(at: tempIdml)

        do {
            try FileManager.default.copyItem(at: url, to: tempIndd)
        } catch {
            return ConversionResult(path: url.path, success: false, error: "Kopieren fehlgeschlagen: \(error.localizedDescription)")
        }

        let script = """
with timeout of 600 seconds
    tell application "Adobe InDesign 2026"
        -- Correct property: it lives on "script preferences", not on the app itself.
        -- "never interact" suppresses the missing-links and missing-fonts dialogs on open.
        set user interaction level of script preferences to never interact
        try
            set redraw of script preferences to false
        end try
        set theDoc to missing value
        try
            set theAlias to POSIX file "\(tempIndd.path)" as alias
            set theDoc to open theAlias
            tell theDoc
                export format InDesign Markup to "\(tempIdml.path)" without showing options
            end tell
        end try
        if theDoc is not missing value then
            try
                close theDoc saving no
            end try
        end if
        try
            set redraw of script preferences to true
        end try
        set user interaction level of script preferences to interact with all
    end tell
end timeout
"""

        // Dialog watcher as a fallback: auto-clicks any remaining dialogs.
        // Priority list — the "continue without changes" buttons first,
        // never "Cancel"/"Update" (which would abort the open or start a relink).
        let watcherScript = """
set dismissNames to {"Don't Update", "Nicht aktualisieren", "Nicht aktuali", "Ignorieren", "Ignore", "Beibehalten", "Keep", "Übernehmen", "Apply", "OK", "Fortfahren", "Continue", "Schließen", "Close", "Fertig", "Done"}
repeat 2000 times
    delay 0.3
    try
        tell application "System Events"
            if exists (process "Adobe InDesign 2026") then
                tell process "Adobe InDesign 2026"
                    repeat with w in (every window)
                        set btns to {}
                        try
                            set btns to buttons of w
                        end try
                        try
                            repeat with s in (sheets of w)
                                set btns to btns & (buttons of s)
                            end repeat
                        end try
                        if (count of btns) > 0 then
                            repeat with targetName in dismissNames
                                set clicked to false
                                repeat with b in btns
                                    try
                                        if (name of b) contains targetName then
                                            click b
                                            set clicked to true
                                            exit repeat
                                        end if
                                    end try
                                end repeat
                                if clicked then exit repeat
                            end repeat
                        end if
                    end repeat
                end tell
            end if
        end tell
    end try
end repeat
"""
        let watcherFile = desktop.appendingPathComponent("_indd_watcher.applescript")
        try? watcherScript.write(to: watcherFile, atomically: true, encoding: .utf8)

        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        watcher.arguments = [watcherFile.path]
        try? watcher.run()

        // Main conversion
        let scriptFile = desktop.appendingPathComponent("_indd_convert_script.applescript")
        do {
            try script.write(to: scriptFile, atomically: true, encoding: .utf8)
        } catch {
            watcher.terminate()
            try? FileManager.default.removeItem(at: watcherFile)
            try? FileManager.default.removeItem(at: tempIndd)
            return ConversionResult(path: url.path, success: false, error: "Script schreiben fehlgeschlagen: \(error.localizedDescription)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptFile.path]
        let pipe = Pipe()
        process.standardError = pipe

        // Async warten — blockiert NICHT den Swift-Concurrency-Thread-Pool
        let exitStatus: Int32 = await withCheckedContinuation { cont in
            process.terminationHandler = { p in
                cont.resume(returning: p.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                cont.resume(returning: -1)
            }
            // Safety timeout: abort after 600s (matches the script timeout).
            DispatchQueue.global().asyncAfter(deadline: .now() + 600) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        watcher.terminate()
        try? FileManager.default.removeItem(at: scriptFile)
        try? FileManager.default.removeItem(at: watcherFile)
        try? FileManager.default.removeItem(at: tempIndd)

        if exitStatus != 0 {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unbekannter Fehler"
            try? FileManager.default.removeItem(at: tempIdml)
            return ConversionResult(path: url.path, success: false, error: errMsg)
        }

        do {
            if FileManager.default.fileExists(atPath: idmlURL.path) {
                try FileManager.default.removeItem(at: idmlURL)
            }
            try FileManager.default.moveItem(at: tempIdml, to: idmlURL)
            return ConversionResult(path: url.path, success: true, error: nil)
        } catch {
            return ConversionResult(path: url.path, success: false, error: "Verschieben fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
