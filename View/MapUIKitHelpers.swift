import MapKit

enum MapRoadStyle {
    static let blue = UIColor(red: 0.18, green: 0.52, blue: 0.62, alpha: 0.85)
    static let lineWidthMM: CGFloat = 4.0

    /// Distinct colors so each corridor is visually separable while designing.
    static let palette: [UIColor] = [
        UIColor(red: 0.18, green: 0.52, blue: 0.62, alpha: 0.95), // teal
        UIColor(red: 0.90, green: 0.30, blue: 0.24, alpha: 0.95), // red
        UIColor(red: 0.18, green: 0.65, blue: 0.34, alpha: 0.95), // green
        UIColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 0.95), // orange
        UIColor(red: 0.51, green: 0.30, blue: 0.78, alpha: 0.95), // purple
        UIColor(red: 0.85, green: 0.33, blue: 0.60, alpha: 0.95), // pink
        UIColor(red: 0.40, green: 0.45, blue: 0.50, alpha: 0.95), // slate
        UIColor(red: 0.10, green: 0.40, blue: 0.85, alpha: 0.95), // blue
    ]

    /// Stable per-corridor color keyed off the trailing number in its id ("c_3" -> index 2).
    static func color(for id: String?) -> UIColor {
        guard let id = id else { return blue }
        let digits = id.drop { !$0.isNumber }
        if let n = Int(digits), n > 0 {
            return palette[(n - 1) % palette.count]
        }
        return palette[abs(id.hashValue) % palette.count]
    }
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
