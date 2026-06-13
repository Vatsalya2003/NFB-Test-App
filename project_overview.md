# Project Overview: NFB Test iOS Application

**Project Name:** NFB Test  
**Platform:** iOS (Swift, UIKit + SwiftUI)  
**Institution:** Northeastern University  
**Role:** Research Assistant — iOS Developer  
**Purpose:** Accessibility Research — Indoor Navigation for Visually Impaired Users

---

## 1. What Is This Project?

NFB Test is a research-focused iOS application designed to study how visually impaired individuals can navigate indoor environments using a touchscreen map. Instead of relying on sight, users receive real-time haptic vibrations, spatial audio, and speech feedback based on what part of the map they are touching. A researcher on a separate device controls a moving guidance dot that the participant follows — entirely through touch and sound.

The app supports three distinct study conditions to compare different types of audio feedback and collects detailed touch-event data in CSV format for research analysis.

---

## 2. Core Problem Being Solved

Traditional indoor navigation tools are not accessible to visually impaired users. This app explores:
- Can a tactile touchscreen map replace visual maps for indoor wayfinding?
- Which feedback modality (speech, spatial audio, sound icons) is most effective?
- How do users interact with map elements (corridors, intersections, landmarks) through touch?

---

## 3. Two-Device Architecture

The app runs on two physical iPhones simultaneously, connected peer-to-peer over Wi-Fi/Bluetooth using Apple's MultipeerConnectivity framework — no internet required.

| Device | Role | Who Uses It |
|--------|------|-------------|
| **Controller** | Researcher drags a dot along a route | Experimenter |
| **Participant** | Receives dot position, explores map, gets haptic/audio feedback | Study Participant |

Both devices run the same app binary. Role is selected at launch via `RoleSelectionView`.

---

## 4. App Architecture

### 4.1 Layer Overview

```
┌─────────────────────────────────────────┐
│              SwiftUI Layer              │
│  RouteContentView → RoleSelectionView   │
│  RouteSelectionView → Study Views       │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│           UIKit Map Layer               │
│  MKMapView (MapKit)                     │
│  BlankMapView → ParticipantMapView      │
│              → ControllerMapView        │
│  Coordinator (MKMapViewDelegate)        │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│           Service Layer                 │
│  FeedbackManager (orchestrator)         │
│  ├── HapticService  (CoreHaptics)       │
│  ├── AudioService   (AVAudioEngine)     │
│  ├── SpeechService  (AVSpeechSynth)     │
│  └── DataService    (CSV logging)       │
│  MultipeerService   (P2P networking)    │
└─────────────────────────────────────────┘
```

### 4.2 Launch Flow

```
NFB_TestApp (@main)
  └── RouteContentView
        ├── RoleSelectionView
        │     ├── "Controller" → ControllerMapView
        │     └── "Participant" → RouteSelectionView → ParticipantMapView
        └── FilesListView (CSV log manager)
```

---

## 5. Map Rendering

### 5.1 How the Map Works

The map is NOT a real geographic map. It uses MapKit with fake normalized coordinates (0–10 range) to render a custom floor plan on a plain white background. This tricks MapKit into displaying a schematic indoor map.

**Pipeline:**
1. Read GeoJSON file from app bundle
2. Parse coordinates `[x, y]` and divide by 100,000 → `CLLocationCoordinate2D`
3. Apply **2.6× vertical stretch** around center point to space out features
4. Create typed Swift model objects for each feature
5. Add overlays/annotations to `MKMapView`
6. Replace all map tiles with a white `BlankTileOverlay`

### 5.2 Map Features

| Feature | Visual | Drawn As | Size |
|---------|--------|----------|------|
| **Corridor** | Blue line | `MKPolyline` + `MKPolylineRenderer` | 4mm wide |
| **Intersection** | Orange circle | `MKAnnotation` + custom `UIView` | 8mm diameter |
| **Landmark** | Red rectangle | `MKAnnotation` + custom `UIView` | 6mm × 4mm |
| **Anchor Point** | Purple circle | `MKAnnotation` + custom `UIView` | 8mm diameter |
| **Moving Dot** | Indigo arrow | `MKAnnotation` + custom `UIView` | 10mm |

### 5.3 Coordinate Vertical Stretch

All Y coordinates are stretched 2.6× around the center (y=500) to make the floor plan taller and easier to navigate by touch:

```
stretchedY = 500 + (rawY - 500) × 2.6
```

### 5.4 Touch Hit Detection

When a user touches the map, the coordinator converts the screen point and checks features in priority order:

| Priority | Feature | Detection Method | Radius |
|----------|---------|-----------------|--------|
| 1 (Highest) | Anchor Points | Point-to-point distance | 20pt |
| 2 | Intersections & Landmarks | Point-to-point distance | 25pt |
| 3 (Lowest) | Corridors | Perpendicular distance to line segment | 20–50pt (velocity-aware) |

Corridor detection radius grows with swipe speed (up to +30pt bonus at high velocity) to account for fast-moving fingers.

