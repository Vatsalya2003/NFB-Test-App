// RouteMapData.swift
// Loads route_*.json files and applies the same Y stretch as the base map.

import Foundation

/// Manages route data loading and parsing
class RouteMapDataLoader {
    
    // Same stretch factor as base map
    static var stretchFactor: Double = 2.6
    
    /// Load route features from JSON
    static func loadRouteFeatures(from filename: String) -> [RouteFeature] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["routes"] as? [[String: Any]] else {
            print("Failed to load route file: \(filename)")
            return []
        }
        
        var routes: [RouteFeature] = []
        
        for routeJSON in features {
            guard let id = routeJSON["id"] as? String,
                  let geometry = routeJSON["geometry"] as? [String: Any],
                  let coordinates = geometry["coordinates"] as? [[Double]],
                  let properties = routeJSON["properties"] as? [String: Any] else {
                continue
            }
            
            // Stretch route coordinates to match base map
            let stretchedCoords = stretchCoordinates(coordinates, stretchFactor: stretchFactor)
            let route = RouteFeature(id: id, coordinates: stretchedCoords, properties: properties)
            routes.append(route)
        }
        
        return routes
    }
    
    /// Load complete map with routes (base map + route overlay)
    static func loadMapWithRoutes(baseMap: String, routeFile: String) -> (features: [MapFeature], routes: [RouteFeature]) {
        let baseFeatures = MapDataLoader.loadMapFeatures(from: baseMap)
        let routes = loadRouteFeatures(from: routeFile)
        return (baseFeatures, routes)
    }
    
    // MARK: - Coordinate Stretching (same as MapDataLoader)
    
    private static func stretchCoordinates(_ coords: [[Double]], stretchFactor: Double) -> [[Double]] {
        return coords.map { coord in
            stretchCoordinate(coord, stretchFactor: stretchFactor)
        }
    }
    
    private static func stretchCoordinate(_ coord: [Double], stretchFactor: Double) -> [Double] {
        guard coord.count >= 2 else { return coord }
        let centerY = 500.0
        let x = coord[0]
        let y = coord[1]
        let stretchedY = centerY + (y - centerY) * stretchFactor
        return [x, stretchedY]
    }
}
