-- convert_indd_to_idml.applescript
--
-- Converts all InDesign files (.indd) from a text list
-- to IDML files (.idml), saved in the same folder as the original.
--
-- Works with files in protected directories too:
-- iCloud app containers (e.g. Scanbot), Dropbox, Google Drive, external drives.
-- Each file is temporarily copied to the Desktop (where InDesign has write access),
-- converted there, and the resulting .idml is moved back to the original location.
--
-- Notes on the output:
-- - Missing fonts: InDesign substitutes them with placeholders and still exports.
--   Affinity Publisher shows yellow warnings; fonts can be reassigned there.
-- - Linked images: only the layout is exported, not the image files themselves.
--   If originals are missing, image frames appear empty and must be re-linked in Affinity.
--
-- Requirements:
--   - Adobe InDesign must be installed (tested with InDesign 2026)
--   - A text file with one .indd file path per line (see fileListPath)
--   - Files must be locally available on the Mac (not cloud-only placeholders)
--
-- Customization: adjust the path variables below to match your system.

set fileListPath to "/tmp/indd_files.txt"
set logPath to "/tmp/indd_to_idml_log.txt"
set tempIndd to "/Users/" & (system attribute "USER") & "/Desktop/indd_convert_work.indd"
set tempIdml to "/Users/" & (system attribute "USER") & "/Desktop/indd_convert_work.idml"

-- === Do not edit below this line ===

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
						-- Copy file to Desktop: InDesign has reliable write access there,
						-- even when the source is in another app container.
						do shell script "cp " & quoted form of inddPath & " " & quoted form of tempIndd

						set theAlias to POSIX file tempIndd as alias
						set theDoc to open theAlias

						tell theDoc
							export format InDesign Markup to tempIdml without showing options
						end tell

						close theDoc saving no

						-- Move .idml back to the original location
						do shell script "mv " & quoted form of tempIdml & " " & quoted form of idmlPath

						-- Clean up the temporary copy
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
					write ("ERROR: " & inddPath & " -- " & errMsg & return) to logHandle starting at eof
					close access logHandle
				end try
			end if
		end repeat

		set userInteractionLevel to interact with all
	end tell
end timeout

set logHandle to open for access POSIX file logPath with write permission
write ("---" & return & "Result: " & successCount & " succeeded, " & errorCount & " errors out of " & totalCount & " files" & return) to logHandle starting at eof
close access logHandle

display dialog "Conversion complete!" & return & successCount & " succeeded" & return & errorCount & " errors" buttons {"OK"} default button "OK"
