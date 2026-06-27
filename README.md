# indd-to-idml-converter

Automatisiert die Massenkonvertierung von Adobe InDesign-Dateien (`.indd`) in das offene IDML-Format (`.idml`) – ohne manuelles Öffnen jeder Datei. Ziel: vollständige Unabhängigkeit von Adobe-Software, da IDML von Affinity Publisher und anderen Programmen geöffnet werden kann.

## Hintergrund

Adobe InDesign speichert Dateien im proprietären `.indd`-Format, das ausschließlich mit InDesign geöffnet werden kann. Das IDML-Format (InDesign Markup Language) ist dagegen ein offenes XML-basiertes Format, das u.a. von **Affinity Publisher** vollständig unterstützt wird.

Dieses Script automatisiert den Export über InDesigns eigene AppleScript-Schnittstelle: InDesign öffnet jede Datei im Hintergrund, exportiert sie als `.idml` in denselben Ordner und schließt sie wieder. Die Originaldatei (`.indd`) bleibt dabei unberührt.

## Voraussetzungen

- macOS
- Adobe InDesign (getestet mit InDesign 2026)
- Die zu konvertierenden `.indd`-Dateien müssen **lokal auf dem Mac verfügbar** sein (nicht nur in der Cloud – iCloud-, Dropbox- oder Google-Drive-Dateien müssen vorher heruntergeladen werden)

## Dateien

| Datei | Beschreibung |
|-------|-------------|
| `find_indd_files.sh` | Shell-Script zum Erstellen der Dateiliste |
| `convert_indd_to_idml.applescript` | AppleScript für die eigentliche Konvertierung |

## Verwendung

### Schritt 1: Dateiliste erstellen

```bash
chmod +x find_indd_files.sh
./find_indd_files.sh ~/Documents /tmp/indd_files.txt
```

Ohne Argumente wird der gesamte Home-Ordner durchsucht:

```bash
./find_indd_files.sh
```

Die Datei `/tmp/indd_files.txt` enthält danach alle gefundenen `.indd`-Pfade, einen pro Zeile.

### Schritt 2: Pfade im AppleScript anpassen

Öffne `convert_indd_to_idml.applescript` und passe die beiden Variablen oben an:

```applescript
set fileListPath to "/tmp/indd_files.txt"  -- Pfad zur Dateiliste aus Schritt 1
set logPath to "/tmp/indd_to_idml_log.txt" -- Wo das Log gespeichert wird
```

### Schritt 3: Script ausführen

```bash
osascript convert_indd_to_idml.applescript
```

InDesign öffnet sich und verarbeitet alle Dateien automatisch nacheinander. Am Ende erscheint ein Dialog mit der Zusammenfassung.

### Ergebnis prüfen

```bash
# Erfolgreiche Konvertierungen
grep "^OK:" /tmp/indd_to_idml_log.txt

# Fehlgeschlagene Konvertierungen
grep "^FEHLER:" /tmp/indd_to_idml_log.txt

# Zusammenfassung
tail -3 /tmp/indd_to_idml_log.txt
```

## Bekannte Einschränkungen

**Cloud-Dateien:** Dateien, die nur in der Cloud liegen (iCloud, Google Drive, Dropbox) und nicht lokal heruntergeladen sind, schlagen fehl mit dem Fehler `kann nicht in Typ alias umgewandelt werden`. Lösung: Dateien vorher im Finder herunterladen (Rechtsklick → "Jetzt laden").

**Timeout bei großen Dateien:** Sehr große InDesign-Dateien (viele verknüpfte Assets, komplexe Layouts) können den 5-Minuten-Timeout pro Datei überschreiten. In diesem Fall die Datei manuell in InDesign öffnen und über `Datei → Exportieren → InDesign Markup (IDML)` konvertieren.

**InDesign-Version:** Das Script ist auf `Adobe InDesign 2026` eingestellt. Für andere Versionen den App-Namen in `convert_indd_to_idml.applescript` anpassen:

```applescript
tell application "Adobe InDesign 2025"  -- oder die entsprechende Version
```

## Kompatibilität der Zielformate

| Programm | IDML-Unterstützung |
|----------|-------------------|
| Affinity Publisher 2 | Vollständig |
| QuarkXPress | Vollständig |
| Adobe InDesign | Vollständig (natives Format) |
| Scribus | Teilweise (via Plugin) |

## Lizenz

MIT
