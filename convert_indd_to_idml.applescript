-- convert_indd_to_idml.applescript
--
-- Konvertiert alle InDesign-Dateien (.indd) aus einer Textliste
-- zu IDML-Dateien (.idml) und speichert sie im gleichen Ordner.
--
-- Voraussetzungen:
--   - Adobe InDesign muss installiert sein
--   - Eine Textdatei mit einer .indd-Dateipfad pro Zeile (siehe file_list_path)
--
-- Anpassung: Passe die beiden Pfad-Variablen unten an dein System an.

-- Pfad zur Textdatei mit allen .indd Dateipfaden (eine Datei pro Zeile)
set fileListPath to "/tmp/indd_files.txt"

-- Pfad zur Log-Ausgabedatei
set logPath to "/tmp/indd_to_idml_log.txt"

-- === Ab hier nichts ändern ===

set fileListHandle to open for access POSIX file fileListPath
set fileListContent to read fileListHandle
close access fileListHandle

set logHandle to open for access POSIX file logPath with write permission
set eof of logHandle to 0
close access logHandle

set fileList to paragraphs of fileListContent
set successCount to 0
set errorCount to 0
set totalCount to count of fileList

with timeout of 7200 seconds
	tell application "Adobe InDesign 2026"
		set userInteractionLevel to never interact

		repeat with i from 1 to totalCount
			set inddPath to item i of fileList
			if inddPath is not "" then
				-- .idml Zielpfad: gleicher Ordner, gleicher Name, andere Endung
				set idmlPath to (text 1 thru -5 of inddPath) & "idml"

				try
					with timeout of 300 seconds
						set theAlias to POSIX file inddPath as alias
						set theDoc to open theAlias

						tell theDoc
							export format InDesign Markup to idmlPath without showing options
						end tell

						close theDoc saving no
					end timeout

					set successCount to successCount + 1

					set logHandle to open for access POSIX file logPath with write permission
					write ("OK: " & inddPath & return) to logHandle starting at eof
					close access logHandle

				on error errMsg
					set errorCount to errorCount + 1
					set logHandle to open for access POSIX file logPath with write permission
					write ("FEHLER: " & inddPath & " -- " & errMsg & return) to logHandle starting at eof
					close access logHandle
				end try
			end if
		end repeat

		set userInteractionLevel to interact with all
	end tell
end timeout

-- Zusammenfassung ans Log anhängen
set logHandle to open for access POSIX file logPath with write permission
write ("---" & return & "Ergebnis: " & successCount & " erfolgreich, " & errorCount & " Fehler von " & totalCount & " Dateien" & return) to logHandle starting at eof
close access logHandle

display dialog "Konvertierung abgeschlossen!" & return & successCount & " erfolgreich" & return & errorCount & " Fehler" buttons {"OK"} default button "OK"
