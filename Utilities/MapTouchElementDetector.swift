// MapTouchElementDetector.swift
// Hit-testing for CSV touch logs — mirrors RouteMapView / IntersectionDetailMapView coordinators.

import MapKit

enum MapTouchLoggingContext {
    case routeOverview
    case intersectionDetail
}

enum MapTouchElementDetector {

    static func elementName(
        at point: CGPoint,
        in mapView: MKMapView,
        context: MapTouchLoggingContext,
        features: [MapFeature],
        routes: [RouteFeature],
        routeEndpoints: [RouteEndpointFeature],
        landmarks: [LandmarkFeature] = [],
        routeTurns: [RouteTurnFeature] = []
    ) -> String {
        switch context {
        case .routeOverview:
            return elementNameForRouteOverview(
                at: point,
                in: mapView,
                features: features,
                routes: routes,
                routeEndpoints: routeEndpoints,
                landmarks: landmarks
            )
        case .intersectionDetail:
            return elementNameForIntersectionDetail(
                at: point,
                in: mapView,
                features: features,
                routes: routes,
                routeEndpoints: routeEndpoints,
                routeTurns: routeTurns
            )
        }
    }

    // MARK: - Route overview (Level 1)

    private static func elementNameForRouteOverview(
        at point: CGPoint,
        in mapView: MKMapView,
        features: [MapFeature],
        routes: [RouteFeature],
        routeEndpoints: [RouteEndpointFeature],
        landmarks: [LandmarkFeature]
    ) -> String {
        if let endpoint = routeEndpoint(at: point, in: mapView, endpoints: routeEndpoints) {
            return endpointLogName(endpoint)
        }
        if let landmark = landmark(at: point, in: mapView, landmarks: landmarks) {
            return landmark.properties["name"] as? String ?? "Landmark"
        }
        if let intersection = intersection(at: point, in: mapView, features: features) {
            return intersection.properties["name"] as? String ?? "Intersection"
        }
        if routeHit(at: point, in: mapView, routes: routes) != nil {
            return "Route"
        }
        if let corridor = corridor(
            at: point,
            in: mapView,
            features: features,
            lineWidthMM: MapRoadStyle.lineWidthMM
        ) {
            return corridor.properties["name"] as? String ?? "Corridor"
        }
        return "Background"
    }

    // MARK: - Intersection detail (Level 2)

    private static func elementNameForIntersectionDetail(
        at point: CGPoint,
        in mapView: MKMapView,
        features: [MapFeature],
        routes: [RouteFeature],
        routeEndpoints: [RouteEndpointFeature],
        routeTurns: [RouteTurnFeature]
    ) -> String {
        if routeTurn(at: point, in: mapView, turns: routeTurns) != nil {
            return "Route Turn"
        }
        if let endpoint = routeEndpoint(at: point, in: mapView, endpoints: routeEndpoints) {
            return endpointLogName(endpoint)
        }
        if let intersection = intersection(at: point, in: mapView, features: features) {
            return intersection.properties["name"] as? String ?? "Intersection"
        }
        if route(at: point, in: mapView, routes: routes) != nil {
            return "Route"
        }
        if sidewalk(at: point, in: mapView, features: features) != nil {
            return streetName(at: point, in: mapView, features: features) ?? "Sidewalk"
        }
        if let corridor = corridor(
            at: point,
            in: mapView,
            features: features,
            lineWidthMM: MapIntersectionDetailStyle.roadLineWidthMM
        ) {
            return corridor.properties["name"] as? String ?? "Road"
        }
        if crosswalk(at: point, in: mapView, features: features) != nil {
            return "Crosswalk"
        }
        return "Background"
    }

    private static func endpointLogName(_ endpoint: RouteEndpointFeature) -> String {
        let name = endpoint.properties["name"] as? String ?? "Location"
        switch endpoint.kind {
        case .departure:
            return "Route Start - \(name)"
        case .destination:
            return "Route End - \(name)"
        }
    }

    // MARK: - Hit testing

    private static func routeEndpoint(
        at point: CGPoint,
        in mapView: MKMapView,
        endpoints: [RouteEndpointFeature]
    ) -> RouteEndpointFeature? {
        let radius = max(PhysicalDimensions.mmToPoints(MapDestinationStyle.diameterMM) / 2, 24)
        for feature in endpoints {
            let center = mapView.convert(feature.coordinate, toPointTo: nil)
            if hypot(point.x - center.x, point.y - center.y) <= radius {
                return feature
            }
        }
        return nil
    }

    private static func routeTurn(
        at point: CGPoint,
        in mapView: MKMapView,
        turns: [RouteTurnFeature]
    ) -> RouteTurnFeature? {
        let radius = max(PhysicalDimensions.mmToPoints(MapRouteTurnStyle.diameterMM) / 2, 32)
        for turn in turns {
            let center = mapView.convert(turn.coordinate, toPointTo: nil)
            if hypot(point.x - center.x, point.y - center.y) <= radius {
                return turn
            }
        }
        return nil
    }

    private static func landmark(
        at point: CGPoint,
        in mapView: MKMapView,
        landmarks: [LandmarkFeature]
    ) -> LandmarkFeature? {
        let anchorThreshold: CGFloat = 30
        let boxThreshold = max(PhysicalDimensions.mmToPoints(MapLandmarkStyle.boxWidthMM) / 2, 22)
        for feature in landmarks {
            let anchor = mapView.convert(feature.coordinate, toPointTo: nil)
            let offset = MapLandmarkStyle.sideOffset(feature.side)
            let box = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
            if hypot(point.x - anchor.x, point.y - anchor.y) <= anchorThreshold
                || hypot(point.x - box.x, point.y - box.y) <= boxThreshold {
                return feature
            }
        }
        return nil
    }

