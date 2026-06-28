# INDD → IDML Converter

Konvertiert Adobe InDesign-Dateien (`.indd`) in das offene IDML-Format (`.idml`) — damit du deine Dateien in **Affinity Publisher**, QuarkXPress oder anderen Programmen öffnen kannst, ohne auf Adobe angewiesen zu sein.

## Download

**[INDD-IDML-Converter-v1.0.zip](https://github.com/konradvb/indd-to-idml-converter/releases/tag/v1.0)** — macOS App, ca. 100 KB

## Was die App macht

- Ordner per Drag & Drop oder Ordner-Auswahl-Button hinzufügen
- Alle `.indd` Dateien im Ordner werden automatisch gefunden
- Per Klick auf „Konvertieren starten" wird jede Datei als `.idml` daneben gespeichert
- Fortschrittsbalken und Ergebnisanzeige (erfolgreich / Fehler)
- Die Originaldateien (`.indd`) bleiben unberührt

## Voraussetzungen

- macOS 13 oder neuer
- **Adobe InDesign muss installiert sein** — die App steuert InDesign im Hintergrund automatisch. InDesign öffnet jede Datei, exportiert sie als IDML und schließt sie wieder.

## Installation

1. ZIP herunterladen und entpacken
2. `INDDConverter.app` in den Programme-Ordner ziehen (optional)
3. **Beim ersten Start:** Rechtsklick auf die App → „Öffnen" → Im Dialog „Öffnen" bestätigen

Der Rechtsklick-Schritt ist einmalig nötig, weil die App kein Apple-Zertifikat hat. Danach startet sie normal per Doppelklick.

## Verwendung

1. App starten
2. Einen Ordner mit `.indd` Dateien auf die Drop-Zone ziehen — oder „Ordner wählen" klicken
3. Die Anzahl gefundener Dateien wird angezeigt
4. „Konvertieren starten" klicken
5. Die `.idml` Dateien liegen danach im gleichen Ordner wie die Originale

## Bekannte Einschränkungen

**Fehlende Schriften:** InDesign exportiert trotzdem, ersetzt fehlende Schriften durch Platzhalter. In Affinity Publisher erscheinen gelbe Warnungen — Schriften können dort neu zugewiesen werden.

**Verknüpfte Bilder:** IDML enthält nur das Layout, nicht die Bilder selbst. Wenn die verlinkten Bilddateien nicht mehr am selben Ort liegen, sind Bildrahmen in Affinity leer und müssen neu verknüpft werden.

**Cloud-Dateien:** Dateien die sich in gesperrten App-Containern befinden (z.B. Scanbot iCloud) können nicht direkt kopiert werden. Diese Dateien zuerst in einen normalen Ordner verschieben.

## Für Entwickler

Das Projekt ist eine native macOS SwiftUI App, aufgebaut mit einem Workspace + Swift Package Manager:

```
INDDConverter.xcworkspace      ← In Xcode öffnen
INDDConverter/                 ← App-Shell (Entry Point, Assets)
INDDConverterPackage/
  Sources/INDDConverterFeature/
    ContentView.swift           ← UI
    Converter.swift             ← AppleScript-Logik
convert_indd_to_idml.applescript  ← Standalone Script (kein Xcode nötig)
find_indd_files.sh                ← Hilfsskript für die Dateiliste
```

### Standalone Script (ohne App)

Alternativ zur App können die AppleScript- und Shell-Dateien direkt verwendet werden:

```bash
# 1. Alle .indd Dateien im Home-Ordner finden
./find_indd_files.sh ~/Documents /tmp/indd_files.txt

# 2. Konvertierung starten (InDesign muss installiert sein)
osascript convert_indd_to_idml.applescript
```

Die Pfade in `convert_indd_to_idml.applescript` oben anpassen (`fileListPath` und `logPath`).

### Projekt bauen

```bash
# In Xcode öffnen
open INDDConverter.xcworkspace

# Oder per Terminal
xcodebuild -workspace INDDConverter.xcworkspace -scheme INDDConverter -configuration Release build
```

## Lizenz

MIT
