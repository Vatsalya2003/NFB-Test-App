import Foundation

class MapDataLoader {
    // Stretch factor for vertical map stretching (Y direction only)
    // 1.0 = no stretch (original size)
    // 1.5 = 50% taller (1.5x)
    // 2.0 = twice as tall (2x) - previous default
    // 2.5 = 2.5x taller
    // 3.0 = 3x taller
    // Higher values = even taller map
    static var stretchFactor: Double = 2.6
    
    static func loadMapFeatures(from filename: String) -> [MapFeature] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return []
        }
        
        var mapFeatures: [MapFeature] = []
        
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
                    // Stretch corridor coordinates vertically
                    let stretchedCoords = stretchCoordinates(coords, stretchFactor: stretchFactor)
                    let corridor = CorridorFeature(id: id, coordinates: stretchedCoords, properties: properties)
                    mapFeatures.append(corridor)
                }
                
            case "landmark":
                if let coords = coordinates as? [Double] {
                    // Stretch landmark coordinates vertically
                    let stretchedCoords = stretchCoordinate(coords, stretchFactor: stretchFactor)
                    let landmark = LandmarkFeature(id: id, coordinates: stretchedCoords, properties: properties)
                    mapFeatures.append(landmark)
                }
                
            case "intersection":
                if let coords = coordinates as? [Double] {
                    // Stretch intersection coordinates vertically
                    let stretchedCoords = stretchCoordinate(coords, stretchFactor: stretchFactor)
                    let intersection = IntersectionFeature(id: id, coordinates: stretchedCoords, properties: properties)
                    mapFeatures.append(intersection)
                }
                
            default:
                break
            }
        }
        
        return mapFeatures
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
