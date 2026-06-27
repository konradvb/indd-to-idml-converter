# INDD → IDML Converter – macOS App Design

**Datum:** 2026-06-27
**Status:** Genehmigt

## Ziel

Eine schlanke native macOS App (.app), die Adobe InDesign-Dateien (.indd) per Drag & Drop oder Ordnerauswahl in das offene IDML-Format konvertiert. Verteilung als ZIP-Download über GitHub Releases — kein Code-Signing, kein Apple Developer Account nötig.

## Architektur

Drei Dateien, kein externes Framework:

| Datei | Verantwortung |
|-------|--------------|
| `App.swift` | SwiftUI-Einstiegspunkt, App-Lebenszyklus |
| `ContentView.swift` | Gesamte UI (Drag & Drop, Fortschritt, Ergebnis) |
| `Converter.swift` | AppleScript-Ausführung, Datei-Iteration, Ergebnis-Rückgabe |

## UI

Eine einzige Ansicht mit drei Zuständen:

**Zustand 1 — Leer:**
- Drop-Zone mit Text „Ordner hierher ziehen" + Button „Ordner wählen"
- InDesign-Warnung oben wenn nicht installiert

**Zustand 2 — Bereit:**
- Gefundene Dateianzahl (`23 .indd Dateien gefunden`)
- Button „Konvertieren starten"

**Zustand 3 — Laufend / Fertig:**
- Fortschrittsbalken mit `14/23`
- Ergebniszeile: `✓ 14 erfolgreich  ✗ 2 Fehler`

## Konvertierungslogik

`Converter.swift` ruft denselben AppleScript-Ansatz wie das bestehende Script auf:
- Datei auf Desktop kopieren (umgeht iCloud App-Container-Sandbox)
- InDesign öffnet die Kopie, exportiert als IDML
- IDML zurück an Originalort verschieben, Kopie löschen
- Fehler pro Datei abfangen, weiter mit nächster Datei

## InDesign-Erkennung

Beim App-Start prüfen ob `/Applications/Adobe InDesign*` existiert. Falls nicht: gelbes Banner mit Text „Adobe InDesign nicht gefunden – bitte installieren."

## Verteilung

- Xcode baut die `.app`
- `.app` in ZIP packen: `zip -r INDD-IDML-Converter.zip INDD\ IDML\ Converter.app`
- Als GitHub Release hochladen
- Nutzer: Rechtsklick → Öffnen beim ersten Start (Gatekeeper-Bypass ohne Notarisierung)

## Was die App nicht tut

- Kein Code-Signing / Notarisierung
- Keine Einzel-Datei-Auswahl (immer Ordner)
- Keine Vorschau der gefundenen Dateien (nur Anzahl)
- Kein Dark/Light-Mode-Toggle (folgt System)
