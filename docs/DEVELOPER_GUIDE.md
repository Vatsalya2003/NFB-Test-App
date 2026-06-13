# NFB Test — Developer Guide

This guide explains what the app does, how the code is organized, and what each file is for. Written for anyone picking up the project (student / RA / new dev).

---

## What is this app?

**NFB Test** is an iOS research app for **tactile indoor navigation**. Users explore a schematic map by touch and get:

- **Haptic feedback** (vibration patterns) for roads, intersections, landmarks, and routes
- **Speech** (VoiceOver-friendly) for street names, landmarks, and route endpoints
- A **fixed zoom map** so the layout looks the same on every iPhone

The current build focuses on an **Austin downtown grid** with two hotel routes (Marriott ↔ JW Marriott).

There is **no** Controller/Participant two-phone sync in this repo version — that was from an older Indoor_Route design. This app is single-device route study + tools.

---

## How the app starts

```
NFB_TestApp.swift
  └── RouteContentView          (home screen — pick a route or tool)
        ├── RouteStudyView      (full map + navigation study)
        ├── FeedbackCustomizationTesterView   (haptic testing tool)
        └── MapDesignerView     (draw corridors, export JSON)
```

---

## Folder structure

```
NFB Test/
├── NFB Test/                   App entry + Info.plist
├── RouteOverlay_POC/           Main study feature (routes on map)
│   ├── View/                   RouteContentView, RouteStudyView, RouteMapView
│   ├── Model/                  RouteFeature, RouteMapData
│   ├── FeedbackManager/        Route-specific feedback extensions
│   └── Services/               Route-specific haptic extensions
├── Model/                      Map data types + JSON map files
├── View/                       Shared UI (MapDesigner, helpers, tester)
├── ViewModel/                  JSON loading (MapDataLoader)
├── Services/                   Haptics, speech, audio
├── FeedbackManager/            Central feedback orchestrator
├── PhysicalDimensions.swift    mm → screen points (device PPI)
├── SpeechSynthesizerManager.swift   Text-to-speech wrapper
└── docs/                       This guide + README
```

---

## File reference

### App entry

| File | What it does |
|------|----------------|
| `NFB Test/NFB_TestApp.swift` | `@main` — launches `RouteContentView` |
| `NFB Test/Info.plist` | Bundle ID, permissions, app metadata |

### Views (what the user sees)

| File | What it does |
|------|----------------|
| `RouteOverlay_POC/View/RouteContentView.swift` | Home screen: two route buttons + Tools (Feedback Tester, Map Designer) |
| `RouteOverlay_POC/View/RouteStudyView.swift` | Loads base map JSON + route JSON, shows `RouteMapView` |
| `RouteOverlay_POC/View/RouteMapView.swift` | **Main map screen.** MapKit view, touch gestures, hit-testing, renders roads/intersections/landmarks/routes/yellow dots |
| `View/MapDesignerView.swift` | On-device tool to draw corridors on a grid and export `testMap_Condition1.json` to console |
| `View/FeedbackCustomizationTesterView.swift` | Dev tool to try different haptic patterns on map elements |
| `View/MapUIKitHelpers.swift` | Colors, sizes (mm), fixed viewport, tile overlay, fit helpers |

### Model (map data)

| File | What it does |
|------|----------------|
| `Model/MapFeature.swift` | Protocol all map elements implement (`addToMap`, haptics, feedback) |
| `Model/CorridorFeature.swift` | A road segment (blue line). Converts JSON coords → MapKit polyline |
| `Model/IntersectionFeature.swift` | Red square at a junction. `IntersectionAnnotationView` draws it |
| `Model/LandmarkFeature.swift` | Purple tagged box beside a road (e.g. "JW"). Directional speech |
| `RouteOverlay_POC/Model/RouteFeature.swift` | Cyan route line + `RouteEndpointFeature` (yellow start/end dots) |
| `RouteOverlay_POC/Model/RouteMapData.swift` | Loads route JSON files (`route_*.json`) |
| `Model/HapticFeedbackSelection.swift` | Settings model for Feedback Customization Tester |

### ViewModel / loading

| File | What it does |
|------|----------------|
| `ViewModel/MapDataLoader.swift` | Reads `testMap_Condition1.json`, builds corridors/intersections/landmarks, applies 2.6× Y stretch |

### JSON data (bundled in app)

| File | What it does |
|------|----------------|
| `Model/testMap_Condition1.json` | Base map: 5 roads, 6 intersections, 2 landmarks (JW + Marriott) |
| `Model/route_marriott_to_jwmarriott.json` | Route: Marriott → JW Marriott |
| `Model/route_jwmarriott_to_marriott.json` | Route: JW Marriott → Marriott |

### Services & feedback

