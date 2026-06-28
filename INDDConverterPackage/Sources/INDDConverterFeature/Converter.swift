import Foundation
import AppKit

public struct ConversionResult: Sendable {
    public let path: String
    public let success: Bool
    public let error: String?
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

    // Synchron (für Drop-Handler von einzelnen Dateien)
    public func findInddFiles(in folderURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "indd" }
    }

    // Verzeichnisse die macOS-Datenschutz-Dialoge auslösen oder irrelevant sind
    private nonisolated static let skippedDirectoryNames: Set<String> = [
        "Music", "Photos Library.photoslibrary", "Pictures",
        "Library", ".Trash", "node_modules", ".git"
    ]

    // Async mit Live-Fortschritt (für Ordner-Suche)
    public func findInddFilesAsync(in folderURL: URL) async -> [URL] {
        isSearching = true
        searchCount = 0
        scannedBytes = 0
        scanBytesPerSecond = 0
        peakRemainingSeconds = 0
        scanStartTime = Date()

        // Nur bei echtem Volume-Root (z.B. /, /Volumes/Backup) die Festplattenkapazität zeigen
        let isVolumeRoot = (try? folderURL.resourceValues(forKeys: [.isVolumeKey]).isVolume) ?? false
        if isVolumeRoot {
            volumeTotalBytes = (try? folderURL.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity).flatMap { Int64($0) } ?? 0
        } else {
            volumeTotalBytes = 0
            // Ordnergröße im Hintergrund mit du schätzen
            Task.detached(priority: .background) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                process.arguments = ["-sk", folderURL.path]
                let pipe = Pipe()
                process.standardOutput = pipe
                try? process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if let kb = Int64(output.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "") {
                    await MainActor.run { self.volumeTotalBytes = kb * 1024 }
                }
            }
        }
        defer { isSearching = false; currentSearchPath = "" }

        return await Task.detached(priority: .userInitiated) {
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            var found: [URL] = []
            while let obj = enumerator.nextObject() {
                guard let url = obj as? URL else { continue }

                // Geschützte/irrelevante Ordner überspringen
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue {
                    if Converter.skippedDirectoryNames.contains(url.lastPathComponent) {
                        enumerator.skipDescendants()
                    } else {
                        let dirPath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                        await MainActor.run { self.currentSearchPath = dirPath }
                    }
                    continue
                }

                // Dateigröße zum Scan-Fortschritt addieren
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0

                if url.pathExtension.lowercased() == "indd" {
                    found.append(url)
                    let count = found.count
                    await MainActor.run {
                        self.searchCount = count
                        self.scannedBytes += fileSize
                        let elapsed = Date().timeIntervalSince(self.scanStartTime)
                        if elapsed > 1 { self.scanBytesPerSecond = Double(self.scannedBytes) / elapsed }
                    }
                } else {
                    await MainActor.run {
                        self.scannedBytes += fileSize
                        let elapsed = Date().timeIntervalSince(self.scanStartTime)
                        if elapsed > 1 { self.scanBytesPerSecond = Double(self.scannedBytes) / elapsed }
                    }
                }
            }
            return found
        }.value
    }

    @Published public var isSearching = false
    @Published public var searchCount = 0
    @Published public var currentSearchPath = ""
    @Published public var scannedBytes: Int64 = 0
    @Published public var volumeTotalBytes: Int64 = 0
    @Published public var scanBytesPerSecond: Double = 0
    @Published public var peakRemainingSeconds: Double = 0
    public var scanStartTime: Date = Date()

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

        // Überspringen wenn IDML schon existiert
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
with timeout of 300 seconds
    tell application "Adobe InDesign 2026"
        -- Dialoge vor dem Öffnen deaktivieren
        set userInteractionLevel to never interact
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
        set userInteractionLevel to interact with all
    end tell
end timeout
"""

        // Dialog-Watcher: klickt automatisch Verknüpfungs-Dialoge in InDesign weg
        let watcherScript = """
repeat 120 times
    delay 0.5
    tell application "System Events"
        if exists process "Adobe InDesign 2026" then
            tell process "Adobe InDesign 2026"
                repeat with w in windows
                    try
                        repeat with b in buttons of w
                            set btnName to name of b
                            if btnName contains "Don't Update" or btnName contains "Nicht aktuali" or btnName contains "Beibehalten" or btnName contains "OK" or btnName contains "Schließen" then
                                click b
                                exit repeat
                            end if
                        end repeat
                    end try
                    try
                        repeat with s in sheets of w
                            repeat with b in buttons of s
                                set btnName to name of b
                                if btnName contains "Don't Update" or btnName contains "Nicht aktuali" or btnName contains "Beibehalten" or btnName contains "OK" then
                                    click b
                                    exit repeat
                                end if
                            end repeat
                        end try
                    end try
                end repeat
            end tell
        end if
    end tell
end repeat
"""
        let watcherFile = desktop.appendingPathComponent("_indd_watcher.applescript")
        try? watcherScript.write(to: watcherFile, atomically: true, encoding: .utf8)

        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        watcher.arguments = [watcherFile.path]
        try? watcher.run()

        // Hauptkonvertierung
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
            // Sicherheits-Timeout: nach 360s abbrechen
            DispatchQueue.global().asyncAfter(deadline: .now() + 360) {
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
