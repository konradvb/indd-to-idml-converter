import SwiftUI
import AppKit

private struct ResultRow: View {
    let result: ConversionResult

    var body: some View {
        let fileURL = URL(fileURLWithPath: result.path)
        let idmlURL = fileURL.deletingPathExtension().appendingPathExtension("idml")
        let isSkipped = result.success && result.error != nil

        Button {
            let target = (result.success && !isSkipped) ? idmlURL : fileURL
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } label: {
            HStack(spacing: 5) {
                resultIcon(isSkipped: isSkipped)
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(result.success ? Color.primary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !result.success, let err = result.error {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 140, alignment: .trailing)
                }
                Image(systemName: "arrow.right.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
    }

    @ViewBuilder
    private func resultIcon(isSkipped: Bool) -> some View {
        if result.success {
            if isSkipped {
                Image(systemName: "forward.circle").foregroundStyle(Color.secondary).font(.caption)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green).font(.caption)
            }
        } else {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red).font(.caption)
        }
    }
}

public struct ContentView: View {
    @StateObject private var converter = Converter()
    @State private var foundFiles: [URL] = []
    @State private var sourceRoots: [URL] = []
    @State private var isDragging = false
    @State private var errorMessage: String?
    @State private var scanTask: Task<Void, Never>?
    private let inDesignInstalled = Converter.inDesignInstalled()

    public init() {}

    var successCount: Int { converter.results.filter { $0.success && $0.error == nil }.count }
    var skippedCount: Int { converter.results.filter { $0.success && $0.error != nil }.count }
    var errorCount: Int { converter.results.filter { !$0.success }.count }

    public var body: some View {
        VStack(spacing: 0) {
            // InDesign-Warnung
            if !inDesignInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(String(localized: "warning.no_indesign", bundle: .module))
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(.orange.opacity(0.12))
            }

            VStack(spacing: 28) {
                // Header
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.doc.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue.gradient)
                    Text(String(localized: "app.title", bundle: .module))
                        .font(.title2.bold())
                    Text(String(localized: "app.subtitle", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // Drop-Zone
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isDragging ? .blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    isDragging ? Color.blue : Color.secondary.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 1.5, dash: isDragging ? [] : [6])
                                )
                        )
                        .frame(height: 130)
                        .animation(.easeInOut(duration: 0.15), value: isDragging)

