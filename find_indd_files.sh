#!/bin/bash
# find_indd_files.sh
#
# Recursively searches a directory for .indd files
# and saves the paths to a text file for use with convert_indd_to_idml.applescript.
#
# Usage:
#   ./find_indd_files.sh [start-directory] [output-file]
#
# Example:
#   ./find_indd_files.sh ~/Documents /tmp/indd_files.txt
#
# Defaults (no arguments): searches the home folder, output to /tmp/indd_files.txt

START_DIR="${1:-$HOME}"
OUTPUT_FILE="${2:-/tmp/indd_files.txt}"

echo "Searching for .indd files in: $START_DIR"

find "$START_DIR" -type f -name "*.indd" \
  2>/dev/null \
  | grep -v "\.Trash" \
  | grep -v "Library/Caches" \
  > "$OUTPUT_FILE"

COUNT=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "$COUNT files found -> $OUTPUT_FILE"
