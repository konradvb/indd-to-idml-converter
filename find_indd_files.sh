#!/bin/bash
# find_indd_files.sh
#
# Durchsucht ein Verzeichnis rekursiv nach .indd-Dateien
# und speichert die Pfade in einer Textdatei für convert_indd_to_idml.applescript.
#
# Verwendung:
#   ./find_indd_files.sh [Startverzeichnis] [Ausgabedatei]
#
# Beispiel:
#   ./find_indd_files.sh ~/Documents /tmp/indd_files.txt
#
# Standard ohne Argumente: durchsucht den Home-Ordner, Ausgabe nach /tmp/indd_files.txt

START_DIR="${1:-$HOME}"
OUTPUT_FILE="${2:-/tmp/indd_files.txt}"

echo "Suche nach .indd Dateien in: $START_DIR"

find "$START_DIR" -type f -name "*.indd" \
  2>/dev/null \
  | grep -v "\.Trash" \
  | grep -v "Library/Caches" \
  > "$OUTPUT_FILE"

COUNT=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "$COUNT Dateien gefunden -> $OUTPUT_FILE"
