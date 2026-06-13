# Features

---

## Corridor detection and feedback

### What it does (user perspective)
When a participant presses and holds anywhere along a blue hallway line, the device vibrates with a steady, smooth continuous buzz. The vibration persists exactly as long as the finger stays on the corridor and stops immediately on release. There is no speech. The reduced intensity (50 % of maximum) is intentional — it creates a clear contrast against the stronger feedback on route overlays.

### Files and classes

| File | Class / Symbol | Role |
|---|---|---|
| `Model/CorridorFeature.swift` | `CorridorFeature` | Stores coordinates; adds `MKPolyline` to map |
| `Services/HapticService.swift` | `startContinuousVibration()` / `stopContinuousVibration()` | CoreHaptics continuous event at 0.5 intensity |
| `FeedbackManager/FeedbackManager.swift` | `startContinuousSound()` / `stopContinuousSound()` | Orchestrates haptic start/stop; guards against double-start |
| `View/ParticipantMapView.swift` | `ParticipantCoordinator.startFeedback()` | Dispatches to `FeedbackManager` when hit-test returns a corridor |

### Key functions

**`CorridorFeature.addToMap(_:)`** — Creates a plain `MKPolyline` from the corridor's coordinate array and adds it to the map. The polyline `title` is set to the feature `id` so it can be removed later.

**`HapticService.startContinuousVibration()`** — Creates a `CHHapticEvent` of type `.hapticContinuous` with intensity `0.5`, sharpness `0.5`, and duration `100.0` seconds. Wraps it in a `CHHapticPattern`, creates an `CHHapticAdvancedPatternPlayer`, and starts it immediately. Tracks start time for diagnostics.

**`HapticService.stopContinuousVibration()`** — Calls `continuousPlayer?.stop(atTime: CHHapticTimeImmediate)` and records activation duration in the diagnostics struct. Logs a warning if the activation was shorter than 50 ms (too brief to be perceived).

**`FeedbackManager.startContinuousSound()`** — Guards the `isPlayingContinuousSound` flag so repeated calls are no-ops. Calls `stopContinuousPulsing()` and `stopMovingDotFeedback()` first to clear any competing feedback channel before starting corridor vibration.

### Hit detection

`ParticipantCoordinator.isPointNearFeature(_:feature:in:)` uses perpendicular-distance-to-segment geometry (the same projection formula as `DataService`). The threshold is `PhysicalDimensions.mmToPoints(4.0) / 2` — half the visual line width — so the touch target exactly matches what the user sees.

### Interactions with other features
- Route overlay takes priority: if `foundRoute != nil`, `startRoutePulsing()` is called instead of `startContinuousSound()`, even though both are detected as the "corridor" feature type.
- Starting corridor vibration calls `stopContinuousPulsing()` and `stopMovingDotFeedback()` to prevent overlap.
- Corridor has **no audio component** — `SpeechService.announceCorridor()` exists but is not called during touch; it is only called programmatically from `FeedbackManager.provideCorridorFeedback()`, which is wired to explicit tap gestures, not the long-press exploration loop.

---

## Intersection feedback

### What it does (user perspective)
Orange circles mark corridor junctions. Holding a finger on one produces a rhythmic pulse — a medium-speed "thump thump thump" — accompanied by a repeating high-pitched ding (system sound 1057) every 0.4 seconds. The audio ding provides an extra cue for users who find the haptic pulse insufficient on its own.

### Files and classes

| File | Class / Symbol | Role |
|---|---|---|
| `Model/IntersectionFeature.swift` | `IntersectionFeature` | Point annotation; `IntersectionAnnotationView` draws the orange circle |
| `Services/HapticService.swift` | `startVertexFeedback()` / `stopVertexFeedback()` | Pulsing haptic player + repeating ding timer |
| `FeedbackManager/FeedbackManager.swift` | `startContinuousPulsing()` / `stopContinuousPulsing()` | Delegates to `startVertexFeedback()` |
| `View/ParticipantMapView.swift` | `ParticipantCoordinator.startFeedback()` | Dispatches when hit-test returns an intersection |

### Key functions

**`IntersectionAnnotationView.setupView()`** — Sizes the view to `4 mm radius` (`8 mm diameter`) using `PhysicalDimensions.mmToPoints()`. Sets background to `.systemOrange` with a white border (`0.5 mm`) and disables the callout.

