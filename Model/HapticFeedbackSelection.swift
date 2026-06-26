// HapticFeedbackSelection.swift
// Stores which haptic pattern goes with each map element type (for Feedback Tester tool).
// Defaults match the patterns used in HapticService / RouteMapView.

import Foundation

// MARK: - Map Element Types

enum MapElementType: String, CaseIterable, Identifiable {
    case corridor = "Street"
    case route = "Route"
    case intersection = "Intersection"
    case landmark = "Landmark"

    var id: String { rawValue }

    /// Maps a map feature type string to a customization element.
    static func from(featureType: String) -> MapElementType? {
        switch featureType {
        case "corridor": return .corridor
        case "route": return .route
        case "intersection": return .intersection
        case "landmark": return .landmark
        default: return nil
        }
    }
}

// MARK: - Haptic Pattern Types

enum HapticPatternType: Int, CaseIterable, Identifiable {
    // App defaults — match HapticService / RouteMapView production patterns
    case heavyBuzz = 1
    case routeRhythmic = 2
    case intersectionSlowPulse = 3
    case landmarkFastPulse = 4

    // Alternates for study customization
    case streetContinuous = 5
    case lightContinuous = 6
    case sharpTransient = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .heavyBuzz: return "Heavy buzz"
        case .routeRhythmic: return "Route"
        case .intersectionSlowPulse: return "Intersection"
        case .landmarkFastPulse: return "Landmark"
        case .streetContinuous: return "Steady"
        case .lightContinuous: return "Light"
        case .sharpTransient: return "Sharp"
        }
    }

    var shortName: String {
        switch self {
        case .heavyBuzz: return "Full rumble"
        case .routeRhythmic: return "Fast pulse"
        case .intersectionSlowPulse: return "Slow + ding"
        case .landmarkFastPulse: return "Quick tick"
        case .streetContinuous: return "Steady 78%"
        case .lightContinuous: return "Soft hum"
        case .sharpTransient: return "Sharp tap"
        }
    }

    /// Patterns that mirror the live navigation map defaults.
    var isAppDefault: Bool {
        switch self {
        case .heavyBuzz, .routeRhythmic, .intersectionSlowPulse, .landmarkFastPulse:
            return true
        default:
            return false
        }
    }
}

// MARK: - Haptic Feedback Selection

struct HapticFeedbackSelection {
    var selections: [MapElementType: HapticPatternType]

    /// Defaults aligned with production: heavy buzz streets, route pulse, intersection slow pulse + ding, landmark fast pulse.
    static let defaults = HapticFeedbackSelection(selections: [
        .corridor: .heavyBuzz,
        .route: .routeRhythmic,
        .intersection: .intersectionSlowPulse,
        .landmark: .landmarkFastPulse
    ])

    func pattern(for element: MapElementType) -> HapticPatternType {
        selections[element] ?? .heavyBuzz
    }
}