                    VStack(spacing: 10) {
                        Image(systemName: isDragging ? "folder.badge.plus" : "doc.badge.plus")
                            .font(.system(size: 30))
                            .foregroundStyle(isDragging ? .blue : .secondary)
                            .animation(.easeInOut(duration: 0.15), value: isDragging)
                        Text(String(localized: "drop.hint", bundle: .module))
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        HStack(spacing: 8) {
                            Button(String(localized: "drop.button.files", bundle: .module)) { pickFiles() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button(String(localized: "drop.button.folder", bundle: .module)) { pickFolder() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers)
                }
                .disabled(converter.isRunning)

                // Fehlermeldung
                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                }

                // Suchfortschritt
                if converter.isSearching {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(converter.searchCount == 0
                                 ? "Suche läuft …"
                                 : "\(converter.searchCount) .indd \(converter.searchCount == 1 ? "Datei" : "Dateien") gefunden")
                                .font(.callout.bold())
                            Spacer()
                            if converter.scannedBytes > 0 {
                                Text(formatBytes(converter.scannedBytes) + " gescannt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !converter.currentSearchPath.isEmpty {
                            Text(converter.currentSearchPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                // Status-Bereich
                if !foundFiles.isEmpty || converter.isRunning || !converter.results.isEmpty {
                    VStack(spacing: 14) {
                        if converter.results.isEmpty && !converter.isRunning {
                            fileCountBadge
                            // Dateiliste vor der Konvertierung
                            if !foundFiles.isEmpty {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(Array(foundFiles.enumerated()), id: \.offset) { _, url in
                                            Button {
                                                NSWorkspace.shared.activateFileViewerSelecting([url])
                                            } label: {
                                                HStack(spacing: 5) {
                                                    Image(systemName: "doc").font(.caption2).foregroundStyle(.secondary)
                                                    Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.primary)
                                                    Spacer()
                                                    Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                                                        .frame(maxWidth: 130, alignment: .trailing)
                                                }
                                                .padding(.horizontal, 6).padding(.vertical, 2).contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 120)
                                .padding(6)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        if converter.isRunning {
                            VStack(spacing: 8) {
                                ProgressView(value: converter.progress)
                                    .progressViewStyle(.linear)
                                    .tint(.blue)
                                Text(converter.currentFile)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !converter.results.isEmpty && !converter.isRunning {
                            resultsRow
                        }
                    }
                }

                // Aktionsbuttons
                VStack(spacing: 10) {
                    // Scan starten (Roots geladen, noch nicht gescannt)
                    if !sourceRoots.isEmpty && !converter.isSearching && foundFiles.isEmpty && converter.results.isEmpty {
                        Button("Scan starten") { startScan() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }

                    // Scan abbrechen
                    if converter.isSearching {
                        Button("Abbrechen") { cancelScan() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .foregroundStyle(.red)
                    }

                    // Konvertierung starten
                    if !foundFiles.isEmpty && !converter.isRunning && !converter.isSearching && converter.results.isEmpty {
                        HStack(spacing: 10) {
                            Button(String(localized: "button.start", bundle: .module)) {
                                errorMessage = nil
                                Task { await converter.convert(files: foundFiles) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!inDesignInstalled)

                            Button("Neu scannen") { resetToRoots() }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                        }
                    }

                    // Konvertierung abbrechen (falls implementiert) + Reset
                    if !converter.results.isEmpty && !converter.isRunning {
                        Button(String(localized: "button.reset", bundle: .module)) { fullReset() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var fileCountBadge: some View {
        let count = foundFiles.count
        let text = count == 1
            ? String(localized: "status.files.one", bundle: .module)
            : String(format: String(localized: "status.files.many", bundle: .module), count)

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.fill").foregroundStyle(.blue)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.blue.opacity(0.08), in: Capsule())

            // Quellpfade anzeigen
            VStack(alignment: .leading, spacing: 3) {
                ForEach(sourceRoots, id: \.path) { root in
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([root])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: root.hasDirectoryPath ? "folder" : "doc")
                                .font(.caption2)
                            Text(root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var resultsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Label(
                    String(format: String(localized: "status.success", bundle: .module), successCount),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)

                if skippedCount > 0 {
                    Label(
                        String(format: String(localized: "status.skipped", bundle: .module), skippedCount),
                        systemImage: "forward.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                }

                if errorCount > 0 {
                    Label(
                        String(format: String(localized: "status.errors", bundle: .module), errorCount),
                        systemImage: "xmark.circle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }
            .font(.callout.bold())

            // Ergebnisliste: alle Dateien anklickbar
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(converter.results.enumerated()), id: \.offset) { _, r in
                        ResultRow(result: r)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)

            // Im Finder zeigen Button
            if !sourceRoots.isEmpty {
                HStack {
                    ForEach(sourceRoots.prefix(2), id: \.path) { root in
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([root])
                        } label: {
                            Label(String(localized: "button.show_finder", bundle: .module), systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // Einzeldateien wählen — direkt konvertierbar, kein Scan nötig
    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "indd")!]
        if panel.runModal() == .OK {
            setRootsAndFiles(files: panel.urls, roots: panel.urls)
        }
    }

    // Ordner wählen — nur Root merken, Scan muss manuell gestartet werden
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setRootsOnly(roots: [url])
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            var fileRoots: [URL] = []
            var dirRoots: [URL] = []
            for provider in providers {
                guard let data = await withCheckedContinuation({ cont in
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        cont.resume(returning: item as? Data)
                    }
                }), let url = URL(dataRepresentation: data, relativeTo: nil) else { continue }

                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

                if isDir.boolValue {
                    dirRoots.append(url)
                } else if url.pathExtension.lowercased() == "indd" {
                    fileRoots.append(url)
                }
            }

            if !fileRoots.isEmpty && dirRoots.isEmpty {
                // Nur Einzeldateien: direkt laden
                setRootsAndFiles(files: fileRoots, roots: fileRoots)
            } else if !dirRoots.isEmpty {
                // Ordner: nur merken, Scan manuell starten
                setRootsOnly(roots: dirRoots + fileRoots)
            } else {
                errorMessage = "Keine .indd Dateien oder Ordner erkannt."
            }
        }
        return true
    }

    private func setRootsOnly(roots: [URL]) {
        cancelScan()
        sourceRoots = roots
        foundFiles = []
        converter.results = []
        converter.progress = 0
        errorMessage = nil
    }

    private func setRootsAndFiles(files: [URL], roots: [URL]) {
        cancelScan()
        sourceRoots = roots
        foundFiles = files
        converter.results = []
        converter.progress = 0
        errorMessage = nil
    }

    private func startScan() {
        foundFiles = []
        errorMessage = nil
        scanTask = Task {
            var all: [URL] = []
            for root in sourceRoots {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir)
                if isDir.boolValue {
                    let found = await converter.findInddFilesAsync(in: root)
                    all.append(contentsOf: found)
                } else if root.pathExtension.lowercased() == "indd" {
                    all.append(root)
                }
                if Task.isCancelled { return }
            }
            foundFiles = all
            if all.isEmpty { errorMessage = "Keine .indd Dateien gefunden." }
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        converter.isSearching = false
    }

    private func resetToRoots() {
        foundFiles = []
        converter.results = []
        converter.progress = 0
        errorMessage = nil
    }

    private func fullReset() {
        cancelScan()
        sourceRoots = []
        foundFiles = []
        converter.results = []
        converter.progress = 0
        errorMessage = nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 0.1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}
