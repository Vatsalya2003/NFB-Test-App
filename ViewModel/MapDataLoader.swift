// MapDataLoader.swift
// Reads testMap_Condition1.json and creates corridor / intersection / landmark objects.
// Applies 2.6x Y stretch so the map matches our fixed viewport layout.

import Foundation

class MapDataLoader {
    // Stretch factor for vertical map stretching (Y direction only)
    // 1.0 = no stretch (original size)
    // 1.5 = 50% taller (1.5x)
    // 2.0 = twice as tall (2x) - previous default
    // 2.5 = 2.5x taller
    // 3.0 = 3x taller
    // Higher values = even taller map
    // Level 1 base map stretch. Level 2 intersection detail uses stretchFactor: 1.0 (uniform legs).
    static var stretchFactor: Double = 2.6

    /// Stretch applied to Level 2 intersection detail JSON — no vertical elongation.
    static let intersectionDetailStretchFactor: Double = 1.0
    
    static func loadMapFeatures(
        from filename: String,
        mirror180: Bool = false,
        routeFile: String? = nil,
        includeLandmarks: Bool = true,
        stretchFactor: Double? = nil
    ) -> [MapFeature] {
        let stretch = stretchFactor ?? Self.stretchFactor
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return []
        }
        
        var mapFeatures: [MapFeature] = []
        let isIntersectionDetail = filename.contains("intersection_") && filename.contains("_detail")
        
        for featureJSON in features {
            guard let id = featureJSON["id"] as? String,
                  let type = featureJSON["type"] as? String,
                  let geometry = featureJSON["geometry"] as? [String: Any],
                  let coordinates = geometry["coordinates"],
                  let properties = featureJSON["properties"] as? [String: Any] else {
                continue
            }
            
            switch type {
            case "corridor":
                if let coords = coordinates as? [[Double]] {
                    let mirroredCoords = mirror180 ? coords.map { MapOrientation.mirrorDesignerCoordinate($0) } : coords
                    let stretchedCoords = stretchCoordinates(mirroredCoords, stretchFactor: stretch)
                    let corridor = CorridorFeature(id: id, coordinates: stretchedCoords, properties: properties)
                    mapFeatures.append(corridor)
                }
                
            case "landmark":
                guard includeLandmarks else { continue }
                if let coords = coordinates as? [Double] {
                    let mirroredCoords = mirror180 ? MapOrientation.mirrorDesignerCoordinate(coords) : coords
                    let stretchedCoords = stretchCoordinate(mirroredCoords, stretchFactor: stretch)
                    let props = landmarkProperties(properties, routeFile: routeFile)
                    let landmark = LandmarkFeature(id: id, coordinates: stretchedCoords, properties: props)
                    mapFeatures.append(landmark)
                }
                
            case "intersection":
                guard !isIntersectionDetail else { continue }
                if let coords = coordinates as? [Double] {
                    let mirroredCoords = mirror180 ? MapOrientation.mirrorDesignerCoordinate(coords) : coords
                    let stretchedCoords = stretchCoordinate(mirroredCoords, stretchFactor: stretch)
                    let intersection = IntersectionFeature(id: id, coordinates: stretchedCoords, properties: properties)
                    mapFeatures.append(intersection)
                }

            case "sidewalk":
                if let coords = coordinates as? [[Double]] {
                    let mirroredCoords = mirror180 ? coords.map { MapOrientation.mirrorDesignerCoordinate($0) } : coords
                    let layoutCoords = mirroredCoords.map { MapIntersectionLayout.remapCoordinate($0, yStretchFactor: stretch) }
                    let stretchedCoords = stretchCoordinates(layoutCoords, stretchFactor: stretch)
                    let sidewalk = SidewalkFeature(id: id, coordinates: stretchedCoords, properties: properties)
                    mapFeatures.append(sidewalk)
                }

            case "crosswalk":
                if let coords = coordinates as? [[Double]] {
                    let mirroredCoords = mirror180 ? coords.map { MapOrientation.mirrorDesignerCoordinate($0) } : coords
                    let layoutCoords = mirroredCoords.map { MapIntersectionLayout.remapCoordinate($0, yStretchFactor: stretch) }
                    let stretchedCoords = stretchCoordinates(layoutCoords, stretchFactor: stretch)
                    let crosswalk = CrosswalkFeature(id: id, coordinates: stretchedCoords, properties: properties)
                    mapFeatures.append(crosswalk)
                }

            default:
                break
            }
        }
        
        return mapFeatures
    }

    private static func landmarkProperties(_ properties: [String: Any], routeFile: String?) -> [String: Any] {
        guard let routeFile, MapOrientation.shouldFlipLandmarkSide(forRouteFile: routeFile) else {
            return properties
        }
        var props = properties
        if let side = props["side"] as? String {
            props["side"] = MapOrientation.flippedLandmarkSide(side)
        }
        if let announcement = props["announcement"] as? String {
            props["announcement"] = MapOrientation.flippedLandmarkAnnouncement(announcement)
        }
        return props
    }
    
    // Helper function to stretch a single coordinate point (for landmarks and intersections)
    private static func stretchCoordinate(_ coord: [Double], stretchFactor: Double) -> [Double] {
        guard coord.count >= 2 else { return coord }
        let centerY = 500.0
        let x = coord[0]
        let y = coord[1]
        let stretchedY = centerY + (y - centerY) * stretchFactor
        return [x, stretchedY]
    }
    
    // Helper function to stretch multiple coordinates (for corridors)
    private static func stretchCoordinates(_ coords: [[Double]], stretchFactor: Double) -> [[Double]] {
        return coords.map { coord in
            stretchCoordinate(coord, stretchFactor: stretchFactor)
        }
    }
}
