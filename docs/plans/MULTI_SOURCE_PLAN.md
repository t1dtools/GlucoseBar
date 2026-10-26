# Multi-Source Support — Implementation Plan

## Status: Planning complete, implementation not started

---

## Goal

Allow GlucoseBar to follow multiple CGM sources simultaneously, including multiple
instances of the same provider type (e.g. two different Nightscout servers). Each
source gets its own independent menu bar item, popover/overlay, and full settings.

---

## All Decisions Locked

| Topic | Decision |
|---|---|
| Menu bar | Each source gets its own independent `MenuBarExtra` via `ForEach` in `GlucoseBarApp.body` |
| Source identity | User-defined name + SF Symbol picker + tint color (`ColorPicker`) |
| Settings scope | Everything per-source — thresholds, chart window, unit, menu bar layout, AID, credentials |
| AID integration | Per-source; each Nightscout source manages its own AID data independently |
| Chart / popover | Each source has its own fully independent overlay |
| Global settings | None — no `GlobalSettings` object needed |
| Migration | Legacy flat UserDefaults keys migrated to first source's namespaced keys |
| Min source count | Always at least one source (deleting last source resets it, not removes it) |

---

## Architecture

```
SourceManager (@StateObject, app-level)
 └── [SourceState] (stable reference type, one per source)
      ├── SettingsStore (per-source, all UserDefaults keys namespaced by UUID)
      └── Glucose       (per-source, owns provider + 15s timer)

GlucoseBarApp.body:
  ForEach(sourceManager.sources) { source in
    MenuBarExtra {
        MainAppView()
            .environmentObject(source.glucose)
            .environmentObject(source.settings)
            .environmentObject(vs)
            .environmentObject(uc)
    } label: {
        SourceMenuBarLabel()
            .environmentObject(source.glucose)
            .environmentObject(source.settings)
            .environmentObject(uc)
    }
    .menuBarExtraStyle(.window)
  }

  Settings {
    SettingsView()
        .environmentObject(sourceManager)
        .environmentObject(uc)
  }
```

Key property: `SourceState` objects are **reference types** created once and stored
in `SourceManager`. They are not recreated when `ForEach` re-evaluates — so `Glucose`
timer/socket connections survive app state changes.

---

## New Files (5)

### `GlucoseBar/CodableColor.swift`
`Codable` RGBA wrapper around `SwiftUI.Color` / `NSColor`.
- Stored as four `Double` components (red, green, blue, alpha)
- Provides `.color: Color` accessor for use in SwiftUI views
- Used everywhere `iconColor` is stored or read

### `GlucoseBar/SourceConfiguration.swift`
Minimal `Codable` value type used only during migration.
```swift
struct SourceConfiguration: Identifiable, Codable {
    var id: UUID
    var sourceName: String
    var iconSymbol: String      // SF Symbol name, e.g. "person.fill"
    var iconColor: CodableColor
    var providerType: CGMProvider
    var isEnabled: Bool
}
```

### `GlucoseBar/SourceState.swift`
Reference-type wrapper giving each source a stable `Identifiable` identity.
```swift
final class SourceState: ObservableObject, Identifiable {
    let id: UUID
    let settings: SettingsStore   // initialised with this UUID
    let glucose: Glucose          // initialised from settings
}
```

### `GlucoseBar/SourceManager.swift`
App-level coordinator owning the `[SourceState]` list.
- Persists source order as `[UUID]` JSON under UserDefaults key `"sourceIds"`
- `addSource()` / `removeSource(id:)` — removing last source resets it instead of deleting
- `removeSource`: cleans up all `"\(sourceId).*"` UserDefaults keys
- `migrateFromLegacy()`: reads flat legacy keys → writes namespaced keys for first
  source → writes `["newUUID"]` to `"sourceIds"` → sets `"migratedToMultiSource"` flag

### `GlucoseBar/Settings/SymbolPickerView.swift`
Settings sub-view for choosing source icon.
- `LazyVGrid` of curated SF Symbol names (person.fill, heart.fill, figure.walk,
  drop.fill, star.fill, moon.fill, figure.child, pawprint.fill, and more)
- `SwiftUI.ColorPicker` for tint color
- Live preview at menu bar size

---

## Modified Files (8)

### `GlucoseBar/Settings/Settings.swift` — SettingsStore

Changes:
- Add `sourceId: UUID` stored property, set in new `init(sourceId: UUID)` constructor
- Add new per-source identity fields:
  - `sourceName: String` (default: "My CGM")
  - `iconSymbol: String` (default: "person.fill")
  - `iconColor: CodableColor` (default: white)
  - `showSourceIcon: Bool` (default: false)
- All UserDefaults key reads/writes namespaced via private helper:
  ```swift
  private func key(_ base: String) -> String { "\(sourceId.uuidString).\(base)" }
  ```
- Keep `init()` as convenience (generates a new UUID) for migration/previews
- All `defaults.set(...)` and `defaults.xxx(forKey:)` calls use `key("nsURL")` etc.
- Published property names UNCHANGED — all existing views compile without modification

### `GlucoseBar/GlucoseBarApp.swift`

Remove: `@StateObject var g: Glucose`, `@StateObject var s: SettingsStore`
Add: `@StateObject var sourceManager: SourceManager`
Keep: `@StateObject var vs: ViewState`, `@StateObject var uc: UpdateChecker`

Replace the single `MenuBarExtra` block with `ForEach(sourceManager.sources)`.
The label closure logic (Configure / Error / Fetching / Normal) moves to a new
`SourceMenuBarLabel` view that reads from the source's env objects.

### `GlucoseBar/Glucose.swift`

No signature changes. `Glucose(SettingsStore())` still compiles.
Now receives a per-source namespaced `SettingsStore` instead of the global one.
All timer, provider lifecycle, and `getGlucose()` logic unchanged.

