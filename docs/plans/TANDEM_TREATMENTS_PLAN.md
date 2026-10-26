# Tandem Treatment Data — Implementation Plan

## Goal

Expose historical treatment data from Tandem pump logs in the popover (chart overlays, data panels) and menu bar. Leverage the 1188+ events already fetched from `api/reports/bff/pump-logs`.

---

## Data Sources (Event Codes)

### 1. Bolus History
| Code | Fields | Meaning |
|------|--------|---------|
| 20 | `insulinDelivered`, `insulinRequested`, `iob`, `completionStatus`, `bolusId` | Standard bolus |
| 55 | `bolusSize`, `iob`, `selectedIob` | Bolus snapshot |
| 64 | `carbAmount`, `bolusType`, `bg`, `correctionBolusIncluded`, `iob`, `carbRatio` | Bolus with carbs + BG |
| 65 | `standardPercent`, `duration`, `userOverride`, `selectedIob`, `targetBg` | Extended bolus params |
| 66 | `correctionBolusSize`, `foodBolusSize`, `totalBolusSize` | Bolus breakdown |
| 280 | `deliveredTotal`, `requestedLater`, `requestedNow`, `correction`, `bolusType`, `bolusDeliveryStatus`, `extendedDurationRequested` | Modern bolus delivery |

### 2. Basal History
| Code | Fields | Meaning |
|------|--------|---------|
| 90 | `commandedBasalRate` (÷1000), `featuresBitmask` | CIQ active basal |
| 279 | `commandedRate` (÷1000), `algorithmRate` (÷1000), `profileBasalRate` (÷1000), `commandedRateSource`, `tempRate` | Legacy basal with algorithm detail |

### 3. Pump Mode Timeline
| Code | Fields | Meaning |
|------|--------|---------|
| 229 | `currentUserMode`, `previousUserMode`, `sleepStartedByGui`, `exerciseChoice`, `exerciseTime`, `activeSleepSchedule`, `eatingSoonStoppedByTimer` | Mode transitions |
| 230 | `closedLoopPreferred`, `pumpSuspended`, `cgmAvailable` | Pump state changes |
| 11 | `suspendReason`, `insulinAmount` | Basal suspension |
| 12 | `preResumeState` | Basal resume |

### 4. Alerts/Alarms
| Code | Fields | Meaning |
|------|--------|---------|
| 4, 26 | `alertId`, `faultLocatorData` | Alert events |
| 5, 28 | `alarmId`, `faultLocatorData` | Alarm events |
| 369-371 | `dalertId`, `sensorType` | Dexcom alerts |

### 5. Active Insulin Curve (IOB Decay)
Not directly in pump logs. Must be **modeled** from bolus history:
- Linear decay: `IOB = insulinDelivered × (1 - elapsed / DIA)` where DIA ≈ 3-5 hours
- Exponential decay: `IOB = insulinDelivered × e^(-elapsed / tau)` where tau ≈ DIA / ln(2)
- The pump's own IOB snapshots (available on codes 16, 20, 55, 64) provide ground truth for validation

---

## Architecture

All pump log events are already in memory from `fetchPumpLogs()`. The change is purely in `parsePumpEvents()` — instead of extracting only CGM/IOB/COB/basal/loop, we accumulate all treatment data into structured arrays.

### New Data Types (in `TandemResponseModels.swift` or new file)

```swift
struct TreatmentBolus: Identifiable {
    var id: String              // bolusId
    var date: Date
    var insulinDelivered: Double
    var insulinRequested: Double?
    var carbAmount: Double?     // grams
    var bolusType: String?      // "Correction", "Food", "Extended", etc.
    var bg: Int?                // pre-bolus BG
    var isExtended: Bool
}

struct TreatmentBasal: Identifiable {
    var id: String
    var date: Date
    var commandedRate: Double   // U/hr (÷1000)
    var algorithmRate: Double?
    var profileBasalRate: Double?
    var commandedRateSource: String?
}

struct TreatmentModeChange: Identifiable {
    var id: String
    var date: Date
    var mode: String            // "Sleep", "Exercise", "Normal", "Eating Soon"
    var isSuspension: Bool
    var reason: String?
}

struct TreatmentAlert: Identifiable {
    var id: String
    var date: Date
    var alertId: Int
    var isAlarm: Bool
    var sensorType: String?
}
```