**`HapticService.startVertexFeedback()`** — Sets `activeVertexIndex = 0` as a non-nil sentinel, calls `startVertexPulsingHaptic()` (which delegates to `startPulsingVibration()`), plays the first ding immediately via `AudioServicesPlaySystemSound(1057)`, and schedules a `Timer` repeating every 0.4 seconds that calls `playVertexDing()` while `activeVertexIndex != nil`.

**`HapticService.startPulsingVibration()`** — Builds 20 `CHHapticEvent` entries, each `0.15 s` long, spaced `0.25 s` apart (one complete cycle = 0.25 s). Intensity `1.0`, sharpness `0.5`. The player has `loopEnabled = true` so the 20-pulse sequence loops indefinitely until stopped.

**`HapticService.stopVertexFeedback()`** — Invalidates the ding timer, sets `activeVertexIndex = nil`, calls `stopPulsingVibration()`.

**`FeedbackManager.provideIntersectionFeedback(_:)`** — Fires a single `playSingleTap()` (used for quick taps, not long-press exploration).

### Hit detection
Euclidean distance from touch point to the intersection's screen coordinate, threshold `25 pts`. Checked before corridors in `findFeaturesAt(_:in:)` so an intersection wins over an overlapping corridor.

### Interactions with other features
- `startContinuousPulsing()` calls `stopContinuousSound()` first.
- The 0.4 s ding timer is distinct from the intersection pulsing haptic; both must be stopped independently — `stopVertexFeedback()` handles both.
- Speech: intersections have **no speech** in the long-press path. `SpeechService.announceIntersection()` exists but is not called from the main touch loop.

---

## Landmark feedback

### What it does (user perspective)
Red rectangles mark rooms and points of interest. Touching one triggers two simultaneous outputs:
1. A fast, snappy vibration — twice the speed of the intersection pulse — that feels more "ticky" due to higher sharpness.
2. An audio announcement whose format depends on the active study condition (see Feedback Conditions below).

There are also invisible **anchor points** — purple dots placed at the left or right edge of each landmark's row. Touching an anchor produces the same audio as touching the landmark directly, but the natural-language announcement includes a directional qualifier ("Bathroom, left") so the user knows the room is nearby rather than directly underfoot.

### Files and classes

| File | Class / Symbol | Role |
|---|---|---|
| `Model/LandmarkFeature.swift` | `LandmarkFeature`, `LandmarkPresentationMode` | Annotation; holds `name`, `category`, `side` properties |
| `Services/HapticService.swift` | `startFastPulsingVibration()` | 2× faster pulsing, 0.7 sharpness |
| `Services/SpeechService.swift` | `announceLandmark(name:category:side:mode:isAnchorPoint:)` | Routes to the correct condition handler |
| `Services/AudioService.swift` | `speak()`, `speakSpatially()`, `playSpatialSoundEffect()` | Delivers the audio output |
| `FeedbackManager/FeedbackManager.swift` | `startLandmarkPulsing()`, `provideLandmarkFeedback(_:isAnchorPoint:)` | Combines haptic + audio |
| `View/ParticipantMapView.swift` | `updateUIView(_:context:)` — anchor placement; `findFeaturesAt(_:in:)` — hit detection |

### Key functions