### `GlucoseBar/MenuBarItems/GlucoseViewBuilder.swift` — MenuBarView

Add optional icon prefix at the start of `menuStack`:
```swift
if s.showSourceIcon {
    Image(systemName: s.iconSymbol)
        .foregroundStyle(s.iconColor.color)
        .font(.system(size: 22))
        .padding(.horizontal, 4)
}
```
All other `onReceive` chains and `ImageRenderer` logic unchanged.

### `GlucoseBar/MainAppView.swift`

Add source identity header at the top of the normal content branch:
```swift
HStack {
    Image(systemName: s.iconSymbol).foregroundStyle(s.iconColor.color)
    Text(s.sourceName).font(.headline)
    Spacer()
}
.padding(.horizontal).padding(.top, 8)
```
All other logic (NightscoutButton, ZenModeButton, SettingsButton, etc.) unchanged
since they already read from `@EnvironmentObject var s: SettingsStore` which is
now the per-source instance.

### `GlucoseBar/Settings/SettingsView.swift`

Sidebar restructure — from:
> General / CGM / Menu Bar / Chart / AID / About

To:
> Sources (list with +/- and reorder) / Chart / About

When a source is selected, a second navigation level appears:
- **Identity** — name field + SymbolPickerView
- **CGM** — existing CGMSettingsView (no body changes)
- **Menu Bar** — existing MenuBarSettingsView (no body changes)
- **General** — existing GeneralSettingsView, renamed "Thresholds & Display"
- **AID** — existing AidSettingsView (no body changes), shown when applicable

Sub-views receive the selected source's `SettingsStore` + `Glucose` via
`.environmentObject(selectedSource.settings).environmentObject(selectedSource.glucose)`.
`SettingsView` gets `SourceManager` as an env object.

### `GlucoseBar/Settings/CGMSettingsView.swift`

No view body changes. Already calls `g.reset(s)` and `s.save()` — both work
correctly with per-source env objects.

### `GlucoseBar/WelcomeView.swift`

Minor copy update: add a note that additional sources can be added in Settings
after the first source is configured.

---

## Unchanged Files (~25)

All providers (`Providers/`), all widget views (`MenuBarItems/`), all chart views
(`Chart/`), all common utilities (`Common/`), all data model types, and all other
settings sub-views require **zero changes**:

- `GlucoseEntry.swift`, `GlucoseSourceExtraProperties`, `AIDForecasts`
- `Provider.swift` and all subclasses (`Nightscout`, `DexcomShare`, `Simulator`)
- `MenuBarItem.swift`, `MenuBarItemContainer`
- All `CGMProvider`, `GlucoseUnit`, `GlucoseTrend` enums
- `DispatchTimer.swift`, `KeepAliveManager.swift`
- `UpdateChecker.swift`, `NetworkSession.swift`
- `MenuBar/StatusItemManager.swift`
- All `MenuBarItems/Settings/` sub-views
- `GeneralSettingsView.swift`, `AidSettingsView.swift`, `ChartSettingsView.swift`

---

## Implementation Phases

| Phase | Scope | Files created/changed |
|---|---|---|
| 1 | Foundation types | NEW: `CodableColor`, `SourceConfiguration`, `SourceState`, `SourceManager` |
| 2 | SettingsStore namespacing | CHANGE: `Settings.swift` — add `sourceId`, namespace keys, add identity fields |
| 3 | App wiring | CHANGE: `GlucoseBarApp.swift` — ForEach + SourceManager; `Glucose.swift` — verify |
| 4 | Menu bar icon prefix | CHANGE: `GlucoseViewBuilder.swift` |
| 5 | Popover identity header | CHANGE: `MainAppView.swift` |
| 6 | Settings UI redesign | CHANGE: `SettingsView.swift`; NEW: `SymbolPickerView.swift` |
| 7 | Migration + onboarding | CHANGE: `SourceManager` migration logic, `WelcomeView.swift` |

---

## Persistence Model

Source order stored at: `UserDefaults["sourceIds"]` → JSON `[UUID string]`

Per-source settings stored at: `UserDefaults["\(sourceId.uuidString).\(key)"]`
for every key that was previously a flat key (e.g. `"nsURL"` → `"\(id).nsURL"`).

Migration flag: `UserDefaults["migratedToMultiSource"]` → `Bool`

On migration: reads old flat keys, creates a new UUID, writes namespaced keys,
writes `sourceIds = [newUUID]`, sets migration flag. Old flat keys are left
in place for safety and can be pruned in a later release.

---

## Curated SF Symbols for Picker

```
person.fill, person.2.fill, figure.walk, figure.child, figure.child.circle.fill,
heart.fill, heart.circle.fill, drop.fill, drop.circle.fill,
star.fill, moon.fill, sun.max.fill, bolt.fill,
pawprint.fill, leaf.fill, flame.fill, waveform.path.ecg,
cross.case.fill, medical.thermometer.fill, bandage.fill
```

---

## Notes

- `SourceState` is a **class** (reference type) — crucial so `Glucose` instances
  persist across `body` re-evaluations in `GlucoseBarApp`.
- `ForEach` in a `@SceneBuilder` requires `Identifiable` items. `SourceState.id: UUID`
  provides stable identity so SwiftUI does not tear down `MenuBarExtra` windows on
  unrelated state changes.
- The `NSStatusItem`-based `StatusItemManager.swift` remains available as a fallback
  if SwiftUI `ForEach + MenuBarExtra` proves unstable for dynamic count changes.
- Passwords remain in plain `UserDefaults` (no Keychain), consistent with the
  existing codebase approach.
- All internal glucose values remain in mg/dL; unit conversion at display time only.