### 5.5 Physical Dimensions

`PhysicalDimensions.swift` stores the PPI (pixels per inch) for every supported iPhone and iPad model. All feature sizes are specified in millimeters and converted to screen points at runtime — ensuring features are physically the same size on every device.

---

## 6. Multimodal Feedback System

`FeedbackManager` orchestrates all feedback. When a user touches a map element, it triggers the appropriate combination of haptic + audio.

### 6.1 Haptic Patterns (CoreHaptics)

| Feature | Pattern | Intensity | Sharpness | Interval |
|---------|---------|-----------|-----------|---------|
| Corridor | Continuous buzz | 0.5 | 0.3 | Continuous |
| Intersection | Slow pulse | 1.0 | 0.5 | 0.25s |
| Landmark | Fast pulse | 1.0 | 0.7 | 0.12s |
| Moving Dot | Rhythmic pulse + tick | 1.0 | 1.0 | 0.18s |

Each pattern is intentionally distinct so users can identify map elements by vibration rhythm alone — without any sound.

### 6.2 Audio Feedback (AVAudioEngine)

Three study conditions test different audio modalities:

**Condition 1 — Natural Language**
- Speech announces room name + direction
- Example: *"Bathroom, on your left"* (anchor touch) or *"Bathroom"* (direct touch)
- Direction determined by landmark position relative to nearest corridor

**Condition 2 — Spatialized Audio**
- Room name spoken from a 3D direction using HRTF (Head-Related Transfer Function)
- AVAudio3DPoint positions the voice left, right, ahead, or behind
- User perceives sound coming from where the room actually is

**Condition 3 — Auditory Icons**
- Sound effect (e.g., toilet flush, stairway sound) plays from the room's direction
- No speech — purely spatial sound icons

### 6.3 Speech Debouncing

`SpeechService` applies a 0.5-second gate per `(landmark, direction, touchType)` tuple to prevent the same announcement from repeating while the finger stays in place.

### 6.4 Anchor Points vs. Direct Landmark Touch

Each landmark has a corresponding invisible **anchor point** placed on the nearest corridor edge. The distinction matters:

- **Direct touch** on red landmark → announces name only
- **Anchor touch** on purple dot → announces name with directional cue ("on your left")

This gives users a spatial reference for where the room entry is relative to the hallway.

---

## 7. Two-Device Synchronization (MultipeerConnectivity)

`MultipeerService` handles all peer-to-peer communication.

### Flow
```
Controller: Experimenter drags dot
  └── CoordinateSnappingService.snapToRoute()
        └── MultipeerService.sendPosition()  [throttled @ 200ms]
              └── [MCSession over Wi-Fi/Bluetooth]
                    └── Participant: receives MovingDotPosition
                          └── Animates dot (0.15s smooth transition)
                                └── FeedbackManager triggers moving dot feedback
```

### Connection States
- **Disconnected** → browsing/advertising for peers
- **Connecting** → MCSession handshake in progress
- **Connected** → live position sync active

### Snapping Logic
The moving dot is snapped to the nearest point on the defined route polyline. Coordinate jumps greater than 0.002° are rejected to prevent the dot from teleporting across U-shaped corridors.

---

## 8. Data Logging

`DataService` logs every touch interaction to a CSV file stored in the app's Documents directory.

### CSV Format

```
Time Stamp, Trial Time, Touch Event, Object Type, Touch X, Touch Y, Condition
2025-01-15 14:32:45.123, 00:05.3, Touch Down, Bathroom, 234.5, 456.7, Natural Language
2025-01-15 14:32:45.223, 00:05.4, Touch Move, Corridor, 240.1, 460.2, Natural Language
2025-01-15 14:32:45.850, 00:06.1, Touch Up, Corridor, 245.0, 462.0, Natural Language
```

### Logging Rules
- **Touch Down / Touch Up** → always logged
- **Touch Move** → throttled to maximum one entry per 100ms (to limit file size)
- **File Name** → `{Mode}_{Date}_{Time}_vN.csv`
- **Viewing** → Built-in FilesListView screen in the app with share/delete options

---

## 9. Study Conditions & Map Files

Six GeoJSON map files are bundled in the app, one per condition:

| Condition | JSON File | Landmark Feedback |
|-----------|-----------|-------------------|
| Natural Language | `testMap_Condition1.json` | Spoken direction |
| Spatialized Audio | `testMap_Condition2.json` | Directional voice (HRTF) |
| Auditory Icons | `testMap_Condition3.json` | Spatial sound effects |
| Practice — NL | `testMap_practice_Condition1.json` | Simple map, natural language |
| Practice — Spatial | `testMap_practice_Condition2.json` | Simple map, spatialized |
| Practice — Icons | `testMap_practice_Condition3.json` | Simple map, icons |

Participants first complete a practice session to learn the system before the real study condition.

---

## 10. File & Folder Structure

