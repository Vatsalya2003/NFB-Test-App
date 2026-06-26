// DataService.swift
// Session-scoped CSV touch logging for route navigation studies.

import Foundation
import MapKit

@MainActor
class DataService {
    static let shared = DataService()

    private let dataManager = DataManager()
    private var trialStartTime: Date?
    private var currentFileName: String?
    private var currentRouteFile: String?
    private var currentConditionLabel: String?
    private var lastLogTime: Date?
    private let samplingInterval: TimeInterval = 0.1

    private init() {}

    // MARK: - Session Management

    /// Starts a new CSV only when no session is active or the route changed.
    /// Re-entering map overview after intersection detail reuses the same file.
    func startSession(routeTitle: String, routeFile: String) {
        if isSessionActive, currentRouteFile == routeFile {
            setMapOverviewCondition(routeTitle: routeTitle)
            return
        }

        if isSessionActive {
            endSession()
        }

        trialStartTime = Date()
        lastLogTime = nil
        currentRouteFile = routeFile
        currentConditionLabel = "\(routeTitle) - Map Overview"

        let modeName = Self.shortName(forRouteFile: routeFile)
        currentFileName = generateFileName(mode: modeName)
        createFileWithHeader()

        print("📊 Session started: \(currentFileName ?? "unknown").csv")
    }

    func endSession() {
        guard isSessionActive else { return }

        if let fileName = currentFileName {
            print("📊 Session ended and saved: \(fileName).csv")
        }
        trialStartTime = nil
        currentFileName = nil
        currentRouteFile = nil
        currentConditionLabel = nil
        lastLogTime = nil
    }

    func setMapOverviewCondition(routeTitle: String) {
        currentConditionLabel = "\(routeTitle) - Map Overview"
    }

    func setIntersectionCondition(routeTitle: String, intersectionName: String) {
        currentConditionLabel = "\(routeTitle) - Intersection View (\(intersectionName))"
    }

    var isSessionActive: Bool {
        currentFileName != nil
    }

    // MARK: - Touch Logging

    @discardableResult
    func logTouchEvent(
        location: CGPoint,
        eventType: TouchEventType,
        elementName: String
    ) -> Bool {
        guard let fileName = currentFileName,
              let condition = currentConditionLabel,
              let trialStart = trialStartTime else {
            return false
        }

        let now = Date()

        if eventType == .touchMove {
            if let lastTime = lastLogTime, now.timeIntervalSince(lastTime) < samplingInterval {
                return false
            }
        }

        let elapsedSeconds = now.timeIntervalSince(trialStart)
        let data = InteractionData(
            timestamp: Self.currentTimestamp(),
            trialTime: Self.formatTrialTime(elapsedSeconds),
            touchEvent: eventType,
            objectType: elementName,
            touchX: location.x,
            touchY: location.y,
            condition: condition
        )

        dataManager.appendToCSV(
            dataItem: data,
            filePath: dataManager.filePath(path: fileName).path
        )

        lastLogTime = now

        if eventType != .touchMove {
            print("📝 \(eventType.rawValue): \(elementName) at (\(String(format: "%.1f", location.x)), \(String(format: "%.1f", location.y)))")
        }

        return true
    }

    func logTouchEvent(
        at point: CGPoint,
        in mapView: MKMapView,
        eventType: TouchEventType,
        context: MapTouchLoggingContext,
        features: [MapFeature],
        routes: [RouteFeature],
        routeEndpoints: [RouteEndpointFeature],
        landmarks: [LandmarkFeature] = [],
        routeTurns: [RouteTurnFeature] = []
    ) {
        let elementName = MapTouchElementDetector.elementName(
            at: point,
            in: mapView,
            context: context,
            features: features,
            routes: routes,
            routeEndpoints: routeEndpoints,
            landmarks: landmarks,
            routeTurns: routeTurns
        )
        logTouchEvent(location: point, eventType: eventType, elementName: elementName)
    }

    // MARK: - File Management

    func getAllLogFiles() -> [URL] {
        dataManager.getAllCSVFiles()
    }

    func deleteFile(at url: URL) -> Bool {
        dataManager.deleteFile(at: url)
    }

    func shareFile(at url: URL) {
        dataManager.shareFile(url: url)
    }

    func getFileSize(at url: URL) -> String {
        dataManager.getFileSize(at: url)
    }

    func hasCollectedData() -> Bool {
        !dataManager.getAllCSVFiles().isEmpty
    }

    // MARK: - Private

    private func createFileWithHeader() {
        guard let fileName = currentFileName else { return }

        let filePath = dataManager.filePath(path: fileName).path
        let fileURL = URL(fileURLWithPath: filePath)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = "Time Stamp,Trial Time,Touch Event,Object Type,Touch X,Touch Y,Condition\n"
            do {
                try header.write(to: fileURL, atomically: true, encoding: .utf8)
                print("📁 Created log file: \(fileName).csv")
            } catch {
                print("Error creating CSV file: \(error.localizedDescription)")
            }
        }
    }

    private func generateFileName(mode: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmmss"
        let timeString = timeFormatter.string(from: Date())

        let sessionNumber = dataManager.getNextSessionNumber(for: mode, date: dateString)
        return "\(mode)_\(dateString)_\(timeString)_v\(sessionNumber)"
    }

    private static func shortName(forRouteFile routeFile: String) -> String {
        switch routeFile {
        case "route_jwmarriott_to_marriott":
            return "JWToMarriott"
        case "route_marriott_to_jwmarriott":
            return "MarriottToJW"
        default:
            return routeFile.replacingOccurrences(of: "route_", with: "")
        }
    }

    private static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    private static func formatTrialTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let deciseconds = Int((seconds - Double(totalSeconds)) * 10)
        return String(format: "%02d:%02d.%d", minutes, secs, deciseconds)
    }
}
