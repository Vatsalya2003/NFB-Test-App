// MapUIKitHelpers.swift
// Shared map settings: colors, mm sizes, fixed viewport, blank white tiles.
// All visual constants (road blue, intersection red, etc.) live here.

import MapKit

enum MapRoadStyle {
    /// Road blue (#023e8a).
    static let blue = UIColor(red: 0x02 / 255.0, green: 0x3e / 255.0, blue: 0x8a / 255.0, alpha: 1.0)
    static let lineWidthMM: CGFloat = 4.0
}

enum MapIntersectionStyle {
    /// Intersection red (#c1121f).
    static let red = UIColor(red: 0xc1 / 255.0, green: 0x12 / 255.0, blue: 0x1f / 255.0, alpha: 1.0)
    static let sideMM: CGFloat = 5.0
}

enum MapRouteStyle {
    /// Route line (#48cae4).
    static let color = UIColor(red: 0x48 / 255.0, green: 0xca / 255.0, blue: 0xe4 / 255.0, alpha: 1.0)
    static let lineWidthMM: CGFloat = 3.5
}

enum MapLandmarkStyle {
    /// Landmark marker (#7b2cbf) — a small tagged box placed beside the road.
    static let color = UIColor(red: 0x7b / 255.0, green: 0x2c / 255.0, blue: 0xbf / 255.0, alpha: 1.0)
    static let diameterMM: CGFloat = 6.0

    /// Box (building marker) sizing, in physical mm.
    static let boxWidthMM: CGFloat = 9.0
    static let boxHeightMM: CGFloat = 6.0
    static let cornerRadiusMM: CGFloat = 1.2
    static let borderWidthMM: CGFloat = 0.5
    /// Gap between the road edge and the landmark box edge.
    static let gapMM: CGFloat = 2.0

    /// Screen-point offset that pushes the box to the side of the road.
    /// Anchor stays on the road centerline; offset accounts for road half-width + gap + box half-width.
    static func sideOffset(_ side: String) -> CGPoint {
        let halfRoad = PhysicalDimensions.mmToPoints(MapRoadStyle.lineWidthMM) / 2
        let gap = PhysicalDimensions.mmToPoints(gapMM)
        let halfBox = PhysicalDimensions.mmToPoints(boxWidthMM) / 2
        let dx = halfRoad + gap + halfBox
        switch side.lowercased() {
        case "right": return CGPoint(x: dx, y: 0)
        case "left": return CGPoint(x: -dx, y: 0)
        default: return .zero
        }
    }
}

enum MapSidewalkStyle {
    /// Sidewalk gray (#9e9e9e).
    static let color = UIColor(red: 0x9e / 255.0, green: 0x9e / 255.0, blue: 0x9e / 255.0, alpha: 1.0)
    static let lineWidthMM: CGFloat = 4.0
}

enum MapCrosswalkStyle {
    /// Crosswalk white with dashes.
    static let color = UIColor.white
    static let lineWidthMM: CGFloat = 2.0
    static let dashPattern: [NSNumber] = [6, 4]
}

/// Level 2 intersection layout — sidewalk lines in designer JSON use 440/560 around center 500.
enum MapIntersectionLayout {
    static let center = 500.0
    /// Designer offset for vertical sidewalks (X axis, not stretched). Tune this value.
    static let sidewalkOffsetX = 120.0
    /// Designer offset for horizontal sidewalks — smaller because Y is stretched 2.6× in MapDataLoader.
    static var sidewalkOffsetY: Double { sidewalkOffsetX / yStretchFactor }
    /// Keep in sync with MapDataLoader.stretchFactor.
    private static let yStretchFactor = 2.6

    static func remapCoordinate(_ coord: [Double]) -> [Double] {
        guard coord.count >= 2 else { return coord }
        return [remapX(coord[0]), remapY(coord[1])]
    }

    private static func remapX(_ value: Double) -> Double {
        if value == 440 { return center - sidewalkOffsetX }
        if value == 560 { return center + sidewalkOffsetX }
        return value
    }

    private static func remapY(_ value: Double) -> Double {
        if value == 440 { return center - sidewalkOffsetY }
        if value == 560 { return center + sidewalkOffsetY }
        return value
    }
}

enum MapDestinationStyle {
    /// Yellow dot marking the route end / point of interest.
    static let color = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
    static let diameterMM: CGFloat = 4.0
}

enum MapFixedViewport {
    /// Fixed viewport tuned to a tall/narrow rect so corridor content fills the
    /// iPhone safe area top-to-bottom. Kept in sync with MapDesignerView's window.
    static let edgePadding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

    /// Vertical-flip pivot used when converting JSON coordinates to latitude.
    /// JSON/designer use a top-down Y axis (y=0 is top) while MapKit latitude is
    /// bottom-up, so we mirror the (already stretched) Y around this value to keep
    /// "JSON top = screen top". Equals the stretched-Y window (syMin + syMax) used
    /// by MapDesignerView (160 + 1160), so the viewport stays identical after the flip.
    static let verticalFlipSum: Double = 1320

