# INDD → IDML Converter

**[Download v1.0](https://github.com/konradvb/indd-to-idml-converter/releases/tag/v1.0)** — macOS App zum Konvertieren von Adobe InDesign (.indd) Dateien in das offene IDML-Format (kompatibel mit Affinity Publisher).

Ordner per Drag & Drop auf die App ziehen → alle .indd Dateien werden automatisch als .idml daneben gespeichert. Erfordert Adobe InDesign.

---

## Project Architecture

```
INDDConverter/
├── INDDConverter.xcworkspace/              # Open this file in Xcode
├── INDDConverter.xcodeproj/                # App shell project
├── INDDConverter/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── INDDConverterApp.swift              # App entry point
│   ├── INDDConverter.entitlements          # App sandbox settings
│   └── INDDConverter.xctestplan            # Test configuration
├── INDDConverterPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/INDDConverterFeature/       # Your feature code
│   └── Tests/INDDConverterFeatureTests/    # Unit tests
└── INDDConverterUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `INDDConverter/` contains minimal app lifecycle code
- **Feature Code**: `INDDConverterPackage/Sources/INDDConverterFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

### App Sandbox
The app is sandboxed by default with basic file access permissions. Modify `INDDConverter.entitlements` to add capabilities as needed.

## Development Notes

### Code Organization
Most development happens in `INDDConverterPackage/Sources/INDDConverterFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `INDDConverterPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "INDDConverterFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `INDDConverterPackage/Tests/INDDConverterFeatureTests/` (Swift Testing framework)
- **UI Tests**: `INDDConverterUITests/` (XCUITest framework)
- **Test Plan**: `INDDConverter.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### App Sandbox & Entitlements
The app is sandboxed by default with basic file access. Edit `INDDConverter/INDDConverter.entitlements` to add capabilities:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<!-- Add other entitlements as needed -->
```

## macOS-Specific Features

### Window Management
Add multiple windows and settings panels:
```swift
@main
struct INDDConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
```

### Asset Management
- **App-Level Assets**: `INDDConverter/Assets.xcassets/` (app icon with multiple sizes, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "INDDConverterFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

## Notes

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted macOS development workflows.