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
            HStack(spacing: 6) {
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
                        .frame(maxWidth: 130, alignment: .trailing)
                }
                Image(systemName: "arrow.right.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .windowBackgroundColor)))
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

    // Vom Nutzer ziehbare Höhen der beiden Felder (Quellen-Box oben, Listen-Bereich unten)
    @State private var sourceBoxHeight: CGFloat = 130
    @State private var listHeight: CGFloat = 200
    @State private var dragStartSource: CGFloat?
    @State private var dragStartList: CGFloat?
    @State private var dividerHover = false

    // Grenzen für die ziehbaren Felder
    private let minSourceH: CGFloat = 60, maxSourceH: CGFloat = 420
    private let minListH: CGFloat = 90, maxListH: CGFloat = 520

    public init() {}

    // Reine Anzeige — KEINE State-Mutation hier (würde sonst Render-Schleife/Beachball auslösen)
    var etaString: String? {
        let remaining = converter.etaSeconds
        guard remaining >= 10 else { return nil }
        if remaining < 90 { return "\(Int((remaining / 10).rounded(.up)) * 10) Sek." }
        if remaining < 3600 { return "\(Int(remaining / 60) + 1) Min." }
        return String(format: "%.0f Std. %d Min.", floor(remaining / 3600), Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60) + 1)
    }

    var successCount: Int { converter.results.filter { $0.success && $0.error == nil }.count }
    var skippedCount: Int { converter.results.filter { $0.success && $0.error != nil }.count }
    var errorCount: Int { converter.results.filter { !$0.success }.count }

    // Zustand der Drop-Zone
    private var dropZoneIsEmpty: Bool {
        sourceRoots.isEmpty && !converter.isSearching
    }

    // Ist unter der Quellen-Box ein Listen-Bereich sichtbar (Suche/Treffer/Ergebnisse)?
    private var hasContentBelow: Bool {
        converter.isSearching
            || (!foundFiles.isEmpty && !converter.isRunning && converter.results.isEmpty)
            || (!converter.results.isEmpty && !converter.isRunning)
    }

    // Ziehbarer Trenner: verschiebt Höhe zwischen Quellen-Box und Listen-Bereich.
    // Klarer Griff (3 Punkte) mit Hover-Hervorhebung — eindeutig als „zum Ziehen" erkennbar.
    private var resizeDivider: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.secondary.opacity(dividerHover ? 0.75 : 0.4))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .background(
            Capsule().fill(dividerHover ? Color.secondary.opacity(0.12) : Color.clear)
        )
        .frame(maxWidth: .infinity)
        .frame(height: 18)
        .contentShape(Rectangle())
        .onHover { inside in
            dividerHover = inside
            if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartSource == nil {
                        dragStartSource = sourceBoxHeight
                        dragStartList = listHeight
                    }
                    guard let s0 = dragStartSource, let l0 = dragStartList else { return }
                    // Delta so begrenzen, dass beide Felder in ihren Grenzen bleiben
                    let lower = max(minSourceH - s0, l0 - maxListH)
                    let upper = min(maxSourceH - s0, l0 - minListH)
                    let d = min(max(value.translation.height, lower), upper)
                    sourceBoxHeight = s0 + d
                    listHeight = l0 - d
                }
                .onEnded { _ in
                    dragStartSource = nil
                    dragStartList = nil
                }
        )
        .help("Ziehen, um die Felder größer/kleiner zu machen")
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !inDesignInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(String(localized: "warning.no_indesign", bundle: .module)).font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10).padding(.horizontal, 16)
                .background(.orange.opacity(0.12))
            }

            VStack(spacing: 20) {
                // Header
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.doc.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.gradient)
                    Text(String(localized: "app.title", bundle: .module)).font(.title2.bold())
                    Text(String(localized: "app.subtitle", bundle: .module))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // Drop-Zone — leer oder mit Inhalt
                // .fileURL + .folder + .directory deckt normale Dateien UND Finder-Seitenleiste ab
                dropZone
                    .onDrop(of: [.fileURL, .folder, .directory], isTargeted: $isDragging) { providers, _ in
                        handleDrop(providers)
                    }
                    .disabled(converter.isRunning)

                // Ziehbarer Trenner zwischen Quellen-Box und Listen-Bereich
                if !dropZoneIsEmpty && hasContentBelow {
                    resizeDivider
                }

                // Fehlermeldung
                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                }

                // Suchfortschritt
                if converter.isSearching { searchProgressView }

                // Gefundene Dateien (nach Scan, vor Konvertierung)
                if !foundFiles.isEmpty && !converter.isRunning && converter.results.isEmpty {
                    foundFilesView
                }

                // Konvertierungs-Fortschritt
                if converter.isRunning {
                    VStack(spacing: 8) {
                        ProgressView(value: converter.progress)
                            .progressViewStyle(.linear).tint(.blue)
                        Text(converter.currentFile)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Ergebnisse
                if !converter.results.isEmpty && !converter.isRunning { resultsView }

                // Aktionsbuttons
                actionButtons
            }
            .padding(20)
        }
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Drop Zone

    @ViewBuilder
    private var dropZone: some View {
        if dropZoneIsEmpty {
            // Leer: klassische Drop-Zone
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDragging ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isDragging ? Color.blue : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 1.5, dash: isDragging ? [] : [6])
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isDragging)

                VStack(spacing: 10) {
                    Image(systemName: isDragging ? "folder.badge.plus" : "doc.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(isDragging ? Color.blue : Color.secondary)
                        .animation(.easeInOut(duration: 0.15), value: isDragging)
                    Text(String(localized: "drop.hint", bundle: .module))
                        .foregroundStyle(.secondary).font(.callout)
                    HStack(spacing: 8) {
                        Button(String(localized: "drop.button.files", bundle: .module)) { pickFiles() }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button(String(localized: "drop.button.folder", bundle: .module)) { pickFolder() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Button {
                        addAllVolumes()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "externaldrive.fill.badge.checkmark")
                            Text("Alle Laufwerke durchsuchen")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            .frame(minHeight: 130)

        } else {
            // Gefüllt: zeigt Roots als Kacheln
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDragging ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isDragging ? Color.blue : Color.blue.opacity(0.25),
                                lineWidth: 1.5
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isDragging)

                VStack(alignment: .leading, spacing: 0) {
                    // Titelzeile
                    HStack(spacing: 8) {
                        Text(sourceRoots.count == 1 ? "1 Quelle ausgewählt" : "\(sourceRoots.count) Quellen ausgewählt")
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        // Weiteres hinzufügen / zurücksetzen — größere, klar tappbare Buttons
                        if !converter.isSearching {
                            HStack(spacing: 4) {
                                Button { pickFiles() } label: {
                                    Image(systemName: "doc.badge.plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 30, height: 26)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless).foregroundStyle(.blue)
                                .help("Dateien hinzufügen")

                                Button { pickFolder() } label: {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 30, height: 26)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless).foregroundStyle(.blue)
                                .help("Ordner hinzufügen")

                                Button { fullReset() } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(width: 30, height: 26)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                                .help("Alle entfernen")
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

                    Divider().padding(.horizontal, 8)

                    // Root-Kacheln
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(sourceRoots, id: \.path) { root in
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([root])
                                } label: {
                                    HStack(spacing: 8) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.blue.opacity(0.12))
                                                .frame(width: 28, height: 28)
                                            Image(systemName: root.hasDirectoryPath ? "folder.fill" : "doc.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.blue)
                                        }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(root.lastPathComponent)
                                                .font(.callout.bold())
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(root.deletingLastPathComponent().path
                                                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.head)
                                        }
                                        Spacer()
                                        if !converter.isSearching {
                                            Button {
                                                sourceRoots.removeAll { $0 == root }
                                                if sourceRoots.isEmpty { fullReset() }
                                            } label: {
                                                Image(systemName: "minus.circle")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    // Höhe: vom Nutzer ziehbar wenn ein Listen-Bereich darunter ist,
                    // sonst adaptiv (wächst bis ~3 Quellen, danach Scroll)
                    .frame(height: hasContentBelow
                           ? sourceBoxHeight
                           : min(CGFloat(sourceRoots.count) * 42 + 8, 138))

                    // Drag-Hinweis unten
                    if isDragging {
                        Divider().padding(.horizontal, 8)
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.blue).font(.caption)
                            Text("Weitere hinzufügen").font(.caption).foregroundStyle(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDragging)
        }
    }

    // MARK: - Suchfortschritt

    @ViewBuilder
    private var searchProgressView: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Status-Zeile
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Suche läuft …").font(.callout.bold())
                    if !converter.currentSearchPath.isEmpty {
                        Text(converter.currentSearchPath)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Abbrechen") { cancelScan() }
                    .buttonStyle(.bordered).controlSize(.small)
            }

            // Fortschrittsbalken (nur wenn Gesamtgröße bekannt)
            if converter.volumeTotalBytes > 0 {
                let progress = min(1.0, Double(converter.scannedBytes) / Double(converter.volumeTotalBytes))
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: progress).progressViewStyle(.linear).tint(.blue)
                    HStack {
                        Text("\(formatBytes(converter.scannedBytes)) von \(formatBytes(converter.volumeTotalBytes))")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        if converter.scanBytesPerSecond > 0 {
                            Text(formatBytes(Int64(converter.scanBytesPerSecond)) + "/s")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let eta = etaString {
                            Text("· noch ca. \(eta)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Bereits gefundene Dateien live anzeigen
            if converter.searchCount > 0 {
                Divider()
                HStack {
                    Image(systemName: "doc.text.fill").foregroundStyle(.blue).font(.caption)
                    Text("\(converter.searchCount) .indd \(converter.searchCount == 1 ? "Datei" : "Dateien") gefunden")
                        .font(.caption.bold()).foregroundStyle(.blue)
                }
                // Live-Liste ALLER gefundenen Dateien — scrollbar schon während der Suche.
                // LazyVStack rendert nur sichtbare Zeilen, daher auch bei tausenden flüssig.
                if !converter.liveFoundFiles.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(converter.liveFoundFiles.enumerated()), id: \.offset) { _, url in
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "doc").font(.caption2).foregroundStyle(.blue)
                                        Text(url.lastPathComponent)
                                            .font(.caption).foregroundStyle(.primary)
                                            .lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: listHeight)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Gefundene Dateien

    @ViewBuilder
    private var foundFilesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            let count = foundFiles.count
            let text = count == 1
                ? String(localized: "status.files.one", bundle: .module)
                : String(format: String(localized: "status.files.many", bundle: .module), count)
            HStack {
                Label(text, systemImage: "doc.fill").font(.callout.bold()).foregroundStyle(.blue)
                Spacer()
                if !sourceRoots.isEmpty {
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting(sourceRoots)
                    }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.blue)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(foundFiles.enumerated()), id: \.offset) { _, url in
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc").font(.caption2).foregroundStyle(.blue)
                                Text(url.lastPathComponent)
                                    .font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.primary)
                                Spacer()
                                Text(url.deletingLastPathComponent().path
                                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.head).frame(maxWidth: 140, alignment: .trailing)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: listHeight)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Ergebnisse

    @ViewBuilder
    private var resultsView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Label(String(format: String(localized: "status.success", bundle: .module), successCount),
                      systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if skippedCount > 0 {
                    Label(String(format: String(localized: "status.skipped", bundle: .module), skippedCount),
                          systemImage: "forward.circle.fill").foregroundStyle(.secondary)
                }
                if errorCount > 0 {
                    Label(String(format: String(localized: "status.errors", bundle: .module), errorCount),
                          systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .font(.callout.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(converter.results.enumerated()), id: \.offset) { _, r in
                        ResultRow(result: r)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: listHeight)

            if !sourceRoots.isEmpty {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(sourceRoots)
                } label: {
                    Label(String(localized: "button.show_finder", bundle: .module), systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Aktionsbuttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 8) {
            if !sourceRoots.isEmpty && !converter.isSearching && foundFiles.isEmpty && converter.results.isEmpty {
                Button("Scan starten") { startScan() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            // Abbrechen-Button ist bereits in searchProgressView — hier nicht nochmal
            if !foundFiles.isEmpty && !converter.isRunning && !converter.isSearching && converter.results.isEmpty {
                HStack(spacing: 10) {
                    Button(String(localized: "button.start", bundle: .module)) {
                        errorMessage = nil
                        Task { await converter.convert(files: foundFiles) }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!inDesignInstalled)

                    Button("Neu scannen") { resetToRoots() }
                        .buttonStyle(.bordered).controlSize(.regular)
                }
            }
            if !converter.results.isEmpty && !converter.isRunning {
                Button(String(localized: "button.reset", bundle: .module)) { fullReset() }
                    .buttonStyle(.bordered).controlSize(.regular)
            }
        }
    }

    // MARK: - Picker & Drop

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "indd")!]
        if panel.runModal() == .OK { addRoots(panel.urls, asFiles: true) }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { addRoots([url], asFiles: false) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            var dirs: [URL] = []; var files: [URL] = []
            for provider in providers {
                // Mehrere UTI-Typen probieren — Finder-Seitenleiste liefert oft public.folder
                let typeIds = ["public.file-url", "public.folder", "public.directory",
                               "com.apple.finder.node"]
                var resolved: URL?
                for typeId in typeIds {
                    if !provider.hasItemConformingToTypeIdentifier(typeId) { continue }
                    if let url = await loadURL(from: provider, typeId: typeId) {
                        resolved = url; break
                    }
                }
                // Fallback: loadFileRepresentation
                if resolved == nil {
                    resolved = await withCheckedContinuation { cont in
                        provider.loadFileRepresentation(forTypeIdentifier: "public.item") { url, _ in
                            cont.resume(returning: url.map { URL(fileURLWithPath: $0.path) })
                        }
                    }
                }
                guard let url = resolved else { continue }
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue { dirs.append(url) }
                else if url.pathExtension.lowercased() == "indd" { files.append(url) }
            }
            let newRoots = dirs + files
            if newRoots.isEmpty { errorMessage = "Keine .indd Dateien oder Ordner erkannt."; return }
            addRoots(newRoots, asFiles: files.isEmpty ? false : dirs.isEmpty)
        }
        return true
    }

    private func addAllVolumes() {
        let fm = FileManager.default
        // Alle gemounteten Volumes
        let mountedVolumes = (fm.mountedVolumeURLs(includingResourceValuesForKeys: [.isVolumeKey, .volumeIsEjectableKey], options: [.skipHiddenVolumes]) ?? [])
        // Root-Laufwerk explizit hinzufügen (wird von mountedVolumeURLs oft nicht gelistet)
        var roots = mountedVolumes
        let mainDisk = URL(fileURLWithPath: "/")
        if !roots.contains(mainDisk) { roots.insert(mainDisk, at: 0) }
        if roots.isEmpty { roots = [URL(fileURLWithPath: "/")] }
        addRoots(roots, asFiles: false)
    }

    private func loadURL(from provider: NSItemProvider, typeId: String) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else if let url = item as? URL {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func addRoots(_ urls: [URL], asFiles: Bool) {
        // Deduplizieren
        let existing = Set(sourceRoots.map(\.path))
        let fresh = urls.filter { !existing.contains($0.path) }
        sourceRoots.append(contentsOf: fresh)
        foundFiles = []
        converter.results = []
        converter.progress = 0
        errorMessage = nil
        // Einzelne .indd Dateien direkt laden
        if asFiles {
            foundFiles = sourceRoots.filter { $0.pathExtension.lowercased() == "indd" }
        }
    }

    private func startScan() {
        foundFiles = []; errorMessage = nil
        scanTask = Task {
            // Einzelne .indd-Dateien direkt übernehmen, Ordner/Volumes gesammelt scannen
            let singleFiles = sourceRoots.filter { $0.pathExtension.lowercased() == "indd" }
            let folders = sourceRoots.filter { url in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return isDir.boolValue
            }
            var all: [URL] = singleFiles
            if !folders.isEmpty {
                all.append(contentsOf: await converter.findInddFilesAsync(in: folders))
            }
            if Task.isCancelled { return }
            foundFiles = all
            if all.isEmpty { errorMessage = "Keine .indd Dateien gefunden." }
        }
    }

    private func cancelScan() {
        converter.cancelScan()      // stoppt den laufenden Hintergrund-Scan
        scanTask?.cancel(); scanTask = nil
        converter.isSearching = false
    }

    private func resetToRoots() {
        foundFiles = []; converter.results = []; converter.progress = 0; errorMessage = nil
    }

    private func fullReset() {
        cancelScan(); sourceRoots = []; foundFiles = []
        converter.results = []; converter.progress = 0; errorMessage = nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 0.1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}