    private static func intersection(
        at point: CGPoint,
        in mapView: MKMapView,
        features: [MapFeature]
    ) -> IntersectionFeature? {
        let half = PhysicalDimensions.mmToPoints(MapIntersectionStyle.sideMM) / 2
        let threshold = max(half, 22)
        for feature in features where feature.featureType == "intersection" {
            guard let intersection = feature as? IntersectionFeature else { continue }
            let center = mapView.convert(intersection.coordinate, toPointTo: nil)
            if hypot(point.x - center.x, point.y - center.y) <= threshold {
                return intersection
            }
        }
        return nil
    }

    private static func routeHit(
        at point: CGPoint,
        in mapView: MKMapView,
        routes: [RouteFeature]
    ) -> RouteFeature? {
        let threshold = max(PhysicalDimensions.mmToPoints(MapRouteStyle.lineWidthMM) / 2, 22)
        var best: (route: RouteFeature, distance: CGFloat)?

        for route in routes {
            for i in 0..<(route.coordinates.count - 1) {
                let start = mapView.convert(route.coordinates[i], toPointTo: nil)
                let end = mapView.convert(route.coordinates[i + 1], toPointTo: nil)
                let distance = distanceFromPoint(point, toLineFrom: start, to: end)
                if distance < threshold, best == nil || distance < best!.distance {
                    best = (route, distance)
                }
            }
        }

        return best?.route
    }

    private static func route(
        at point: CGPoint,
        in mapView: MKMapView,
        routes: [RouteFeature]
    ) -> RouteFeature? {
        routeHit(at: point, in: mapView, routes: routes)
    }

    private static func corridor(
        at point: CGPoint,
        in mapView: MKMapView,
        features: [MapFeature],
        lineWidthMM: CGFloat
    ) -> CorridorFeature? {
        let threshold = PhysicalDimensions.mmToPoints(lineWidthMM) / 2
        for feature in features where feature.featureType == "corridor" {
            guard let corridor = feature as? CorridorFeature else { continue }
            for i in 0..<(corridor.coordinates.count - 1) {
                let start = mapView.convert(corridor.coordinates[i], toPointTo: nil)
                let end = mapView.convert(corridor.coordinates[i + 1], toPointTo: nil)
                if distanceFromPoint(point, toLineFrom: start, to: end) < threshold {
                    return corridor
                }
            }
        }
        return nil
    }

    private static func sidewalk(
        at point: CGPoint,
        in mapView: MKMapView,
        features: [MapFeature]
    ) -> SidewalkFeature? {
        let threshold = PhysicalDimensions.mmToPoints(MapSidewalkStyle.lineWidthMM) / 2
        for feature in features where feature.featureType == "sidewalk" {
            guard let sw = feature as? SidewalkFeature else { continue }
            for i in 0..<(sw.coordinates.count - 1) {
                let start = mapView.convert(sw.coordinates[i], toPointTo: nil)
                let end = mapView.convert(sw.coordinates[i + 1], toPointTo: nil)
                if distanceFromPoint(point, toLineFrom: start, to: end) < threshold {
                    return sw
                }
            }
        }
        return nil
    }

    private static func crosswalk(
        at point: CGPoint,
        in mapView: MKMapView,
        features: [MapFeature]
    ) -> CrosswalkFeature? {
        let threshold = PhysicalDimensions.mmToPoints(MapCrosswalkStyle.lineWidthMM)
        for feature in features where feature.featureType == "crosswalk" {
            guard let cw = feature as? CrosswalkFeature else { continue }
            for i in 0..<(cw.coordinates.count - 1) {
                let start = mapView.convert(cw.coordinates[i], toPointTo: nil)
                let end = mapView.convert(cw.coordinates[i + 1], toPointTo: nil)
                if distanceFromPoint(point, toLineFrom: start, to: end) < threshold {
                    return cw
                }
            }
        }
        return nil
    }

    private static func streetName(
        at point: CGPoint,
        in mapView: MKMapView,
        features: [MapFeature]
    ) -> String? {
        if let corridor = corridor(
            at: point,
            in: mapView,
            features: features,
            lineWidthMM: MapIntersectionDetailStyle.roadLineWidthMM
        ), let name = corridor.properties["name"] as? String {
            return name
        }

        let roadHalf = PhysicalDimensions.mmToPoints(MapIntersectionDetailStyle.roadLineWidthMM) / 2
        let lookupDistance = roadHalf + PhysicalDimensions.mmToPoints(14)
        if let corridor = nearestCorridor(to: point, in: mapView, features: features, maxDistance: lookupDistance),
           let name = corridor.properties["name"] as? String {
            return name
        }
        return nil
    }

    private static func nearestCorridor(
        to point: CGPoint,
        in mapView: MKMapView,
        features: [MapFeature],
        maxDistance: CGFloat
    ) -> CorridorFeature? {
        var closest: (corridor: CorridorFeature, distance: CGFloat)?
        for feature in features where feature.featureType == "corridor" {
            guard let corridor = feature as? CorridorFeature else { continue }
            for i in 0..<(corridor.coordinates.count - 1) {
                let start = mapView.convert(corridor.coordinates[i], toPointTo: nil)
                let end = mapView.convert(corridor.coordinates[i + 1], toPointTo: nil)
                let distance = distanceFromPoint(point, toLineFrom: start, to: end)
                if distance <= maxDistance {
                    if closest == nil || distance < closest!.distance {
                        closest = (corridor, distance)
                    }
                }
            }
        }
        return closest?.corridor
    }

    private static func distanceFromPoint(_ point: CGPoint, toLineFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projX = start.x + t * dx
        let projY = start.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}