```
NFB Test/
├── NFB Test/
│   ├── NFB_TestApp.swift          # @main entry point
│   ├── PhysicalDimensions.swift       # Device PPI database, mm→points
│   ├── SpeechSynthesizerManager.swift # AVSpeechSynthesizer → audio buffer
│   │
│   ├── Model/
│   │   ├── MapFeature.swift           # Protocol for all map elements
│   │   ├── CorridorFeature.swift      # Blue hallway polylines
│   │   ├── IntersectionFeature.swift  # Orange junction circles
│   │   ├── LandmarkFeature.swift      # Red room rectangles
│   │   ├── MovingDotFeature.swift     # Indigo arrow + snapping logic
│   │   ├── DepartureZone.swift        # Corridor-based speech zones
│   │   └── HapticFeedbackSelection.swift
│   │
│   ├── View/
│   │   ├── BlankMapView.swift         # White map base + gestures
│   │   ├── ParticipantMapView.swift   # Participant device map UI
│   │   ├── ControllerMapView.swift    # Controller/researcher map UI
│   │   ├── Coordinator.swift          # MKMapViewDelegate + hit testing
│   │   ├── RouteSelectionView.swift   # Role + condition selection
│   │   ├── LandmarkStudyView.swift    # Landmark exploration mode
│   │   ├── FilesListView.swift        # CSV log file browser
│   │   ├── ContentView.swift
│   │   ├── NavigationHelper.swift
│   │   └── FeedbackCustomizationTesterView.swift
│   │
│   ├── ViewModel/
│   │   └── MapDataLoader.swift        # GeoJSON loader + vertical stretch
│   │
│   ├── Services/
│   │   ├── MultipeerService.swift     # P2P device sync
│   │   ├── HapticService.swift        # CoreHaptics patterns
│   │   ├── AudioService.swift         # AVAudioEngine + spatial audio
│   │   ├── SpeechService.swift        # Announcement logic + debounce
│   │   └── DataService.swift          # CSV touch event logging
│   │
│   ├── FeedbackManager/
│   │   └── FeedbackManager.swift      # Haptic + audio orchestrator
│   │
│   └── Utilities/
│       └── DataManager.swift          # File I/O, CSV export
│
├── RouteOverlay_POC/                  # Proof-of-concept route overlay
│   ├── Model/RouteFeature.swift
│   ├── View/RouteMapView.swift
│   └── FeedbackManager+Route.swift
│
├── docs/
│   ├── README.md
│   ├── ARCHITECTURE.md
│   ├── FEATURES.md
│   ├── MULTIPEER.md
│   └── ACCESSIBILITY.md
│
└── NFB Test.xcodeproj/
```

---

## 11. Technology Stack

| Technology | Framework | Used For |
|------------|-----------|----------|
| Swift | Language | Entire codebase |
| SwiftUI | UI | Role selection, navigation screens |
| UIKit | UI | Map views, annotation views |
| MapKit | Apple | Floor plan rendering |
| CoreHaptics | Apple | Haptic pattern generation |
| AVFoundation / AVAudioEngine | Apple | Spatial audio playback |
| AVSpeechSynthesizer | Apple | Text-to-speech announcements |
| MultipeerConnectivity | Apple | Two-device real-time sync |
| CoreLocation | Apple | Coordinate data types |
| AudioToolbox | Apple | System sounds (ding, tick) |

**No third-party dependencies.** All frameworks are native Apple SDKs.

---

## 12. Key Technical Decisions

| Decision | Reason |
|----------|--------|
| Fake coordinate space (not real GPS) | Indoor maps have no GPS; MapKit still handles rendering |
| 2.6× vertical stretch | Makes corridors and rooms more spread out and touchable |
| Physical mm sizing (not points) | Ensures features are the same physical size on every device |
| Velocity-aware corridor hit detection | Fast-moving fingers need larger targets to stay on narrow corridors |
| 200ms throttle on position sync | Balances real-time feel with network/battery efficiency |
| 100ms throttle on touch move logging | Prevents CSV file bloat without losing meaningful data |
| 0.5s speech debounce | Prevents the same announcement from triggering repeatedly in one touch |
| Anchor points on corridor edges | Gives users a spatial reference for room direction relative to the hallway |

---

## 13. Supported Devices & Requirements

- **iOS Version:** iOS 18.5+
- **Xcode Version:** 16.0+
- **Physical Device Required:** Yes (haptics and multipeer do not work on Simulator)
- **Two iPhones Required:** One for Controller, one for Participant
- **Network:** Local Wi-Fi or Bluetooth (no internet needed)

---

## 14. Summary

NFB Test is a dual-device iOS research platform that turns an iPhone touchscreen into a tactile indoor map. It combines MapKit floor plan rendering with CoreHaptics vibration patterns, 3D spatial audio, and peer-to-peer device synchronization to create an accessible navigation experience for visually impaired users. All interactions are logged to CSV for research analysis across three study conditions: natural language speech, spatialized audio, and auditory icons.