| File | What it does |
|------|----------------|
| `FeedbackManager/FeedbackManager.swift` | Single place that triggers haptics + speech together |
| `RouteOverlay_POC/FeedbackManager/FeedbackManager+Route.swift` | Extra methods for route pulsing haptics |
| `Services/HapticService.swift` | CoreHaptics: corridor continuous, intersection pulse, landmark fast pulse |
| `RouteOverlay_POC/Services/HapticService+Route.swift` | Route line haptic pattern |
| `Services/AudioService.swift` | Plays sounds + uses SpeechSynthesizerManager |
| `Services/SpeechService.swift` | Landmark announcement logic (natural language / spatial modes) |
| `SpeechSynthesizerManager.swift` | Wraps `AVSpeechSynthesizer` for TTS |

### Utilities

| File | What it does |
|------|----------------|
| `PhysicalDimensions.swift` | Converts millimeters to screen points using device PPI table |

### Tests (Xcode default — not used much yet)

| Folder | What it does |
|--------|----------------|
| `NFB TestTests/` | Unit test target placeholder |
| `NFB TestUITests/` | UI test target placeholder |

---

## Coordinate system (important!)

JSON uses a **0–1000 grid** (designer space):

- `x` = left → right
- `y` = top → down (y=0 is top of map)

Before rendering, the app:

1. **Stretches Y by 2.6×** around center y=500 (`MapDataLoader.stretchFactor`)
2. **Flips Y** for MapKit: `latitude = (1320 - y) / 100000` (`MapFixedViewport.verticalFlipSum`)
3. Uses a **fixed viewport** so zoom never changes per device (`MapFixedViewport.apply`)

The Map Designer preview uses the same stretch + viewport so WYSIWYG matches the live app.

---

## Visual styles (all in mm on screen)

| Element | Color | Size | File |
|---------|-------|------|------|
| Roads | `#023e8a` blue | 4 mm wide | `MapRoadStyle` |
| Intersections | `#c1121f` red | 5 mm square | `MapIntersectionStyle` |
| Route line | `#48cae4` cyan | 3.5 mm wide | `MapRouteStyle` |
| Landmarks | `#7b2cbf` purple box + tag | 9×6 mm box, 2 mm gap from road | `MapLandmarkStyle` |
| Route start/end | Yellow dot | 4 mm | `MapDestinationStyle` |

---

## Touch & feedback flow

`RouteMapView` uses three gestures:

| Gesture | Behavior |
|---------|----------|
| **Single tap** | Pulse + speak name of what was tapped |
| **Long press / drag** | Continuous haptic while finger moves; speaks when entering a new feature |
| **Double tap** | Pulse only (intersection zoom — planned, not built yet) |
| **3-finger swipe right** | Go back (in RouteStudyView) |

**Hit-test priority:** route endpoint (yellow) → landmark → intersection → corridor

**Haptic patterns:**

- Corridor = continuous vibration
- Intersection = slow pulse + ding
- Landmark / route endpoint = fast pulse + speech
- Route line = route-specific pulsing (when on route overlay)

---

## How to edit the map

### Option A — Map Designer (on device)

1. Run app → **Tools → Map Designer**
2. Tap to place points, double-tap to finish a corridor
3. Tap **Export JSON** → copy from Xcode console into `Model/testMap_Condition1.json`

### Option B — Edit JSON directly

Edit `Model/testMap_Condition1.json` in Xcode. Rebuild. Coordinates are `[x, y]` in 0–1000 space.

### Routes

Edit `Model/route_*.json`. Each route has:

- `geometry.coordinates` — path points `[x, y]`
- `properties.departure` — yellow dot at start + "Your location: …"
- `properties.destination` — yellow dot at end + "Destination: …"

---

## Dependencies

- **SenseKit** (Swift Package) — shared haptic helpers from research repo
- **MapKit** — map rendering (blank tiles, polylines, annotations)
- **CoreHaptics** — vibration patterns
- **AVFoundation** — speech and audio

---

## Common tasks

| Task | Where to look |
|------|----------------|
| Change road color/width | `View/MapUIKitHelpers.swift` → `MapRoadStyle` |
| Change intersection size | `MapIntersectionStyle.sideMM` |
| Add a new road | `testMap_Condition1.json` or Map Designer |
| Add a new route button | `RouteContentView.swift` + new route JSON |
| Change speech text | JSON `announcement` on landmarks, or `RouteEndpointFeature.announcement` |
| Fix map not fitting screen | `MapFixedViewport` southwest/northeast coords |
| Debug coordinate mismatch | Compare Map Designer preview vs `MapDataLoader` stretch factor (must both be 2.6) |

---

## Planned (not implemented yet)

- **Intersection zoom on double-tap** — 8 mm red square + white zebra crosswalk arms + different haptics (see conversation plan)

---

## Build & run

1. Open `NFB Test.xcodeproj` in Xcode 16+
2. Select a **physical iPhone** (simulator has limited haptics)
3. Cmd+R to run
4. iOS deployment target: 18.5

---

## Questions?

If something breaks after editing JSON, check:

1. JSON is valid (commas, brackets)
2. File is listed in Xcode project **Copy Bundle Resources**
3. Route coordinates match road coordinates after stretch
4. Rebuild clean (Shift+Cmd+K) if JSON changes don't show up
