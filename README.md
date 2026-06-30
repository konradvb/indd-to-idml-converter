# INDD → IDML Converter

**English** · [Deutsch](README.de.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/konradvb)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub-Sponsor-ea4aaa?logo=github&logoColor=white)](https://github.com/sponsors/konradvb)

Convert Adobe InDesign files (`.indd`) to the open **IDML** format — in bulk, automatically. Open your layouts in **Affinity Publisher**, QuarkXPress and other apps, without staying locked into an Adobe subscription forever.

> **Perfect for the moment before you cancel Adobe.** Point it at a folder (or your whole drive), and it saves every InDesign document as an open `.idml` right next to the original. Your archive stays openable — for good.

<p align="center">
  <img src="docs/screenshots/01_empty.png" width="260" alt="App start — drop zone">
  <img src="docs/screenshots/02_sources.png" width="260" alt="Sources selected, ready to scan">
  <img src="docs/screenshots/03_scanning.png" width="260" alt="Scan running, .indd files found">
</p>

---

## Why convert your files at all?

`.indd` is a **closed, proprietary format**: only Adobe InDesign can open it. The moment you stop paying for Creative Cloud, your own old layouts become unreadable — locked inside a file only Adobe can unlock.

`.idml` is the **open** counterpart. It carries the same layout (pages, text, styles, frames) in a documented, vendor-neutral format that other apps can read:

- **Affinity Publisher** (a one-time purchase, no subscription) imports IDML directly — the most common reason people switch.
- It's your **insurance against lock-in:** once your files are IDML, you can still open them in ten years, no matter what happens to your Adobe plan.
- **You own your work again** — an open format means the files belong to you, not to a subscription.

The catch: doing this by hand means opening every single document in InDesign and clicking *Export* — fine for one file, painful for hundreds. **This app does the whole batch automatically.**

---

## Requirements

- **macOS 13** (Ventura) or newer
- **Adobe InDesign installed.** The app controls InDesign in the background to do the real export — so this is a **migration / archive helper, not an Adobe replacement.** You need InDesign on the machine while you convert; afterwards you can cancel and keep the IDML files.

> **Tip:** A **free Adobe Creative Cloud trial** (7 days) is enough to run the entire conversion. Install InDesign via the trial, convert your whole archive, then cancel — no long-term subscription required.

---

## Download & Install

1. Download the **[latest version here](https://github.com/konradvb/indd-to-idml-converter/releases/latest)** — a `.dmg` disk image.
2. Open the `.dmg` and **drag `INDDConverter` onto the Applications shortcut** in the window.
3. **First launch only:** right-click (or Control-click) the app in Applications → **Open** → confirm in the dialog.

> The right-click step is a one-time thing on the very first launch. After that, a normal double-click works. *(This step disappears once the app is notarized — see [For developers](#for-developers).)*

---

## How to use — step by step

1. **Open the app.**
2. **Add what you want to convert.** Three ways, mix as you like:
   - **Drag & drop** files or folders straight onto the window
   - the **Choose Files** / **Choose Folder** buttons
   - **Search all drives** — finds every `.indd` on everything currently connected (great for a full archive sweep)
3. Click **Start scan.** The app searches and lists every `.indd` it finds. You can watch the list grow live and **cancel** at any time.
4. Click **Start Conversion.** InDesign opens quietly in the background and exports each file as `.idml` — placed right next to the original.
5. **Done.** You see how many files succeeded, were skipped, or failed. Click any entry to reveal it in Finder.

**Two things that keep you safe:**
- Your original `.indd` files are **never modified.**
- Files that already have an `.idml` next to them are **skipped**, so you can re-run a scan anytime without doing double work.

---

## Good to know (limitations)

| Topic | What happens |
|-------|--------------|
| **Missing fonts** | InDesign substitutes them during export. Affinity Publisher flags them in yellow so you can reassign the right fonts there. |
| **Linked images** | IDML stores the *layout*, not the image files. If a linked image has moved from its original path, the frame appears empty in Affinity and needs to be re-linked. |
| **Cloud / locked folders** | Files inside locked app containers (e.g. some iCloud app containers) can't be read directly. Move them into a normal folder first, then convert. |
| **Dialogs** | Missing-link and missing-font prompts are suppressed automatically — the batch runs without you having to click anything. |

---

## Related Tools

### adobe-fonts-revealer

[**adobe-fonts-revealer**](https://github.com/Kalaschnik/adobe-fonts-revealer) scans your InDesign files and reveals every font referenced across your documents — before you convert.

Use it to find out exactly which fonts are embedded or linked in your `.indd` files, so you know which ones you need to install (or source) before opening the converted `.idml` in Affinity Publisher or another app. Especially useful when migrating a large archive, where missing fonts would otherwise only surface one by one as warnings after the fact.

---

## Support this project

This tool is **free and open source**. If it saved you hours of work or a month of Adobe subscription, consider chipping in:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Buy_me_a_coffee-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/konradvb)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub-Sponsor-ea4aaa?logo=github&logoColor=white)](https://github.com/sponsors/konradvb)

---

## For developers

Native macOS **SwiftUI** app, Workspace + Swift Package Manager.

```
INDDConverter.xcworkspace          ← open this in Xcode
INDDConverter/                     ← app shell (entry point, assets, AppIconGlass.icon)
INDDConverterPackage/
  Sources/INDDConverterFeature/
    ContentView.swift              ← UI
    Converter.swift                ← scan + InDesign automation (AppleScript via osascript)
    Resources/{de,en}.lproj/       ← localized strings
Config/                            ← xcconfig build settings + entitlements
notarize.sh                        ← build + sign + notarize for distribution
convert_indd_to_idml.applescript   ← standalone script (no app needed)
find_indd_files.sh                 ← helper to build a file list
```

### Build

```bash
open INDDConverter.xcworkspace
# or
xcodebuild -workspace INDDConverter.xcworkspace -scheme INDDConverter -configuration Release build
```

### Command-line alternative (no app)

```bash
./find_indd_files.sh ~/Documents /tmp/indd_files.txt   # 1. collect .indd paths
osascript convert_indd_to_idml.applescript             # 2. convert (adjust paths at the top of the script)
```

---

## License

[MIT](LICENSE)
