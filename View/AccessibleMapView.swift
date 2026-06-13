// AccessibleMapView.swift
// MKMapView subclass that handles VoiceOver gestures (3-finger swipe back, Z-scrub escape).
// Copied from Nav_Indoor — same pattern used across Indoor_Route and Nav_Indoor.

import UIKit
import MapKit

class AccessibleMapView: MKMapView {

    var onBackGesture: (() -> Void)?

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        if direction == .right {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred(intensity: 0.8)
            UIAccessibility.post(notification: .announcement, argument: "Going back")
            onBackGesture?()
            return true
        }
        return super.accessibilityScroll(direction)
    }

    override func accessibilityPerformEscape() -> Bool {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: 0.8)
        onBackGesture?()
        return true
    }
}
