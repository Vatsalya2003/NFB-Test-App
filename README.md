# NFB Test

iOS app for **tactile indoor navigation research** at Northeastern. Users explore a touch map of streets and get haptic + speech feedback. Includes two Austin hotel walking routes and dev tools to design maps.

---

## What it does

- Shows a **schematic street map** (blue roads, red intersections, purple landmark boxes)
- Draws a **cyan route** between JW Marriott and Austin Marriott Downtown
- **Yellow dots** mark route start ("Your location") and end ("Destination")
- **Touch feedback**: vibration + spoken street/landmark names while exploring
- **Map Designer** tool to draw roads on a grid and export JSON
- **Fixed viewport** — same zoom on every phone (matches Indoor_Route setup)

---

## Requirements

| Item | Version |
|------|---------|
| Xcode | 16+ |
| iOS | 18.5+ |
| Device | Physical iPhone recommended (CoreHaptics) |

**Dependency:** [SenseKit](https://github.com/arnavvaryani/SenseKit.git) via Swift Package Manager (auto-resolves on open).

---

## Quick start

```bash
git clone <repo-url>
cd "NFB Test"
open "NFB Test.xcodeproj"
```

1. Select your **iPhone** as run destination
2. **Cmd+R** to build and run
3. On home screen, pick a route or open **Tools**

---

## App screens

| Screen | Purpose |
|--------|---------|
| **Route Overlay Study** (home) | Choose Marriott → JW or reverse route |
| **Route Study View** | Full-screen tactile map with route overlay (Level 1) |
| **Intersection Detail** | Zoomed-in intersection view with wider roads, sidewalks, crosswalks (Level 2) |
| **Map Designer** | Draw corridors, export `testMap_Condition1.json` |
| **Feedback Tester** | Try haptic patterns on map elements |

---

## Project layout

```
NFB Test/
├── NFB Test/              App entry (NFB_TestApp.swift, Info.plist)
├── RouteOverlay_POC/      Route study views + route model
├── Model/                 Map features + JSON map/route data
├── View/                  MapDesigner, MapUIKitHelpers, Feedback Tester
├── ViewModel/             MapDataLoader (JSON → features)
├── Services/              HapticService, AudioService, SpeechService
├── FeedbackManager/       Coordinates haptics + speech
├── PhysicalDimensions.swift
└── docs/DEVELOPER_GUIDE.md   ← full file-by-file reference
```

See **[docs/DEVELOPER_GUIDE.md](docs/DEVELOPER_GUIDE.md)** for detailed documentation of every file, coordinate system, and how to edit maps/routes.

---

## Map data files

| File | Contents |
|------|----------|
| `Model/testMap_Condition1.json` | Base map: E 1st/E 2nd St grid, Brazos, San Jacinto, Trinity, landmarks |
| `Model/route_marriott_to_jwmarriott.json` | Marriott → JW Marriott route |
| `Model/route_jwmarriott_to_marriott.json` | JW Marriott → Marriott route |
| `Model/intersection_i_*_detail.json` | Level 2 intersection detail data (6 files, one per intersection) |

---

## Map styling

| Element | Color | Size |
|---------|-------|------|
| Roads | Blue `#023e8a` | 4 mm |
| Intersections | Red `#c1121f` | 5 mm square |
| Route | Cyan `#48cae4` | 3.5 mm |
| Landmarks | Purple `#7b2cbf` box + tag | 9×6 mm, 2 mm from road |
| Start / end | Yellow dot | 4 mm |
| Sidewalks (Level 2) | Gray `#9e9e9e` | 4 mm |
| Crosswalks (Level 2) | White dashed | 2 mm |
| Roads (Level 2) | Blue `#023e8a` | 12 mm |

---

## Touch gestures (on map)

- **Tap** — haptic + speak feature name
- **Long press / drag** — continuous feedback while exploring
- **Double tap on intersection** — zoom into Level 2 intersection detail view
- **3-finger swipe right** — go back

---

## Editing the map

**On device:** Tools → Map Designer → draw → Export JSON → paste into `testMap_Condition1.json`

**In code:** Edit JSON coordinates (0–1000 grid). Rebuild app.

Coordinate pipeline: JSON → 2.6× Y stretch → Y flip → MapKit. See Developer Guide for details.

---

## License / research

Northeastern University accessibility research project. Not App Store production code.
