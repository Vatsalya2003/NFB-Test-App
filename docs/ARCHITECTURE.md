# Architecture

## Overview

NFB Test is a two-layer iOS application: a **map presentation layer** built on MapKit and a **multimodal feedback layer** driven by CoreHaptics and AVAudioEngine. A peer-to-peer network layer synchronizes a moving dot between a Controller device and a Participant device.

---

## Module map

```
┌─────────────────────────────────────────────────────────────────┐
│                          SwiftUI / UIKit Views                  │
│                                                                 │
│  RoleSelectionView                                              │
│       │                                                         │
│       ├── ControllerMapView ──► ControllerCoordinator           │
│       │        (MKMapView + gesture recognizers)                │
│       │                                                         │
│       └── ParticipantMapView ──► ParticipantCoordinator         │
│                (MKMapView + touch detection)                    │
└────────────┬────────────────────────────┬───────────────────────┘
             │                            │
             ▼                            ▼
┌────────────────────┐        ┌──────────────────────────────────┐
│  MultipeerService  │        │         FeedbackManager          │
│                    │        │                                  │
│  Controller:       │        │  provideLandmarkFeedback()       │
│    Advertiser      │        │  provideIntersectionFeedback()   │
│    sendPosition()  │        │  startContinuousSound()          │
│                    │        │  startMovingDotFeedback()        │
│  Participant:      │        │  startRoutePulsing()             │
│    Browser         │        └───────────┬──────────────────────┘
│    receivedPosition│                    │
└────────┬───────────┘         ┌──────────┴──────────┐
         │                     ▼                     ▼
         │           ┌──────────────────┐  ┌──────────────────────┐
         │           │   HapticService  │  │    AudioService /    │
         │           │  (CoreHaptics)   │  │    SpeechService     │
         │           │                  │  │  (AVAudioEngine)     │
         │           │  Patterns:       │  │                      │
         │           │  • Corridor      │  │  • speak()           │
         │           │  • Intersection  │  │  • speakSpatially()  │
         │           │  • Landmark      │  │  • playSpatialFX()   │
         │           │  • MovingDot     │  └──────────────────────┘
         │           │  • Route         │
         │           └──────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────┐
│                  Map Feature Models                    │
│                                                        │
│  MapFeature (protocol)                                 │
│    ├── CorridorFeature   — blue polyline (4 mm)        │
│    ├── IntersectionFeature — orange circle (8 mm dia.) │
│    ├── LandmarkFeature   — red rectangle (6×4 mm)      │
│    └── MovingDotFeature  — indigo arrow (10 mm)        │
│                                                        │
│  MapDataLoader  ── loads GeoJSON, applies 2.6× stretch │
│  CoordinateSnappingService ── snaps dot to polyline    │
└────────────────────────────────────────────────────────┘
```

---

## Data flow: finger touch triggers feedback

This is the core interaction loop on the **Participant** device.

```
1. User places finger on MKMapView
        │
        ▼
2. ParticipantCoordinator (UIGestureRecognizer / touchesBegan)
   • Converts UITouch point → map coordinate
   • Calls hitTest() against all rendered overlays and annotations
        │
        ├── Touched CorridorFeature?
        │       └── FeedbackManager.startContinuousSound()
        │               ├── HapticService.startContinuousVibration()  (0.5 intensity)
        │               └── (no audio for corridors)
        │
        ├── Touched IntersectionFeature?
        │       └── FeedbackManager.startContinuousPulsing()
        │               ├── HapticService.startPulsingVibration()  (0.25 s cycle)
        │               └── AudioService plays system sound 1057 (ding) repeatedly
        │
        ├── Touched LandmarkFeature?
        │       └── FeedbackManager.startLandmarkPulsing()
        │               ├── HapticService.startFastPulsingVibration()  (0.12 s cycle)
        │               └── SpeechService.announceLandmark()
        │                       ├── Condition 1: AudioService.speak("Bathroom, on your left")
        │                       ├── Condition 2: AudioService.speakSpatially("Bathroom", from: left)
        │                       └── Condition 3: AudioService.playSpatialSoundEffect("toilet_flush", from: left)
        │
        ├── Touched MovingDotAnnotation?
        │       └── FeedbackManager.startMovingDotFeedback()
        │               ├── HapticService.startMovingDotFeedback()  (0.18 s pulse + 1.0 sharpness)
        │               └── AudioService plays system sound 1104 (tick) every 0.3 s
        │
        └── Touched nothing
                └── FeedbackManager.stopAllFeedback()

3. User lifts finger (touchesEnded)
        └── FeedbackManager.stopAllFeedback()
                ├── HapticService.stop()
                └── AudioService.stop()
```

