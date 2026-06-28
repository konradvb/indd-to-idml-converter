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

    // System-Pfade die beim Scan von / übersprungen werden (keine .indd dort)
    private nonisolated static let skippedRootPaths: Set<String> = [
        "/System", "/usr", "/bin", "/sbin", "/private",
        "/dev", "/cores", "/opt", "/etc", "/var", "/tmp",
        "/Volumes"  // Volumes werden separat als eigene Roots behandelt
    ]

    // Einstiegspunkt: mehrere Roots auf einmal scannen, GB-Summe über alle
    public func findInddFilesAsync(in roots: [URL]) async -> [URL] {
        isSearching = true
        searchCount = 0
        scannedBytes = 0
        scanBytesPerSecond = 0
        peakRemainingSeconds = 0
        volumeTotalBytes = 0
        scanStartTime = Date()

        // Gesamtkapazität aller Roots vorab summieren
        for root in roots {
            let isVol = (try? root.resourceValues(forKeys: [.isVolumeKey]).isVolume) ?? false
            if isVol {
                let cap = (try? root.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity).flatMap { Int64($0) } ?? 0
                volumeTotalBytes += cap
            } else {
                // du im Hintergrund — blockiert den Scan nicht
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

        // Scan läuft auf GCD-Thread — kein Swift-Concurrency-Task, stabiler bei TCC-Dialogen
        let startTime = scanStartTime
        let result: [URL] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var all: [URL] = []
                for root in roots {
                    all.append(contentsOf: self._scanFolderGCD(root, startTime: startTime))
                }
                DispatchQueue.main.async {
                    self.isSearching = false
                    self.currentSearchPath = ""
                    cont.resume(returning: all)
                }
            }
        }
        return result
    }

    // Scan läuft synchron auf GCD-Thread — robust gegen TCC-Unterbrechungen
    private nonisolated func _scanFolderGCD(_ folderURL: URL, startTime: Date) -> [URL] {
        // errorHandler: Fehler (z.B. Zugriff verweigert) ignorieren statt crashen
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in return true }
        ) else { return [] }

        var found: [URL] = []
        var pendingBytes: Int64 = 0
        var pendingCount = 0
        var lastUIUpdate = Date()

        while let obj = enumerator.nextObject() {
            guard let url = obj as? URL else { continue }

            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let p = url.path
                if Converter.skippedRootPaths.contains(p) || Converter.skippedDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                } else {
                    let display = p.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                    DispatchQueue.main.async { self.currentSearchPath = display }
                }
                continue
            }

            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            pendingBytes += fileSize
            if url.pathExtension.lowercased() == "indd" {
                found.append(url)
                pendingCount = found.count
            }

            // UI nur alle 0.3s updaten — sonst bremst DispatchQueue.main.async den Scan aus
            let now = Date()
            if now.timeIntervalSince(lastUIUpdate) >= 0.3 {
                lastUIUpdate = now
                let bytes = pendingBytes
                let count = pendingCount
                let startTime = startTime
                DispatchQueue.main.async {
                    self.scannedBytes += bytes
                    self.searchCount = count
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed > 1 { self.scanBytesPerSecond = Double(self.scannedBytes) / elapsed }
                }
                pendingBytes = 0
            }
        }
        // Rest-Update
        if pendingBytes > 0 {
            let bytes = pendingBytes; let count = pendingCount
            DispatchQueue.main.async {
                self.scannedBytes += bytes
                self.searchCount = count
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 1 { self.scanBytesPerSecond = Double(self.scannedBytes) / elapsed }
            }
        }
        return found
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
