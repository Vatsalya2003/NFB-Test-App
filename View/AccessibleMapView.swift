// AccessibleMapView.swift
// MKMapView subclass for VoiceOver tactile exploration.
// Uses allowsDirectInteraction + silentOnTouch so touches pass through to haptics.
// When VoiceOver is on, UIKit gesture recognizers often do not fire — we handle
// touches directly via touchesBegan/Moved/Ended instead.

import UIKit
import MapKit

/// Receives touch events from AccessibleMapView (VoiceOver direct-touch path).
protocol AccessibleMapTouchDelegate: AnyObject {
    func accessibleMapView(_ mapView: MKMapView, touchBeganAt point: CGPoint)
    func accessibleMapView(_ mapView: MKMapView, touchMovedTo point: CGPoint)
    func accessibleMapView(_ mapView: MKMapView, touchEndedAt point: CGPoint)
    func accessibleMapView(_ mapView: MKMapView, singleTappedAt point: CGPoint)
    func accessibleMapView(_ mapView: MKMapView, doubleTappedAt point: CGPoint)
}

class AccessibleMapView: MKMapView {

    /// Two-finger swipe right in VoiceOver — only enable on screens where that should go back one level.
    var onAccessibilityScrollBack: (() -> Void)?
    /// Escape (two-finger Z) in VoiceOver.
    var onAccessibilityEscape: (() -> Void)?
    weak var touchDelegate: AccessibleMapTouchDelegate?

    private var activeTouch: UITouch?
    private var touchStartPoint: CGPoint = .zero
    private var touchStartTime: TimeInterval = 0
    private var isDragging = false
    private var didPostVoiceOverFocus = false

    private var pendingSingleTapWorkItem: DispatchWorkItem?
    private var lastTapTime: TimeInterval = 0
    private var lastTapPoint: CGPoint = .zero

    private let dragThreshold: CGFloat = 8
    private let tapMaxDisplacement: CGFloat = 28
    private let tapMaxDuration: TimeInterval = 0.45
    private let doubleTapMaxInterval: TimeInterval = 0.45
    private let doubleTapMaxDistance: CGFloat = 48

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAccessibility()
        observeVoiceOverChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
        observeVoiceOverChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil,
              UIAccessibility.isVoiceOverRunning,
              !didPostVoiceOverFocus else { return }
        didPostVoiceOverFocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, self.window != nil else { return }
            UIAccessibility.post(notification: .layoutChanged, argument: self)
        }
    }

    // MARK: - Accessibility

    func configureAccessibility(label: String, hint: String) {
        isAccessibilityElement = true
        accessibilityTraits = [.allowsDirectInteraction]
        accessibilityLabel = label
        accessibilityHint = hint
        accessibilityViewIsModal = false

        if #available(iOS 17.0, *) {
            // Pass touches straight to the map without requiring a two-finger
            // activation gesture or speaking on every touch (WWDC23 piano-key pattern).
            accessibilityDirectTouchOptions = .silentOnTouch
        }
    }

    private func configureAccessibility() {
        configureAccessibility(
            label: "Tactile navigation map",
            hint: "Touch and drag to feel streets and hear names."
        )
    }

    private func observeVoiceOverChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(voiceOverStatusChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func voiceOverStatusChanged() {
        // Re-apply traits after VoiceOver toggles so direct touch stays active.
        accessibilityTraits = [.allowsDirectInteraction]
        if #available(iOS 17.0, *) {
            accessibilityDirectTouchOptions = .silentOnTouch
        }
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard direction == .right, let action = onAccessibilityScrollBack else { return false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
        UIAccessibility.post(notification: .announcement, argument: "Going back")
        action()
        return true
    }

    override func accessibilityPerformEscape() -> Bool {
        guard let action = onAccessibilityEscape else { return false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
        action()
        return true
    }

    // MARK: - VoiceOver direct touch (bypasses gesture recognizers)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard UIAccessibility.isVoiceOverRunning,
              let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        activeTouch = touch
        touchStartPoint = touch.location(in: self)
        touchStartTime = CACurrentMediaTime()
        isDragging = false
        pendingSingleTapWorkItem?.cancel()
        pendingSingleTapWorkItem = nil

        touchDelegate?.accessibleMapView(self, touchBeganAt: touchStartPoint)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard UIAccessibility.isVoiceOverRunning,
              let touch = touches.first,
              touch == activeTouch else {
            super.touchesMoved(touches, with: event)
            return
        }

        let point = touch.location(in: self)
        if hypot(point.x - touchStartPoint.x, point.y - touchStartPoint.y) > dragThreshold {
            isDragging = true
            pendingSingleTapWorkItem?.cancel()
            pendingSingleTapWorkItem = nil
        }

        touchDelegate?.accessibleMapView(self, touchMovedTo: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard UIAccessibility.isVoiceOverRunning,
              let touch = touches.first,
              touch == activeTouch else {
            super.touchesEnded(touches, with: event)
            return
        }

        let point = touch.location(in: self)
        let duration = CACurrentMediaTime() - touchStartTime
        let displacement = hypot(point.x - touchStartPoint.x, point.y - touchStartPoint.y)

        touchDelegate?.accessibleMapView(self, touchEndedAt: point)

        if displacement < tapMaxDisplacement && duration < tapMaxDuration {
            let now = CACurrentMediaTime()
            let isDoubleTap = (now - lastTapTime) < doubleTapMaxInterval
                && hypot(point.x - lastTapPoint.x, point.y - lastTapPoint.y) < doubleTapMaxDistance

            if isDoubleTap {
                pendingSingleTapWorkItem?.cancel()
                pendingSingleTapWorkItem = nil
                lastTapTime = 0
                touchDelegate?.accessibleMapView(self, doubleTappedAt: point)
            } else {
                lastTapTime = now
                lastTapPoint = point

                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.touchDelegate?.accessibleMapView(self, singleTappedAt: point)
                    self.lastTapTime = 0
                }
                pendingSingleTapWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapMaxInterval, execute: work)
            }
        }

        activeTouch = nil
        isDragging = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard UIAccessibility.isVoiceOverRunning,
              let touch = touches.first,
              touch == activeTouch else {
            super.touchesCancelled(touches, with: event)
            return
        }

        pendingSingleTapWorkItem?.cancel()
        pendingSingleTapWorkItem = nil
        touchDelegate?.accessibleMapView(self, touchEndedAt: touch.location(in: self))
        activeTouch = nil
        isDragging = false
    }
}