**Touch sampling**: Move events are throttled to one log entry per 100 ms. Feedback state changes are applied immediately on every new feature contact.

---

## Moving dot system

The moving dot is the mechanism by which the Controller guides the Participant along a route.

### Components

| Component | File | Role |
|---|---|---|
| `MovingDotAnnotation` | `Model/MovingDotFeature.swift` | `MKAnnotation` subclass whose `coordinate` property is updated live |
| `MovingDotAnnotationView` | `Model/MovingDotFeature.swift` | Renders an indigo arrow; rotates to match route heading |
| `CoordinateSnappingService` | `Model/MovingDotFeature.swift` | Finds the nearest point on the route polyline and computes heading |
| `MultipeerService` | `Services/MultipeerService.swift` | Sends/receives `MovingDotPosition` structs over Multipeer |
| `ControllerCoordinator` | `View/ControllerMapView.swift` | Translates tap/pan gestures into dot positions |
| `ParticipantCoordinator` | `View/ParticipantMapView.swift` | Receives positions, updates annotation, provides feedback |

### End-to-end flow

```
Controller iPhone
─────────────────
User taps or drags on map
        │
        ▼
ControllerCoordinator
  • UITapGestureRecognizer / UIPanGestureRecognizer
  • Converts touch → CLLocationCoordinate2D
  • Calls CoordinateSnappingService.snapToRoute(rawCoord, polyline)
        │
        ▼
CoordinateSnappingService
  • Iterates all polyline segments
  • Projects raw coordinate onto each segment (clamped)
  • Picks the closest projected point
  • Rejects jumps > 0.0015° or > 0.002° (U-route guard)
  • Computes heading between consecutive snapped points
        │
        ▼
MovingDotAnnotation.coordinate updated
        │
        ▼
MultipeerService.sendPosition(MovingDotPosition)
  • Encodes { latitude, longitude, routeId, timestamp } as JSON
  • Sends via MCSession (reliable delivery)

━━━━━━━━━━━━━━━━━━━━━━━━━━ network ━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Participant iPhone
──────────────────
MCSessionDelegate.session(_:didReceive:)
        │
        ▼
MultipeerService publishes receivedPosition (ObservableObject)
        │
        ▼
ParticipantCoordinator (observes receivedPosition)
  • Updates MovingDotAnnotation.coordinate on main thread
  • Rotates MovingDotAnnotationView to new heading
  • If user is currently touching the dot → updates feedback
```

### Jump detection

Large coordinate jumps are rejected to prevent the dot snapping across the map on U-shaped routes:

```swift
// CoordinateSnappingService.snapToRoute()
let latDelta = abs(candidate.latitude  - lastSnapped.latitude)
let lonDelta = abs(candidate.longitude - lastSnapped.longitude)
if latDelta > 0.0015 || lonDelta > 0.002 { return lastSnapped }
```

---

## Controller vs Participant device roles

Both roles use the same codebase and are selected at launch from `RoleSelectionView`.

### Controller

- Starts `MultipeerService` as **advertiser** (MCNearbyServiceAdvertiser)
- Displays `ControllerMapView` with a draggable dot
- No haptic/audio feedback (intended for the researcher operating the session)
- Sends `MovingDotPosition` on every gesture update

### Participant

- Starts `MultipeerService` as **browser** (MCNearbyServiceBrowser)
- Discovers the controller automatically on the local network
- Displays `ParticipantMapView` — full haptic/audio feedback on touch
- Receives `MovingDotPosition` and moves the annotation accordingly
- VoiceOver is enabled to allow assistive-technology use

### Connection states

```
.disconnected → .connecting → .connected(peerName: "iPhone 14 Pro")
```

The UI shows a connection status banner until both devices reach `.connected`.

---

## Feedback services

### HapticService — pattern library

All patterns are implemented with CoreHaptics `CHHapticEngine`. Each pattern runs in a continuous loop until `stop()` is called.

| Pattern | Method | Intensity | Sharpness | Cycle |
|---|---|---|---|---|
| Corridor | `startContinuousVibration()` | 0.5 | 0.3 | continuous |
| Intersection | `startPulsingVibration()` | 0.8 | 0.5 | 0.25 s (0.15 on / 0.10 off) |
| Landmark | `startFastPulsingVibration()` | 0.8 | 0.7 | 0.12 s (0.08 on / 0.04 off) |
| Moving dot | `startMovingDotFeedback()` | 1.0 | 1.0 | 0.18 s (0.06 on) |
| Route | `startVertexFeedback()` | 0.9 | 0.8 | fast (4 pulses/sec) |

