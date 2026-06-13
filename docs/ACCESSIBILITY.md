# Accessibility

---

## Overview

NFB Test is designed to be operated primarily through touch without vision. All map content is conveyed through haptic vibration and audio output. Visual rendering exists to support sighted researchers (Controller role) and for development/debugging. The Participant device is expected to be used with screen-based touch exploration, with optional VoiceOver support.

---

## VoiceOver integration

### Configuration

VoiceOver support is conditionally applied at map creation time in `ParticipantMapView.makeUIView(context:)`:

```swift
if UIAccessibility.isVoiceOverRunning {
    mapView.isAccessibilityElement = true
    mapView.accessibilityTraits = [.allowsDirectInteraction]
    mapView.accessibilityLabel = "Tactile map with moving dot"
    mapView.accessibilityHint = "Touch to explore. The moving dot shows your current position."
}
```

This configuration is applied only when VoiceOver is detected as active, so it does not affect sighted-use sessions.

**File**: `View/ParticipantMapView.swift:69–74`

### Direct Interaction trait

The `.allowsDirectInteraction` accessibility trait is the critical setting. It tells VoiceOver to pass raw touch events directly to the view rather than intercepting them for VoiceOver's own gesture vocabulary (swipe-to-navigate, double-tap-to-activate, etc.).

Without this trait, VoiceOver would consume the long-press and drag gestures that drive the haptic feedback loop. With it, the user's raw finger contact reaches `ParticipantCoordinator`'s gesture recognizers as normal `UITouch` events.

**Consequence**: When `.allowsDirectInteraction` is active, VoiceOver's standard navigation gestures (swipe between elements, two-finger scroll) are suppressed inside the map view. Users must use the app's own gesture set (described below).

### When VoiceOver is not running

When VoiceOver is off, `isAccessibilityElement` and `accessibilityTraits` are not set, so the map receives standard UIKit touch events with no VoiceOver overhead. This is the typical session configuration.

---

## Direct touch mode

The Participant map is permanently configured as a direct-touch surface rather than a standard accessible view:

- `isUserInteractionEnabled = true` — always
- Pan, zoom, rotation, and pitch are all disabled (`isZoomEnabled = false`, `isScrollEnabled = false`, etc.)
- The map region is fixed to the floor-plan bounds and cannot be changed by user gestures

This means every touch event on the map surface is available to the custom gesture recognizers. There is no MapKit pan/zoom gesture consuming events.

---

## Custom gestures

All custom gestures are added in `ParticipantMapView.addExplorationGestures(to:coordinator:)` and `makeUIView(context:)`.

### Long press — primary exploration gesture

```
UILongPressGestureRecognizer
  minimumPressDuration: 0.1 s
  allowableMovement:    10000 pts  (effectively unlimited — drag freely)
  requires doubleTap to fail
```

**What it does**: Begins feedback on `.began`, updates feedback as finger moves on `.changed` (throttled to 100 ms), stops all feedback on `.ended` / `.cancelled` / `.failed`.

This is the main exploration gesture. A threshold of 0.1 s means almost any intentional touch activates it, while the unlimited movement allows the user to drag their finger across the map and receive continuous feedback transitions.

**File**: `View/ParticipantMapView.swift:120–128`

### Single tap — orientation cue

```
UITapGestureRecognizer (1 tap, 1 finger)
  requires doubleTap to fail
```

**What it does**: Plays a single `playSingleTap()` haptic pulse for orientation. If the tap lands on the moving dot, plays `playMovingDotTick()` instead. Also announces a landmark or intersection if the tap hits one (calls `provideLandmarkFeedback` or `provideIntersectionFeedback`). Primarily useful for quick identification of a point without needing to hold.

**File**: `View/ParticipantMapView.swift:105–109`, `handleSingleTap(_:)` at line 280

### Double tap — confirmation pulse

```
UITapGestureRecognizer (2 taps, 1 finger)
```

**What it does**: Plays `playPulseHaptic()` — a single strong transient haptic. Acts as a generic confirmation or "I am here" cue with no map-content-specific action.

**File**: `View/ParticipantMapView.swift:110–114`, `handleDoubleTap(_:)` at line 275

### Three-finger swipe right — end session / advance

```
UISwipeGestureRecognizer
  direction:               .right
  numberOfTouchesRequired: 3
```

**What it does**: Calls `onThreeFingerSwipe?()` — a closure provided by the parent view. Typically used to dismiss the map view or advance to the next trial. Requires three simultaneous fingers to avoid conflict with single-finger exploration.

Only added if `onThreeFingerSwipe != nil` at map creation time.

**File**: `View/ParticipantMapView.swift:88–96`, `handleThreeFingerSwipe(_:)` at line 270

### Gesture dependency chain

```
singleTap.require(toFail: doubleTap)
longPress.require(toFail: doubleTap)
```

The single tap and long press only fire after the system confirms a double tap did not occur. This prevents a double tap from also triggering two single taps or a long press. The slight delay before single-tap/long-press fires is the trade-off.

---

## How haptic and audio feedback layers work together

The two channels — haptic (CoreHaptics) and audio (AVAudioEngine / AVSpeechSynthesizer) — are designed to be complementary and non-redundant.

### Division of responsibility

| Element | Haptic pattern | Audio output |
|---|---|---|
| Corridor | Continuous 50 % intensity buzz | None |
| Intersection | Slow pulse (0.25 s cycle) + ding every 0.4 s | None (no speech) |
| Landmark | Fast pulse (0.12 s cycle, high sharpness) | Speech or sound (condition-dependent) |
| Route | Fast pulse (same as landmark) | None |
| Moving dot | Rhythmic pulse (0.18 s cycle, max sharpness) + tick every 0.3 s | None |