### Modifications

**A. `TandemResponseModels.swift`** — Add the above structs.

**B. `TandemSource.swift` — `parsePumpEvents()`** — Accumulate all four treatment arrays alongside existing CGM/IOB parsing. Set them on new `@Published` properties or a single `@Published var treatments: TreatmentData` struct on `TandemSource`.

**C. `Provider.swift`** — Add `TreatmentData` to `GlucoseSourceExtraProperties` or expose via new published property on `Provider`.

**D. `GraphView.swift`** — Add optional bolus markers (vertical lines or dots on chart), basal rate overlay (secondary Y-axis or area), and mode background tint.

**E. `MainAppView.swift` / new popover panel** — Add a scrollable treatment history panel below the chart or as a tab.

**F. `AidGridView.swift`** — Add "Active Insulin" row showing modeled IOB from bolus decay.

**G. `AidSettingsView.swift`** — Add toggles for each new overlay: "Show Bolus Markers", "Show Basal Overlay", "Show Mode Timeline", "Show Alerts", "Show Active Insulin Curve".

---

## Implementation Phases

| Phase | Scope | Files |
|-------|-------|-------|
| **1** | Bolus History | Parse codes 20/55/64/66/280 → `[TreatmentBolus]`. Add to popover as scrollable list below chart. Chart markers as dots on glucose axis. |
| **2** | ✅ Basal Rate Overlay | Parse codes 90/279 → `[TreatmentBasal]`. Render as stepped line + gradient fill (icicles) at chart top, scaled to 200px. Includes hover indicator and grid value syncing. |
| **3** | Pump Mode Timeline | Parse codes 229/230/11/12 → `[TreatmentModeChange]`. Render as colored background bands (blue=Sleep, orange=Exercise, red=Alarm) behind glucose line. |
| **4** | Alerts Panel | Parse codes 4/5/26/28/369-371 → `[TreatmentAlert]`. Show as collapsible list below chart. |
| **5** | Active Insulin Curve | Model from bolus history + pump IOB snapshots. Render as decay line on chart (blue dashed). |

### Phase Dependencies
- Phase 1 is independent — start here
- Phase 2 is independent (can happen in parallel with 1)
- Phase 3 is independent
- Phase 4 is independent
- Phase 5 depends on Phase 1 (needs bolus history data)

---

## Settings Toggles

Added to `AidSettingsView.swift` chart data section:

```
Chart Data
┌──────────────────────────────────┐
│ Show Forecast             [■]    │
│ Forecast Kind     [Lines ▾]      │
│ Show IOB                  [■]    │
│ Show COB                  [■]    │
│ Show Basal Rate           [■]    │
│ Show Loop Status          [■]    │
│ Show Bolus Markers        [■]    │  ← new
│ Show Basal Overlay        [■]    │  ✅ done
│ Show Mode Timeline        [■]    │  ← new
│ Show Alerts               [■]    │  ← new
│ Show Active Insulin       [■]    │  ← new
└──────────────────────────────────┘
```

Each toggle persists via `SettingsStore` (same pattern as `aidChartShowBasalRate`).

---

## Estimated Complexity

| Phase | Effort | Files |
|-------|--------|-------|
| Bolus History | Medium — mostly parsing + list UI | 4 |
| Basal Overlay | Medium — chart overlay rendering | 3 |
| Mode Timeline | Low — background bands | 3 |
| Alerts Panel | Low — simple list | 3 |
| Active Insulin | High — decay modeling + curve rendering | 3 |

**Total: ~5 phases, ~10 files touched**
