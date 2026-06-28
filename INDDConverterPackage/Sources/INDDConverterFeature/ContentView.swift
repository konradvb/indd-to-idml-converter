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
                        Image(systemName: isDragging ? "folder.badge.plus" : "folder")
                            .font(.system(size: 30))
                            .foregroundStyle(isDragging ? .blue : .secondary)
                            .animation(.easeInOut(duration: 0.15), value: isDragging)
                        Text(String(localized: "drop.hint", bundle: .module))
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Button(String(localized: "drop.button", bundle: .module)) { pickFolder() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers)
                }
                .disabled(converter.isRunning)

                // Status-Bereich
                if !foundFiles.isEmpty || converter.isRunning || !converter.results.isEmpty {
                    VStack(spacing: 14) {
                        if converter.results.isEmpty && !converter.isRunning {
                            fileCountBadge
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
                    if !foundFiles.isEmpty && !converter.isRunning && converter.results.isEmpty {
                        Button(String(localized: "button.start", bundle: .module)) {
                            Task { await converter.convert(files: foundFiles) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!inDesignInstalled)
                    }

                    if !converter.results.isEmpty && !converter.isRunning {
                        Button(String(localized: "button.reset", bundle: .module)) {
                            foundFiles = []
                            converter.results = []
                            converter.progress = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var fileCountBadge: some View {
        let count = foundFiles.count
        let text = count == 1
            ? String(localized: "status.files.one", bundle: .module)
            : String(format: String(localized: "status.files.many", bundle: .module), count)

        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.blue)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.blue.opacity(0.08), in: Capsule())
    }

    @ViewBuilder
    private var resultsRow: some View {
        HStack(spacing: 16) {
            Label(
                String(format: String(localized: "status.success", bundle: .module), successCount),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)

            if errorCount > 0 {
                Label(
                    String(format: String(localized: "status.errors", bundle: .module), errorCount),
                    systemImage: "xmark.circle.fill"
                )
                .foregroundStyle(.red)
            }
        }
        .font(.callout.bold())
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
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
