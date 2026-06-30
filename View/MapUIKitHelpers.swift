// MapUIKitHelpers.swift
// Shared map settings: colors, mm sizes, fixed viewport, blank white tiles.
// All visual constants (road blue, intersection red, etc.) live here.

import MapKit
import UIKit

enum MapRoadStyle {
    /// Road blue (#023e8a).
    static let blue = UIColor(red: 0x02 / 255.0, green: 0x3e / 255.0, blue: 0x8a / 255.0, alpha: 1.0)
    static let lineWidthMM: CGFloat = 4.0
}

enum MapIntersectionStyle {
    /// Intersection red (#c1121f).
    static let red = UIColor(red: 0xc1 / 255.0, green: 0x12 / 255.0, blue: 0x1f / 255.0, alpha: 1.0)
    static let sideMM: CGFloat = 6.0
}

/// Level 2 intersection detail — wider roads, sidewalks beside them.
enum MapIntersectionDetailStyle {
    static let roadLineWidthMM: CGFloat = 12.0
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

/// Map orientation — Marriott → JW uses a data mirror (not UIView rotation; MapKit breaks when rotated).
enum MapOrientation {
  static let marriottToJWRouteFile = "route_marriott_to_jwmarriott"
  static let jwToMarriottRouteFile = "route_jwmarriott_to_marriott"
  private static let designerPivot = 500.0

  /// Never rotate the MKMapView — it hides/clips the route. Use `shouldMirrorMap` instead.
  static func isRotated180(forRouteFile routeFile: String) -> Bool { false }

  /// Flip map data 180° around grid center so departure sits toward the bottom (Marriott → JW).
  static func shouldMirrorMap(forRouteFile routeFile: String) -> Bool {
    routeFile == marriottToJWRouteFile
  }

  /// Level 2 intersection JSON routes are authored for Marriott → JW; reverse for the return trip.
  static func shouldReverseIntersectionRoute(forRouteFile routeFile: String) -> Bool {
    routeFile == jwToMarriottRouteFile
  }

  /// Landmarks in JSON are authored for Marriott → JW (left). JW → Marriott uses the opposite side.
  static func shouldFlipLandmarkSide(forRouteFile routeFile: String) -> Bool {
    routeFile == jwToMarriottRouteFile
  }

  static func flippedLandmarkSide(_ side: String) -> String {
    switch side.lowercased() {
    case "left": return "right"
    case "right": return "left"
    default: return side
    }
  }

  static func flippedLandmarkAnnouncement(_ announcement: String) -> String {
    if announcement.contains("on your left") {
      return announcement.replacingOccurrences(of: "on your left", with: "on your right")
    }
    if announcement.contains("on your right") {
      return announcement.replacingOccurrences(of: "on your right", with: "on your left")
    }
    return announcement
  }

  /// Mirror a designer-grid point (0–1000) around the intersection center before stretch.
  static func mirrorDesignerCoordinate(_ coord: [Double]) -> [Double] {
    guard coord.count >= 2 else { return coord }
    return [2 * designerPivot - coord[0], 2 * designerPivot - coord[1]]
  }

  static func applyRotation(rotated180: Bool, to mapView: MKMapView) {
    mapView.transform = .identity
  }

  static func hitTestPoint(from viewPoint: CGPoint, in mapView: MKMapView, rotated180: Bool) -> CGPoint {
    viewPoint
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
    static let lineWidthMM: CGFloat = 2.8
    /// Length of each white stripe along the crossing (matches prior dashPattern[0]).
    static let dashLengthPoints: CGFloat = 6
    static let stripeCount = 3
    /// Legacy dash pattern — kept for reference; rendering uses `CrosswalkStripeRenderer`.
    static let dashPattern: [NSNumber] = [6, 4]
}

/// Level 2 intersection layout — sidewalk lines in designer JSON use 440/560 around center 500.
enum MapIntersectionLayout {
    static let center = 500.0

    // MARK: - Level 2 layout (auto-calculated from 12 mm roads + viewport scale)
    //
    // Root cause of “route on street”: offset 60 matched thin JSON placeholders, but Level 2
    // roads render at 12 mm (~96 designer units wide). Sidewalks/route at +60 still sit ON the blue stroke.
    //
    // Fine-tune sidewalk distance from road only (route ends stay at street legs 100/900).
    static var intersectionSidewalkExtraMM: CGFloat = 1.3

    static let legInnerBound = 100.0
    static let legOuterBound = 900.0

    /// Designer grid span visible at Level 2 (100…900).
    private static let detailDesignerSpan: Double = 800.0
    /// Approx map draw height in points (screen minus nav bars) at Level 2 zoom.
    private static let detailViewportHeightPoints: CGFloat = 520.0
    private static let designerUnitsPerMM: Double = 15.5

