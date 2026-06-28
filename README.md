# INDD → IDML Converter

Converts Adobe InDesign files (`.indd`) to the open IDML format (`.idml`) — so you can open your designs in **Affinity Publisher**, QuarkXPress, or other applications without depending on Adobe.

Available in English and German, automatically matching your system language.

## Download

**[INDD-IDML-Converter-v1.2.zip](https://github.com/konradvb/indd-to-idml-converter/releases/tag/v1.2)** — macOS App, ~144 KB

## What it does

- Drop a folder onto the app or use the folder picker
- All `.indd` files inside are found automatically (including subfolders)
- Click "Start Conversion" — each file is exported as `.idml` next to the original
- Progress bar shows current file; results show how many succeeded or failed
- Original `.indd` files are never touched

## Requirements

- macOS 13 or later
- **Adobe InDesign must be installed** — the app drives InDesign in the background. InDesign opens each file, exports it as IDML, and closes it again.

## Installation

1. Download and unzip the file
2. Move `INDDConverter.app` to your Applications folder (optional)
3. **First launch only:** Right-click the app → "Open" → confirm in the dialog

The right-click step is a one-time requirement because the app is not notarized. After that, it launches normally with a double-click.

## Known Limitations

**Missing fonts:** InDesign still exports even if fonts are missing, replacing them with substitutes. Affinity Publisher will show yellow warnings — fonts can be reassigned there.

**Linked images:** IDML contains only the layout, not the images themselves. If linked image files are no longer at their original path, image frames will appear empty in Affinity and need to be re-linked.

**Cloud-sandboxed files:** Files inside locked app containers (e.g. Scanbot's iCloud container) cannot be copied directly. Move them to a regular folder first.

## Command-Line Alternative

The included shell script and AppleScript can be used without the app:

```bash
# 1. Find all .indd files in a folder
./find_indd_files.sh ~/Documents /tmp/indd_files.txt

# 2. Run the conversion (InDesign must be installed)
osascript convert_indd_to_idml.applescript
```

Adjust `fileListPath` and `logPath` at the top of the AppleScript to match your setup.

## For Developers

Native macOS SwiftUI app using a Workspace + Swift Package Manager structure:

```
INDDConverter.xcworkspace                         ← Open in Xcode
INDDConverter/                                    ← App shell (entry point, assets)
INDDConverterPackage/
  Sources/INDDConverterFeature/
    ContentView.swift                             ← UI
    Converter.swift                               ← AppleScript logic
    Resources/
      de.lproj/Localizable.strings               ← German strings
      en.lproj/Localizable.strings               ← English strings
convert_indd_to_idml.applescript                  ← Standalone script
find_indd_files.sh                                ← Helper to build file list
```

### Build

```bash
open INDDConverter.xcworkspace
# or
xcodebuild -workspace INDDConverter.xcworkspace -scheme INDDConverter -configuration Release build
```

## License

MIT