Corridors and intersections are identified **entirely by haptics** — no speech is produced. This means participants can explore the map silently and receive full structural information through vibration alone.

Landmarks add speech/audio on top of the haptic pulse because their identity (which room it is) cannot be conveyed by vibration alone.

### Mutual exclusion

`FeedbackManager` enforces that only one haptic channel runs at a time. Every `start*` method calls `stop*` on competing channels:

```
startContinuousSound()   → stopContinuousPulsing(), stopMovingDotFeedback()
startContinuousPulsing() → stopContinuousSound(),   stopMovingDotFeedback()
startLandmarkPulsing()   → stopContinuousSound(),   stopMovingDotFeedback()
startMovingDotFeedback() → stopContinuousSound(),   stopContinuousPulsing()
```

Audio (speech or sound effect) is not gated the same way — `AudioService` allows overlap between haptic patterns and audio output. However, `SpeechService` debounces rapid-fire speech announcements (0.5 s window, same touch type).

### Sequencing: haptic first, then audio

In `FeedbackManager.provideLandmarkFeedback(_:isAnchorPoint:)`:

```swift
hapticService.playSingleTap()       // Immediate transient haptic

speechService.announceLandmark(     // Audio follows (no artificial delay)
    name: name,
    category: category,
    side: side,
    ...
)
```

The haptic fires synchronously before the audio call. Because `AVSpeechSynthesizer` processes asynchronously, the physical tap is felt a few milliseconds before the speech begins, reinforcing the "I found something" moment.

### Audio session configuration

`AudioService` configures the shared `AVAudioSession` as `.playAndRecord` with `.spokenAudio` mode:

```swift
try session.setCategory(
    .playAndRecord,
    mode: .spokenAudio,
    options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
)
```

- `.spokenAudio` causes other apps' audio to duck when speech plays (relevant if background music is on)
- `.defaultToSpeaker` ensures the sound comes from the iPhone speaker, not the earpiece
- `.allowBluetooth` enables Bluetooth headphones / AirPods for the spatial audio effect
- `.mixWithOthers` prevents the app from silencing ongoing audio when it activates

Interruption handling (`handleAudioSessionInterruption`) restarts the `AVAudioEngine` if an interruption (e.g. incoming call) ends while the session is active.

---

## How the three feedback conditions differ in accessibility behavior

The three conditions are designed to test different levels of audio-based spatial information. The haptic layer is identical across all three.

### Condition 1 — Natural Language

**Accessibility profile**: Most explicit. Landmarks are announced with their name and direction using words. Does not require the user to localize sound direction.

- Works well with or without headphones
- Works with VoiceOver: the announcement is a standard `AVSpeechUtterance`, which VoiceOver does not interfere with
- Directional information is encoded in the text ("on your left"), making it accessible to users with any level of hearing
- Suitable for users with hearing impairment if volume is adequate

**Announcement examples**:
- Anchor touch: `"Bathroom , left"`
- Direct touch: `"Bathroom"`

### Condition 2 — Spatialized Audio

**Accessibility profile**: Requires the ability to perceive left/right audio directionality. Best with headphones; speaker-only spatialization is reduced. HRTF (Head-Related Transfer Function) rendering requires the sound to be mono at the source.

- `AVAudioPlayerNode.renderingAlgorithm = .HRTFHQ` — highest-quality HRTF
- `AVAudioPlayerNode.sourceMode = .spatializeIfMono` — only spatializes mono content
- `SpeechSynthesizerManager` pipes TTS output as mono PCM into the player node
- Listener is at origin `(0, 0, 0)` facing forward; landmark positions are `±5` units on the x-axis
- A small-room reverb (`AVAudioEnvironmentNode.reverbParameters.loadFactoryReverbPreset(.smallRoom)`) adds a subtle sense of space

**Accessibility note**: Users with monaural hearing or significant hearing asymmetry may not benefit from spatialization. This is a research variable, not an error condition.

### Condition 3 — Auditory Icons

**Accessibility profile**: Requires learned association between sounds and landmark types. The spatial position is the same as condition 2. No speech is produced.

- Sound files are loaded from the bundle at init time into `soundEffectPlayers` dictionary
- Spatial playback uses the same `AVAudioPlayerNode` pipeline as condition 2
- Stereo files are converted to mono before playback to enable correct HRTF spatialization:

  ```swift
  if file.processingFormat.channelCount != playerFormat.channelCount {
      // AVAudioConverter: stereo → mono
  }
  ```

- If the sound file cannot be found or loaded, the method returns silently — no fallback speech is produced
- The `getSoundKeyForCategory()` fallback for unrecognized categories is `"door_knock"`

**Accessibility note**: Auditory icons are the most implicit condition. Users who have not completed a familiarization phase may not recognize the mapping. The practice variants (`.practiceIcons`) are provided for this reason.

### Summary: what changes across conditions

| Property | Condition 1 | Condition 2 | Condition 3 |
|---|---|---|---|
| Haptic pattern | Identical | Identical | Identical |
| Output modality | Speech (center channel) | Speech (spatialized) | Sound effect (spatialized) |
| Directional cue | In text ("on your left") | Ear direction (HRTF) | Ear direction (HRTF) |
| Requires headphones | No | Recommended | Recommended |
| Requires sound recognition | No | No | Yes |
| VoiceOver compatible | Yes | Partial (HRTF may conflict) | Yes |
| Anchor vs. direct distinction | Text differs | No text difference | No text difference |