    private static var designerUnitsPerPoint: Double {
        detailDesignerSpan / Double(detailViewportHeightPoints)
    }

    /// Center (500) → sidewalk centerline; must clear 12 mm road half-width on screen.
    static var intersectionSidewalkOffset: Double {
        autoSidewalkOffsetFromRoadEdge() + Double(intersectionSidewalkExtraMM) * designerUnitsPerMM
    }

    private static func mmToDesignerUnits(_ mm: CGFloat) -> Double {
        Double(PhysicalDimensions.mmToPoints(mm)) * designerUnitsPerPoint
    }

    private static func autoSidewalkOffsetFromRoadEdge() -> Double {
        let roadHalf = mmToDesignerUnits(MapIntersectionDetailStyle.roadLineWidthMM / 2)
        let sidewalkHalf = mmToDesignerUnits(MapSidewalkStyle.lineWidthMM / 2)
        let crosswalk = mmToDesignerUnits(MapCrosswalkStyle.lineWidthMM)
        let curbGap = mmToDesignerUnits(1.0)
        return roadHalf + crosswalk + curbGap + sidewalkHalf
    }

    /// Extra setback for stretched Level 1 layout only (not intersection detail).
    static let sidewalkExtraSetbackMM: CGFloat = 3.0
    private static let sidewalkOffsetBaseline = 132.0
    static let sidewalkOffsetX = sidewalkOffsetBaseline + Double(sidewalkExtraSetbackMM) * designerUnitsPerMM

    static func sidewalkOffsetY(yStretchFactor: Double) -> Double {
        yStretchFactor == 1.0 ? sidewalkOffsetX : sidewalkOffsetX / yStretchFactor
    }

    static func remapCoordinate(_ coord: [Double], yStretchFactor: Double = 1.0) -> [Double] {
        guard coord.count >= 2 else { return coord }
        if yStretchFactor == 1.0 {
            return [remapDetailAxis(coord[0]), remapDetailAxis(coord[1])]
        }
        return [remapX(coord[0]), remapY(coord[1], yStretchFactor: yStretchFactor)]
    }

    /// Remaps JSON sidewalk placeholders 440/560 for unstretched intersection view.
    private static func remapDetailAxis(_ value: Double) -> Double {
        if value == 440 { return center - intersectionSidewalkOffset }
        if value == 560 { return center + intersectionSidewalkOffset }
        return value
    }

    private static func remapX(_ value: Double) -> Double {
        if value == 440 { return center - sidewalkOffsetX }
        if value == 560 { return center + sidewalkOffsetX }
        return value
    }

    private static func remapY(_ value: Double, yStretchFactor: Double) -> Double {
        let offset = sidewalkOffsetY(yStretchFactor: yStretchFactor)
        if value == 440 { return center - offset }
        if value == 560 { return center + offset }
        return value
    }
}

enum MapViewAnnouncement {
    static let mapOverview = "Map Overview"

    /// Speaks for sighted users; posts a screen change for VoiceOver.
    static func announce(_ message: String, delay: TimeInterval = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .screenChanged, argument: message)
            } else {
                FeedbackManager.shared.speak(message)
            }
        }
    }
}

enum MapDestinationStyle {
    /// Yellow dot marking the route end / point of interest.
    static let color = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
    static let diameterMM: CGFloat = 6.0
}

enum MapRouteTurnStyle {
    /// Orange dot at a route turn in intersection view.
    static let color = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0)
    static let diameterMM: CGFloat = 5.0
    static let borderWidthMM: CGFloat = 0.4

    /// Hit radius aligned to `RouteTurnAnnotationView` (dot + white border).
    static var hitRadiusPoints: CGFloat {
        PhysicalDimensions.mmToPoints(diameterMM + borderWidthMM) / 2
    }
}

enum MapFixedViewport {
    /// Fixed viewport tuned to a tall/narrow rect so corridor content fills the
    /// iPhone safe area top-to-bottom. Kept in sync with MapDesignerView's window.
    static let edgePadding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    /// Level 1 route map — inset for nav bar + home indicator (matches Level 2 detail).
    static let routeEdgePadding = UIEdgeInsets(top: 72, left: 28, bottom: 40, right: 28)

    /// Vertical-flip pivot used when converting JSON coordinates to latitude.
    /// JSON/designer use a top-down Y axis (y=0 is top) while MapKit latitude is
    /// bottom-up, so we mirror the (already stretched) Y around this value to keep
    /// "JSON top = screen top". Equals the stretched-Y window (syMin + syMax) used
    /// by MapDesignerView (160 + 1160), so the viewport stays identical after the flip.
    static let verticalFlipSum: Double = 1320

