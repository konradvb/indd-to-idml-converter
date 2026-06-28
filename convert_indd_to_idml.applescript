-- convert_indd_to_idml.applescript
--
-- Konvertiert alle InDesign-Dateien (.indd) aus einer Textliste
-- zu IDML-Dateien (.idml) und speichert sie im gleichen Ordner.
--
-- Funktioniert auch mit Dateien in geschützten Verzeichnissen:
-- iCloud App-Container (z.B. Scanbot), Dropbox, Google Drive, externe Laufwerke.
-- Die Datei wird dazu kurz auf den Desktop kopiert (InDesign hat dort Schreibrecht),
-- konvertiert, und die .idml danach zurück an den Originalort verschoben.
--
-- Hinweise zum Ergebnis:
-- - Fehlende Schriften: InDesign ersetzt sie durch Platzhalter und exportiert trotzdem.
--   In Affinity Publisher erscheinen gelbe Warnungen, Schriften können dort neu zugewiesen werden.
-- - Verknüpfte Bilder (Links): Nur das Layout wird exportiert, nicht die Bilder selbst.
--   Fehlen die Originaldateien, sind Bildrahmen leer und müssen in Affinity neu verknüpft werden.
--
-- Voraussetzungen:
--   - Adobe InDesign muss installiert sein (getestet mit InDesign 2026)
--   - Eine Textdatei mit einem .indd-Dateipfad pro Zeile (siehe fileListPath)
--   - Die Dateien müssen lokal auf dem Mac verfügbar sein (nicht nur Cloud-Platzhalter)
--
-- Anpassung: Passe die Pfad-Variablen unten an dein System an.

set fileListPath to "/tmp/indd_files.txt"
set logPath to "/tmp/indd_to_idml_log.txt"
set tempIndd to "/Users/" & (system attribute "USER") & "/Desktop/indd_convert_work.indd"
set tempIdml to "/Users/" & (system attribute "USER") & "/Desktop/indd_convert_work.idml"

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
				set idmlPath to (text 1 thru -5 of inddPath) & "idml"

				try
					with timeout of 300 seconds
						-- Datei auf Desktop kopieren (InDesign hat dort sicheren Schreibzugriff,
						-- auch wenn die Quelldatei in einem anderen App-Container liegt)
						do shell script "cp " & quoted form of inddPath & " " & quoted form of tempIndd

						set theAlias to POSIX file tempIndd as alias
						set theDoc to open theAlias

						tell theDoc
							export format InDesign Markup to tempIdml without showing options
						end tell

						close theDoc saving no

						-- .idml zurück an Originalort verschieben
						do shell script "mv " & quoted form of tempIdml & " " & quoted form of idmlPath

						-- Temporäre Kopie aufräumen
						do shell script "rm -f " & quoted form of tempIndd
					end timeout

					set successCount to successCount + 1

					set logHandle to open for access POSIX file logPath with write permission
					write ("OK: " & inddPath & return) to logHandle starting at eof
					close access logHandle

				on error errMsg
					set errorCount to errorCount + 1
					do shell script "rm -f " & quoted form of tempIndd & " " & quoted form of tempIdml
					set logHandle to open for access POSIX file logPath with write permission
					write ("FEHLER: " & inddPath & " -- " & errMsg & return) to logHandle starting at eof
					close access logHandle
				end try
			end if
		end repeat

		set userInteractionLevel to interact with all
	end tell
end timeout

set logHandle to open for access POSIX file logPath with write permission
write ("---" & return & "Ergebnis: " & successCount & " erfolgreich, " & errorCount & " Fehler von " & totalCount & " Dateien" & return) to logHandle starting at eof
close access logHandle

display dialog "Konvertierung abgeschlossen!" & return & successCount & " erfolgreich" & return & errorCount & " Fehler" buttons {"OK"} default button "OK"
