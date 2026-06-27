import SwiftUI
import AppKit

public struct ContentView: View {
    @StateObject private var converter = Converter()
    @State private var foundFiles: [URL] = []
    @State private var isDragging = false
    private let inDesignInstalled = Converter.inDesignInstalled()

    public init() {}

    var successCount: Int { converter.results.filter(\.success).count }
    var errorCount: Int { converter.results.filter { !$0.success }.count }

    public var body: some View {
        VStack(spacing: 0) {
            if !inDesignInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Adobe InDesign nicht gefunden – bitte installieren.")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color.yellow.opacity(0.15))
            }

            VStack(spacing: 24) {
                Text("INDD → IDML Converter")
                    .font(.title2.bold())

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isDragging ? Color.accentColor : Color.secondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 2, dash: [6])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isDragging ? Color.accentColor.opacity(0.08) : Color.clear)
                        )
                        .frame(height: 140)

                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Ordner hierher ziehen")
                            .foregroundColor(.secondary)
                        Button("Ordner wählen") { pickFolder() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers)
                }
                .disabled(converter.isRunning)

                if !foundFiles.isEmpty || converter.isRunning || !converter.results.isEmpty {
                    VStack(spacing: 12) {
                        if converter.results.isEmpty && !converter.isRunning {
                            Text("\(foundFiles.count) .indd \(foundFiles.count == 1 ? "Datei" : "Dateien") gefunden")
                                .foregroundColor(.secondary)
                        }

                        if converter.isRunning {
                            VStack(spacing: 6) {
                                ProgressView(value: converter.progress)
                                Text(converter.currentFile)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        if !converter.results.isEmpty && !converter.isRunning {
                            HStack(spacing: 16) {
                                Label("\(successCount) erfolgreich", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                if errorCount > 0 {
                                    Label("\(errorCount) Fehler", systemImage: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .font(.callout.bold())
                        }
                    }
                }

                if !foundFiles.isEmpty && !converter.isRunning && converter.results.isEmpty {
                    Button("Konvertieren starten") {
                        Task { await converter.convert(files: foundFiles) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!inDesignInstalled)
                }

                if !converter.results.isEmpty && !converter.isRunning {
                    Button("Neuer Ordner") {
                        foundFiles = []
                        converter.results = []
                        converter.progress = 0
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .frame(width: 420)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Ordner wählen"
        if panel.runModal() == .OK, let url = panel.url {
            loadFiles(from: url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { self.loadFiles(from: url) }
        }
        return true
    }

    private func loadFiles(from url: URL) {
        foundFiles = converter.findInddFiles(in: url)
        converter.results = []
        converter.progress = 0
    }
}