Landmark pulsing is intentionally 2× faster than intersection pulsing so users can distinguish them by rhythm alone, without speech.

### AudioService — spatial audio

Built on `AVAudioEngine` with `AVAudioEnvironmentNode` and HRTF rendering.

```
AVAudioPlayerNode (mono source)
        │
        ▼
AVAudioEnvironmentNode   ← position set per landmark side
        │                   left:  AVAudio3DPoint(x: -5, y: 0, z: 0)
        ▼                   right: AVAudio3DPoint(x:  5, y: 0, z: 0)
AVAudioOutputNode           ahead: AVAudio3DPoint(x:  0, y: 0, z:-3)
(device speaker / headphones)
```

Sound effect files (MP3/M4A/FLAC) are loaded from the app bundle at startup:
`toilet_flush`, `stairway`, `conference_room`, `vending_machine`, `door_knock`,
`water_running`, `kitchen`, `elevator`, `birdtweet`, `catmeow`, `dogbark`

### SpeechService — announcement logic

Wraps `AVSpeechSynthesizer` with debouncing: the same landmark announced by the same touch type within 0.5 s is suppressed. An anchor-point touch followed immediately by a direct touch on the same landmark is allowed through (different `touchType` values), so the user receives confirmation when they move onto the landmark.

---

## Map rendering

### Coordinate system

Map data is stored in JSON as `[x, y]` pixel coordinates from a floor-plan image. On load, `MapDataLoader` applies two transforms:

1. **Vertical stretch**: multiply y by `stretchFactor` (2.6) to correct aspect ratio on device screen
2. **Lat/lng conversion**: divide by 100,000 to produce small decimal degrees used as a local coordinate space

```swift
latitude  =  y * stretchFactor / 100_000
longitude =  x            / 100_000
```

MapKit is configured with a fixed region that matches this space. The map tiles are replaced with white tiles (`BlankTileOverlay` + `WhiteTileRenderer`) to produce the blank background.

### Physical dimensions

`PhysicalDimensions.swift` contains a PPI database keyed by device model string. All line widths and circle radii are specified in millimetres and converted to screen points at runtime:

```
points = mm * (PPI / 25.4)
```

| Element | Visual size |
|---|---|
| Corridor polyline | 4 mm wide |
| Intersection circle | 8 mm diameter |
| Landmark rectangle | 6 × 4 mm |
| Moving dot arrow | 10 mm |

### Overlay rendering classes

| Class | Overlay type | Color |
|---|---|---|
| `CorridorRenderer` | `MKPolylineRenderer` | Blue |
| `IntersectionRenderer` | `MKCircleRenderer` | Orange fill, white border |
| `LandmarkRenderer` | `MKPolygonRenderer` | Red fill, dark border |
| `RouteRenderer` | `MKPolylineRenderer` | Green dashed |
| `MovingDotAnnotationView` | `MKAnnotationView` | Indigo arrow |

---

## Data logging

`DataService` writes one CSV row per touch event to a file in the app's Documents directory. The Participant coordinator calls `DataService.logTouch(event:point:feature:condition:)` on every touch-down, sampled touch-move, and touch-up.

```
Time Stamp          Trial Time  Touch Event  Object Type   Touch X  Touch Y  Condition
2025-01-15 14:32:45.123  00:05.3  Touch Down  Bathroom      234.5    456.7    Natural Language
```

Trial time is measured from when the user begins the trial (first touch-down after the start signal) and formatted as `MM:SS.d` (deciseconds).

---

## Key design decisions

| Decision | Rationale |
|---|---|
| Haptic patterns differ in rhythm, not just intensity | Allows identification by touch alone without relying on speech |
| Landmark pulsing is 2× faster than intersection pulsing | Gives each element a distinct "signature" even when audio is off |
| Spatial audio uses mono source + AVAudioEnvironmentNode | HRTF rendering produces convincing left/right/front/back directionality over headphones |
| Route snapping rejects large jumps | Prevents dot teleporting to the wrong side of a U-shaped corridor |
| Debounce in SpeechService (0.5 s, same touch type) | Avoids repeated identical announcements when finger rests on a landmark |
| White tile overlay on MapKit | Hides street map beneath, preserving the custom floor-plan coordinate space |
| 2.6× vertical stretch | Corrects the aspect ratio distortion from the original floor-plan scan |