**`HapticService.startFastPulsingVibration()`** — Builds 80 `CHHapticEvent` entries, each `0.08 s` long, spaced `0.12 s` apart. Intensity `1.0`, sharpness `0.7` (higher than intersection's `0.5` for a sharper feel). `loopEnabled = true`.

**`SpeechService.announceLandmark(...)`** — Creates `fullIdentifier = "\(name)_\(side)_\(touchType)"`. Blocks the call if the identical identifier was seen within 0.5 s. Otherwise stores the identifier and time, then dispatches to one of three private methods.

**`SpeechService.announceNaturalLanguage(name:side:isAnchorPoint:)`**
- Anchor touch: `"Bathroom , left"` (name + direction phrase)
- Direct touch: `"Bathroom"` (name only — user is on top of it)

**`SpeechService.announceSpatializedAudio(name:side:isAnchorPoint:)`** — Speaks the name through `audioService.speakSpatially(_:at:)`. Position is computed from the `side` string: left → `x = -5`, right → `x = 5`, ahead → `z = -3`, behind → `z = 3`. Both anchor and direct touches produce the name from the same direction.

**`SpeechService.announceSpatializedIcon(category:side:isAnchorPoint:)`** — Looks up a sound file key via `getSoundKeyForCategory()` (e.g. `"bathroom"` → `"toilet_flush"`) and calls `audioService.playSpatialSoundEffect(_:at:)`. The spatial position provides the directional cue.

**Anchor point placement (in `ParticipantMapView.updateUIView`)** — For each landmark, the x coordinate (in map-local units) is inspected. If `x < 500`, the anchor is placed at `x = 200` (left edge); otherwise at `x = 800` (right edge). A `LandmarkAnchorAnnotation` is added as an `MKAnnotation` at that position.

### Hit detection priority
In `findFeaturesAt(_:in:)`:
1. Anchor points checked first (radius `20 pts`), sets `isAnchorTouch = true`
2. Landmarks checked second (radius `25 pts`)
3. Intersections checked third
4. Corridors last

### Interactions with other features
- `startLandmarkPulsing()` calls `stopContinuousSound()` and `stopMovingDotFeedback()` before starting.
- `provideLandmarkFeedback()` fires `playSingleTap()` (immediate transient haptic) in addition to the pulsing, giving an instant click when the landmark is first identified.
- Landmark pulsing uses the same `pulsePlayer` slot as intersection pulsing, so the two cannot overlap.

---

## Route overlay

### What it does (user perspective)
A green line drawn on top of the base map represents a navigation path from start to finish. Touching it while the Controller has loaded a route produces a fast pulsing vibration (same rhythm as landmark pulsing). The route overlay is rendered above corridors, so when the route runs along a corridor the route feedback takes priority.

The route is also the track the moving dot travels along. The controller device drags a dot; the participant device shows the dot as an indigo arrow that animates to the current position along the route.

### Files and classes

| File | Class / Symbol | Role |
|---|---|---|
| `RouteOverlay_POC/Model/RouteFeature.swift` | `RouteFeature`, `RoutePolyline` | Stores coordinates; adds `RoutePolyline` to map above roads level |
| `RouteOverlay_POC/Model/RouteMapData.swift` | `RouteMapData` | Loads route JSON |
| `RouteOverlay_POC/View/RouteMapView.swift` | — | Dual-layer map: base map + route |
| `RouteOverlay_POC/FeedbackManager/FeedbackManager+Route.swift` | `startRoutePulsing()`, `stopRoutePulsing()` | Haptic extension for route |
| `RouteOverlay_POC/Services/HapticService+Route.swift` | `startRouteVibration()` | Dedicated `routePlayer` channel |
| `Model/MovingDotFeature.swift` | `MovingDotAnnotation`, `MovingDotAnnotationView`, `CoordinateSnappingService` | Dot annotation and snapping |
| `View/ParticipantMapView.swift` | `ParticipantCoordinator.updateMovingDot(to:in:)` | Receives position, snaps, animates |
| `View/ControllerMapView.swift` | `ControllerCoordinator` | Sends position on gesture |

### Key functions

**`RouteFeature.addToMap(_:)`** — Creates a `RoutePolyline` (an `MKPolyline` subclass with a `routeId` property) and adds it at `.aboveRoads` level so it renders on top of corridor polylines.

**`ParticipantCoordinator.isPointOnRoute(_:route:in:)`** — Same segment-projection geometry as corridor hit-testing. Threshold: half the route's visual line width (`PhysicalDimensions.mmToPoints(4.0) / 2`).

**`CoordinateSnappingService.snapToRoute(_:route:)`** — Iterates every segment of the route's coordinate array. For each segment, calls `closestPointOnSegment(from:segmentStart:segmentEnd:)` which computes the perpendicular projection of the incoming coordinate, clamps `t` to `[0, 1]`, and returns the projected point. Picks the segment with the minimum Euclidean distance. Returns the closest projected coordinate.

**`CoordinateSnappingService.headingBetween(from:to:)`** — `atan2(dx, dy)` where `dx = to.longitude - from.longitude`, `dy = to.latitude - from.latitude`. Returns degrees 0–360, 0 = north.

**`ParticipantCoordinator.updateMovingDot(to:in:)`** — Receives a `MovingDotPosition`, calls `snapToRoute`, checks the jump guard (`jumpDistance > 0.002`), then wraps `existingDot.updatePosition(to:heading:)` in a `UIView.animate(withDuration: 0.15)` block for smooth movement.

**`MovingDotAnnotationView.setHeading(_:)`** — Applies a `CGAffineTransform(rotationAngle:)` to `arrowLayer` to rotate the indigo arrow to face the direction of travel.

### Route data format
Route JSON files (e.g. `testRoute_1.json`) follow the same GeoJSON-like structure as map data:
- Coordinates are `[x, y]` in floor-plan pixel space
- `MapDataLoader` applies the same `2.6×` vertical stretch
- The `waypoints` array lists ordered intersection/landmark IDs

### Interactions with other features
- When `foundRoute != nil` in `findFeaturesAt`, `startRoutePulsing()` overrides `startContinuousSound()` even though the underlying feature type is `"corridor"`.
- Route overlay renders at `.aboveRoads` level; corridor polylines render at default level — the visual stacking matches the feedback priority.
- `RoutePolyline` is identified in `rendererFor overlay:` by type check (`overlay is RoutePolyline`) before the plain `MKPolyline` check for corridors.

---

## Feedback conditions

### What it does (user perspective)
Three different ways to learn what a landmark is when you touch it. Set once at session start from `RouteSelectionView`; cannot change mid-session.

| Condition | Enum case | What the user hears on anchor touch | What the user hears on direct touch |
|---|---|---|---|
| Natural Language | `.naturalLanguage` | "Bathroom , left" | "Bathroom" |
| Spatialized Audio | `.spatializedAudio` | "Bathroom" from left speaker | "Bathroom" from left speaker |
| Auditory Icons | `.spatializedIcons` | Toilet-flush sound from left speaker | Toilet-flush sound from left speaker |

Practice variants (`.practiceNL`, `.practiceSpatial`, `.practiceIcons`) use the same audio logic on a simpler map.

### Files and classes

| File | Class / Symbol | Role |
|---|---|---|
| `Model/LandmarkFeature.swift` | `LandmarkPresentationMode` | Enum defining the six modes |
| `Services/SpeechService.swift` | `announceLandmark(...)`, three private condition methods | Routes to correct audio output |
| `Services/AudioService.swift` | `speak()`, `speakSpatially()`, `playSpatialSoundEffect()` | Delivers each condition's audio |
| `FeedbackManager/FeedbackManager.swift` | `presentationMode` (computed property) | Proxies to `speechService.presentationMode` |
| `View/RouteSelectionView.swift` | — | UI to choose condition at session start |

### Condition 1 — Natural Language

**`SpeechService.announceNaturalLanguage(name:side:isAnchorPoint:)`**

Anchor touch builds a direction phrase from the `side` property:

```
side = "left"  → announcement = "Bathroom , left"
side = "right" → announcement = "Bathroom , right"
side = "ahead" → announcement = "Bathroom ahead"
```

Direct touch skips the direction phrase:
```
announcement = "Bathroom"
```

Delivered via `AudioService.speak(_:)` → `AVSpeechSynthesizer` at `1.1×` default rate, centre channel (no spatialization).

### Condition 2 — Spatialized Audio

**`SpeechService.announceSpatializedAudio(name:side:isAnchorPoint:)`**

Always speaks just the name. Position from `AudioService.positionForLandmarkSide(_:)`:

```
left   → AVAudio3DPoint(x: -5, y: 0, z:  0)
right  → AVAudio3DPoint(x:  5, y: 0, z:  0)
ahead  → AVAudio3DPoint(x:  0, y: 0, z: -3)
behind → AVAudio3DPoint(x:  0, y: 0, z:  3)
```

Delivered via `AudioService.speakSpatially(_:at:)` → `SpeechSynthesizerManager` renders TTS to an `AVAudioPlayerNode` placed at the 3D position, routed through `AVAudioEnvironmentNode` with HRTF-HQ rendering.

### Condition 3 — Auditory Icons

**`SpeechService.announceSpatializedIcon(category:side:isAnchorPoint:)`**

Maps landmark category to a sound file via `getSoundKeyForCategory()`:

```
"bathroom"        → "toilet_flush"
"kitchen"         → "kitchen"
"elevator"        → "elevator"
"stairs"          → "stairway"
"conference_room" → "conference_room"
"water_fountain"  → "water_running"
"vending_machine" → "vending_machine"
(default)         → "door_knock"
```

Delivered via `AudioService.playSpatialSoundEffect(_:at:)` — loads the audio file from the bundle, converts stereo → mono if needed (for correct HRTF spatialization), and schedules the buffer on the same `AVAudioPlayerNode` used for condition 2. The spatial position is the same as condition 2.

### Debounce logic

All three conditions share the same gate in `SpeechService.announceLandmark()`:

```swift
let fullIdentifier = "\(name)_\(side)_\(touchType)"  // e.g. "Bathroom_left_anchor"

if lastIdentifier == fullIdentifier &&
   Date().timeIntervalSince(lastTime) < 0.5 {
    return  // blocked
}
```

`touchType` is either `"anchor"` or `"direct"`. This means:
- Same landmark, same touch type, within 0.5 s → **blocked** (prevents rapid repeated announcements while resting)
- Same landmark, **different** touch type → **allowed** (anchor → direct transition confirms position)
- Different landmark → **always allowed**

### Haptic feedback is identical across all three conditions
The pulsing vibration pattern does not change with the presentation mode. Only the audio output changes. This allows participants to detect landmarks haptically regardless of the audio condition.

---

## Moving dot feedback

### What it does (user perspective)
The indigo arrow on the map represents the participant's current position as guided by the researcher on the Controller device. When the participant's finger rests on the dot, they receive a rhythmic haptic pulse with a distinct "tick" tone every 0.3 seconds. This pattern is different enough from corridor (continuous), intersection (slow pulse + ding), and landmark (fast pulse) that it is identifiable by feel alone.

### Files and classes

| File | Class / Symbol | Role |
|---|---|---|
| `Model/MovingDotFeature.swift` | `MovingDotAnnotation`, `MovingDotAnnotationView`, `CoordinateSnappingService` | Annotation, rendering, snapping |
| `Services/HapticService.swift` | `startMovingDotFeedback()`, `stopMovingDotFeedback()`, `playMovingDotTickOnce()` | Haptic + tick sound |
| `FeedbackManager/FeedbackManager.swift` | `startMovingDotFeedback()`, `stopMovingDotFeedback()`, `playMovingDotTick()` | Orchestration |
| `View/ParticipantMapView.swift` | `isPointOnMovingDot(_:in:)`, `updateMovingDot(to:in:)` | Hit detection, animation |
| `Services/MultipeerService.swift` | `MovingDotPosition`, `sendPosition()`, `MCSessionDelegate` | Network transport |

### Key functions

**`HapticService.startMovingDotFeedback()`** — Stops all other channels, builds 40 pulses of `0.06 s` duration at `0.18 s` intervals (intensity `0.85`, sharpness `1.0` — maximum sharpness for a crisp feel). `loopEnabled = true`. Calls `playMovingDotTickOnce()` immediately, then schedules a `Timer` repeating every `0.3 s`.

**`HapticService.playMovingDotTickOnce()`** — `AudioServicesPlaySystemSound(1104)` — a different system sound from the intersection ding (1057), reinforcing the distinctness of the pattern.

**`ParticipantCoordinator.isPointOnMovingDot(_:in:)`** — Converts dot annotation coordinate to screen point, computes Euclidean distance to touch point. Threshold: `PhysicalDimensions.mmToPoints(10.0) / 2` (5 mm radius), matching the 10 mm visual size of the arrow.

**Moving dot priority** — In both `startFeedback()` and `updateFeedback()`, the moving dot is checked first. If `isPointOnMovingDot` returns `true`, feedback is dispatched to `startMovingDotFeedback()` without checking any other feature, and the function returns early.

### Data transport (MultipeerService)

```swift
struct MovingDotPosition: Codable {
    var x: Double          // map-local x (longitude * 100000)
    var y: Double          // map-local y (latitude * 100000)
    var routeId: String
    var timestamp: TimeInterval
}
```

Controller calls `MultipeerService.shared.sendPosition(_:)` → encodes to JSON → `MCSession.send(data:toPeers:with:)` (`.reliable` mode). Participant receives in `session(_:didReceive:fromPeer:)` → decodes → publishes to `@Published var receivedPosition`.

`MovingDotPosition.coordinate` (computed, in `MovingDotFeature.swift`) converts back: `latitude = y / 100_000`, `longitude = x / 100_000`.