    static func defaultMapRect() -> MKMapRect {
        let southwest = MKMapPoint(CLLocationCoordinate2D(latitude: 0.0016, longitude: 0.0027))
        let northeast = MKMapPoint(CLLocationCoordinate2D(latitude: 0.0116, longitude: 0.0073))
        return MKMapRect(
            x: southwest.x,
            y: northeast.y,
            width: northeast.x - southwest.x,
            height: southwest.y - northeast.y
        )
    }

    static func apply(to mapView: MKMapView, edgePadding: UIEdgeInsets? = nil) {
        mapView.setVisibleMapRect(
            defaultMapRect(),
            edgePadding: edgePadding ?? Self.edgePadding,
            animated: false
        )
    }

    /// Same zoom as `apply` but pans to center corridors + route, with nav-bar padding.
    static func applyRouteViewport(
        to mapView: MKMapView,
        features: [MapFeature],
        routes: [RouteFeature] = []
    ) {
        var mapRect = defaultMapRect()
        let corridors = MapVisibleRectHelper.corridorFeatures(from: features)
        let contentRect = MapVisibleRectHelper.tightBoundingMapRect(for: corridors, routes: routes)
        if !contentRect.isNull {
            let dx = contentRect.midX - mapRect.midX
            let dy = contentRect.midY - mapRect.midY
            mapRect = MKMapRect(
                x: mapRect.origin.x + dx,
                y: mapRect.origin.y + dy,
                width: mapRect.width,
                height: mapRect.height
            )
        }
        mapView.setVisibleMapRect(mapRect, edgePadding: routeEdgePadding, animated: false)
    }
}

enum MapIntersectionViewport {
    /// Fixed zoom for Level 2 — symmetric viewport so all intersection legs feel equal length.
    /// Matches unstretched designer grid (100–900) at stretch factor 1.0.
    static let edgePadding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    static let detailEdgePadding = UIEdgeInsets(top: 72, left: 20, bottom: 40, right: 20)

    private static let centerLatitude = (MapFixedViewport.verticalFlipSum - MapIntersectionLayout.center) / 100_000.0
    private static let centerLongitude = MapIntersectionLayout.center / 100_000.0
    /// Half-span in degrees — covers designer 50…950 with margin on each axis.
    private static let halfSpan = 0.0045

