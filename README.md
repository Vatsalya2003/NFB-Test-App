# NFB Test

An iOS application for studying touchscreen-based indoor navigation with multimodal feedback. Participants explore a tactile map using touch, receiving haptic vibrations, speech, and spatial audio based on what they are touching (corridors, intersections, landmarks). A separate Controller device drives a moving dot along a route that the Participant follows.

---

## What the app does

- Renders a schematic indoor map on a blank white background using MapKit overlays
- Delivers distinct haptic patterns for each map element type (corridor, intersection, landmark, route, moving dot)
- Announces landmarks via three switchable modalities: natural language speech, spatialized audio, or auditory icons
- Synchronizes a "moving dot" between two iPhones over a local peer-to-peer network (MultipeerConnectivity)
- Logs every touch event to a CSV file for later analysis

## Who it is for

Research participants and study controllers in an indoor navigation accessibility study. Two physical iPhones are required for the full moving-dot protocol. A single device is sufficient for the landmark-exploration conditions.

---

## Prerequisites

| Requirement | Version |
|---|---|
| Xcode | 16.0 or later |
| iOS deployment target | 18.5 |
| Swift | 5.0 |
| Physical iPhone | Required for haptics (simulator does not support CoreHaptics) |
| Apple Developer account | Required for on-device builds and TestFlight |

No third-party Swift packages or CocoaPods are used. The project depends only on system frameworks:
`MapKit`, `CoreHaptics`, `AVFoundation`, `MultipeerConnectivity`, `CoreLocation`

---

## Step-by-step setup

### 1. Clone the repository

```bash
git clone <repo-url>
cd "NFB Test"
```

### 2. Open the project

```bash
open NFB Test.xcodeproj
```

Or double-click `NFB Test.xcodeproj` in Finder.

### 3. Configure signing and provisioning

1. In Xcode, select the `NFB Test` project in the navigator.
2. Select the **NFB Test** target.
3. Open the **Signing & Capabilities** tab.
4. Set **Team** to your Apple Developer account.
5. Change the **Bundle Identifier** if needed (default: `com.vatsalya.NFB-Test`).
6. Repeat for the `NFB TestTests` and `NFB TestUITests` targets if you plan to run tests.

Xcode will automatically manage provisioning profiles when "Automatically manage signing" is checked.

### 4. Required entitlements

The app uses:
- **Local Network** access (MultipeerConnectivity peer-to-peer) — declared in `Info.plist` with `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_indoor-route._tcp`, `_indoor-route._udp`)
- No location permission is needed (the map uses a custom coordinate space, not GPS)

These are already present in `NFB Test/Info.plist`. No additional entitlement files are needed.

### 5. Select a run destination

Connect a physical iPhone. In the Xcode toolbar, select your device from the scheme/destination picker. The app will not provide haptic feedback on a simulator.

### 6. Build and run

Press **Cmd+R** or click the Run button.

On first launch on a real device, iOS may ask you to trust the developer certificate:
- On the device: **Settings → General → VPN & Device Management → [your account] → Trust**

---

## App launch flow

```
Launch → RoleSelectionView
           ├── "Controller" → RouteStudyView (controller mode)
           │                   Drag dot along route, sends position via Multipeer
           └── "Participant" → Route Study (receives dot from controller)
```

Select **Controller** on one iPhone and **Participant** on the other. Both must be on the same Wi-Fi network or have Bluetooth enabled. They will discover each other automatically.

---

## TestFlight distribution

1. In Xcode, set the scheme to **Any iOS Device (arm64)**.
2. **Product → Archive** (Cmd+Shift+K, then Product → Archive).
3. In the Organizer window, select the archive and click **Distribute App**.
4. Choose **TestFlight & App Store**, then follow the upload wizard.
5. In App Store Connect, add internal or external testers to the build.
6. Testers install the app from the TestFlight app on their iPhone.

Note: Both devices used in a two-device session must have the same version installed.

---

## Branch structure

| Branch | Purpose |
|---|---|
| `main` | Stable release baseline |
| `feature/moving-dot-3` | Current development — two-device moving dot sync, arrow annotation, route snapping, jump detection |
| `feature/feedbacks` | Haptic and audio feedback tuning experiments |

Active development happens on `feature/moving-dot-3`. Merge to `main` after session-ready testing on physical devices.

---

## Project layout

```
NFB Test/
├── NFB Test/           # App target source root
│   ├── NFB_TestApp.swift
│   └── Info.plist
├── View/                   # SwiftUI + UIKit bridge views
│   ├── Coordinator.swift       # NavigationStack, role selection, map helpers
│   ├── ControllerMapView.swift # Controller device UI (drag dot)
│   ├── ParticipantMapView.swift# Participant device UI (touch + feedback)
│   ├── RouteSelectionView.swift
│   ├── LandmarkStudyView.swift
│   └── BlankMapView.swift
├── Model/                  # Map features and data
│   ├── MapFeature.swift        # Protocol for all map elements
│   ├── CorridorFeature.swift
│   ├── IntersectionFeature.swift
│   ├── LandmarkFeature.swift
│   ├── MovingDotFeature.swift  # Annotation + snapping logic
│   ├── DepartureZone.swift     # Corridor length announcements
│   └── *.json                  # GeoJSON map data (6 conditions + practice)
├── Services/
│   ├── MultipeerService.swift  # Controller ↔ Participant communication
│   ├── HapticService.swift     # CoreHaptics patterns
│   ├── AudioService.swift      # AVAudioEngine spatial audio
│   ├── SpeechService.swift     # Landmark announcement logic
│   └── DataService.swift       # CSV session logging
├── FeedbackManager/
│   └── FeedbackManager.swift   # Orchestrates haptic + audio together
├── ViewModel/
│   └── MapDataLoader.swift     # GeoJSON loader, coordinate stretching
├── Utilities/
│   └── DataManager.swift       # File I/O, CSV export
├── PhysicalDimensions.swift    # Device PPI table, mm → points conversion
├── SpeechSynthesizerManager.swift
└── RouteOverlay_POC/           # Proof-of-concept for route overlay feature
    └── README_ROUTE_POC.md
```

---

## Study conditions

The app supports six map variants loaded from JSON:

| Constant | File | Landmark feedback |
|---|---|---|
| Condition 1 | `testMap_Condition1.json` | Natural language ("Bathroom, on your left") |
| Condition 2 | `testMap_Condition2.json` | Spatialized speech (directional audio) |
| Condition 3 | `testMap_Condition3.json` | Auditory icons (spatial sound effect) |
| Practice 1–3 | `testMap_practice_Condition*.json` | Same modalities on a simpler map |

Select the condition from `RouteSelectionView` before starting a trial.

---

## Data logging

Each session writes a CSV file to the app's Documents directory:

```
Time Stamp, Trial Time, Touch Event, Object Type, Touch X, Touch Y, Condition
2025-01-15 14:32:45.123, 00:05.3, Touch Down, Bathroom, 234.5, 456.7, Natural Language
```

- **Touch Move** events are sampled at most once every 100 ms to limit file size.
- Files are named `Mode_Date_Time_vN.csv`.
- Use the **Files** screen inside the app to view, share, or delete log files.