    static func apply(to mapView: MKMapView, edgePadding: UIEdgeInsets? = nil) {
        let southwest = MKMapPoint(CLLocationCoordinate2D(latitude: 0.0016, longitude: 0.0027))
        let northeast = MKMapPoint(CLLocationCoordinate2D(latitude: 0.0116, longitude: 0.0073))
        let mapRect = MKMapRect(
            x: southwest.x,
            y: northeast.y,
            width: northeast.x - southwest.x,
            height: southwest.y - northeast.y
        )
        mapView.setVisibleMapRect(
            mapRect,
            edgePadding: edgePadding ?? Self.edgePadding,
            animated: false
        )
    }
}

enum MapIntersectionViewport {
    static let edgePadding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

    static func apply(to mapView: MKMapView, edgePadding: UIEdgeInsets? = nil) {
        let southwest = MKMapPoint(CLLocationCoordinate2D(latitude: -0.003, longitude: 0.0005))
        let northeast = MKMapPoint(CLLocationCoordinate2D(latitude: 0.019, longitude: 0.0095))
        let mapRect = MKMapRect(
            x: southwest.x,
            y: northeast.y,
            width: northeast.x - southwest.x,
            height: southwest.y - northeast.y
        )
        mapView.setVisibleMapRect(
            mapRect,
            edgePadding: edgePadding ?? Self.edgePadding,
            animated: false
        )
    }
}

enum MapVisibleRectHelper {
    static func corridorFeatures(from features: [MapFeature]) -> [MapFeature] {
        features.filter { $0.featureType == "corridor" }
    }

    static func boundingMapRect(for features: [MapFeature], routes: [RouteFeature] = []) -> MKMapRect {
        var mapRect = MKMapRect.null

        for feature in corridorFeatures(from: features) {
            if let corridor = feature as? CorridorFeature {
                mapRect = mapRect.union(corridor.boundingMapRect)
            }
        }

        for route in routes {
            mapRect = mapRect.union(route.boundingMapRect)
        }

        return mapRect
    }

    static func fitMapView(
        _ mapView: MKMapView,
        features: [MapFeature],
        routes: [RouteFeature] = [],
        edgePadding: UIEdgeInsets = .zero
    ) {
        var mapRect = boundingMapRect(for: features, routes: routes)
        guard !mapRect.isNull else { return }

        let viewSize = mapView.bounds.size
        let effectiveWidth = viewSize.width - edgePadding.left - edgePadding.right
        let effectiveHeight = viewSize.height - edgePadding.top - edgePadding.bottom
        guard effectiveWidth > 0, effectiveHeight > 0 else { return }

        // Cover mode — zoom in so the grid fills the drawable area (no letterboxing)
        let contentAspect = mapRect.width / mapRect.height
        let viewAspect = Double(effectiveWidth / effectiveHeight)

        if contentAspect > viewAspect {
            let newWidth = mapRect.height * viewAspect
            let dx = (mapRect.width - newWidth) / 2
            mapRect = MKMapRect(
                x: mapRect.origin.x + dx,
                y: mapRect.origin.y,
                width: newWidth,
                height: mapRect.height
            )
        } else {
            let newHeight = mapRect.width / viewAspect
            let dy = (mapRect.height - newHeight) / 2
            mapRect = MKMapRect(
                x: mapRect.origin.x,
                y: mapRect.origin.y + dy,
                width: mapRect.width,
                height: newHeight
            )
        }

        mapView.setVisibleMapRect(mapRect, edgePadding: edgePadding, animated: false)
    }
}

class FittingMapView: MKMapView {
    var fitFeatures: [MapFeature] = []
    var fitRoutes: [RouteFeature] = []
    /// When true, insets the fit to the view's safe area (status bar, home indicator).
    var fitToSafeArea: Bool = true
    /// Optional extra padding (e.g. tester view bottom panel). Used when `fitToSafeArea` is false.
    var customEdgePadding: UIEdgeInsets = .zero

    private var effectiveEdgePadding: UIEdgeInsets {
        if !fitToSafeArea { return customEdgePadding }
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let safeFrame = safeAreaLayoutGuide.layoutFrame
        return UIEdgeInsets(
            top: safeFrame.minY,
            left: safeFrame.minX,
            bottom: bounds.maxY - safeFrame.maxY,
            right: bounds.maxX - safeFrame.maxX
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !fitFeatures.isEmpty || !fitRoutes.isEmpty else { return }

        MapVisibleRectHelper.fitMapView(
            self,
            features: fitFeatures,
            routes: fitRoutes,
            edgePadding: effectiveEdgePadding
        )
    }
}

class LandmarkAnchorAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let landmark: LandmarkFeature

    init(coordinate: CLLocationCoordinate2D, landmark: LandmarkFeature) {
        self.coordinate = coordinate
        self.landmark = landmark
        super.init()
    }
}

class BlankTileOverlay: MKTileOverlay {
    override init(urlTemplate URLTemplate: String?) {
        super.init(urlTemplate: nil)
        self.canReplaceMapContent = true
    }
}

class WhiteTileRenderer: MKTileOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let rect = self.rect(for: mapRect)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
    }
}