    static func apply(to mapView: MKMapView, edgePadding: UIEdgeInsets? = nil) {
        let southwest = MKMapPoint(CLLocationCoordinate2D(
            latitude: centerLatitude - halfSpan,
            longitude: centerLongitude - halfSpan
        ))
        let northeast = MKMapPoint(CLLocationCoordinate2D(
            latitude: centerLatitude + halfSpan,
            longitude: centerLongitude + halfSpan
        ))
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

enum MapFitMode {
    /// Zoom in and crop — fills the screen but can clip content at edges.
    case cover
    /// Zoom out to show everything — centers content with even margins (preferred).
    case contain
}

enum MapVisibleRectHelper {
    static func corridorFeatures(from features: [MapFeature]) -> [MapFeature] {
        features.filter { $0.featureType == "corridor" }
    }

    /// Overlay bounds only — used to center the fixed viewport without inflated padding.
    static func tightBoundingMapRect(for features: [MapFeature], routes: [RouteFeature] = []) -> MKMapRect {
        var mapRect = MKMapRect.null
        for feature in features {
            if let overlay = feature as? MKOverlay {
                mapRect = mapRect.union(overlay.boundingMapRect)
            }
        }
        for route in routes {
            mapRect = mapRect.union(route.boundingMapRect)
        }
        return mapRect
    }

    static func boundingMapRect(for features: [MapFeature], routes: [RouteFeature] = []) -> MKMapRect {
        var mapRect = MKMapRect.null

        func unionCoordinate(_ coordinate: CLLocationCoordinate2D, padding: Double) {
            let point = MKMapPoint(coordinate)
            mapRect = mapRect.union(MKMapRect(
                x: point.x - padding,
                y: point.y - padding,
                width: padding * 2,
                height: padding * 2
            ))
        }

        for feature in features {
            if let overlay = feature as? MKOverlay {
                mapRect = mapRect.union(overlay.boundingMapRect)
            } else if let intersection = feature as? IntersectionFeature {
                unionCoordinate(intersection.coordinate, padding: 600)
            } else if let landmark = feature as? LandmarkFeature {
                let pad = Double(PhysicalDimensions.mmToPoints(MapLandmarkStyle.boxWidthMM * 2))
                unionCoordinate(landmark.coordinate, padding: max(pad, 800))
            }
        }

        for route in routes {
            mapRect = mapRect.union(route.boundingMapRect)
            for endpoint in RouteEndpointFeature.endpoints(for: route) {
                unionCoordinate(endpoint.coordinate, padding: 900)
            }
        }

        return mapRect
    }

    /// Fit the map to all drawn content — contain mode keeps everything on screen.
    static func fitContent(
        _ mapView: MKMapView,
        features: [MapFeature],
        routes: [RouteFeature] = [],
        edgePadding: UIEdgeInsets = UIEdgeInsets(top: 72, left: 28, bottom: 40, right: 28),
        mode: MapFitMode = .contain
    ) {
        fitMapView(mapView, features: features, routes: routes, edgePadding: edgePadding, mode: mode)
    }

    static func fitMapView(
        _ mapView: MKMapView,
        features: [MapFeature],
        routes: [RouteFeature] = [],
        edgePadding: UIEdgeInsets = .zero,
        mode: MapFitMode = .contain
    ) {
        var mapRect = boundingMapRect(for: features, routes: routes)
        guard !mapRect.isNull else { return }

        let viewSize = mapView.bounds.size
        let effectiveWidth = viewSize.width - edgePadding.left - edgePadding.right
        let effectiveHeight = viewSize.height - edgePadding.top - edgePadding.bottom
        guard effectiveWidth > 0, effectiveHeight > 0 else { return }

        let contentAspect = mapRect.width / mapRect.height
        let viewAspect = Double(effectiveWidth / effectiveHeight)

        switch mode {
        case .cover:
            // Fill the drawable area — may crop top/bottom or sides.
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
        case .contain:
            // Show all content — expand visible rect so nothing is clipped.
            if contentAspect > viewAspect {
                let newHeight = mapRect.width / viewAspect
                let dy = (newHeight - mapRect.height) / 2
                mapRect = MKMapRect(
                    x: mapRect.origin.x,
                    y: mapRect.origin.y - dy,
                    width: mapRect.width,
                    height: newHeight
                )
            } else {
                let newWidth = mapRect.height * viewAspect
                let dx = (newWidth - mapRect.width) / 2
                mapRect = MKMapRect(
                    x: mapRect.origin.x - dx,
                    y: mapRect.origin.y,
                    width: newWidth,
                    height: mapRect.height
                )
            }
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

/// Draws exactly three crosswalk stripes — same 2 mm × 6 pt size as the dashed style, evenly spaced.
final class CrosswalkStripeRenderer: MKPolylineRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let polyline = overlay as? MKPolyline, polyline.pointCount >= 2 else { return }

        let mapPoints = UnsafeBufferPointer(start: polyline.points(), count: polyline.pointCount)
        let viewPoints = mapPoints.map { point(for: $0) }

        var polylineLength: CGFloat = 0
        for i in 0..<(viewPoints.count - 1) {
            let dx = viewPoints[i + 1].x - viewPoints[i].x
            let dy = viewPoints[i + 1].y - viewPoints[i].y
            polylineLength += hypot(dx, dy)
        }
        guard polylineLength > 1 else { return }

        let dashLength = MapCrosswalkStyle.dashLengthPoints / zoomScale
        let lineWidth = PhysicalDimensions.mmToPoints(MapCrosswalkStyle.lineWidthMM) / zoomScale
        let stripeCount = CGFloat(MapCrosswalkStyle.stripeCount)
        let totalDash = dashLength * stripeCount
        let gap = max((polylineLength - totalDash) / (stripeCount + 1), 0)

        context.setStrokeColor(MapCrosswalkStyle.color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.butt)

        var offset = gap
        for _ in 0..<MapCrosswalkStyle.stripeCount {
            let stripeStart = pointAlongPolyline(at: offset, points: viewPoints)
            let stripeEnd = pointAlongPolyline(at: offset + dashLength, points: viewPoints)
            if let stripeStart, let stripeEnd {
                context.beginPath()
                context.move(to: stripeStart)
                context.addLine(to: stripeEnd)
                context.strokePath()
            }
            offset += dashLength + gap
        }
    }

    private func pointAlongPolyline(at distance: CGFloat, points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        if distance <= 0 { return points[0] }

        var remaining = distance
        for i in 0..<(points.count - 1) {
            let dx = points[i + 1].x - points[i].x
            let dy = points[i + 1].y - points[i].y
            let segmentLength = hypot(dx, dy)
            guard segmentLength > 0 else { continue }

            if remaining <= segmentLength {
                let t = remaining / segmentLength
                return CGPoint(x: points[i].x + t * dx, y: points[i].y + t * dy)
            }
            remaining -= segmentLength
        }
        return points.last
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
