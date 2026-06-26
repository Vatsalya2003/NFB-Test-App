// DataManager.swift
// CSV file I/O for touch telemetry logs (Documents directory).

import Foundation
import UIKit

enum TouchEventType: String {
    case touchDown = "Touch Down"
    case touchMove = "Touch Move"
    case touchUp = "Touch Up"
}

struct InteractionData {
    var timestamp: String
    var trialTime: String
    var touchEvent: TouchEventType
    var objectType: String
    var touchX: CGFloat
    var touchY: CGFloat
    var condition: String
}

class DataManager {

    func getAllCSVFiles() -> [URL] {
        let documentsUrl = getDocumentsDirectory()

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsUrl,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            return fileURLs
                .filter { $0.pathExtension == "csv" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            print("Error listing files: \(error.localizedDescription)")
            return []
        }
    }

    func deleteFile(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            print("Error deleting file: \(error.localizedDescription)")
            return false
        }
    }

    func getFileSize(at url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            print("Error getting file size: \(error.localizedDescription)")
        }
        return "Unknown"
    }

    func getNextSessionNumber(for mode: String, date: String) -> Int {
        let files = getAllCSVFiles()
        let prefix = "\(mode)_\(date)"

        var maxVersion = 0
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            if name.hasPrefix(prefix) {
                if let vIndex = name.lastIndex(of: "v"),
                   let versionStr = name.suffix(from: name.index(after: vIndex)).components(separatedBy: CharacterSet.decimalDigits.inverted).first,
                   let version = Int(versionStr) {
                    maxVersion = max(maxVersion, version)
                }
            }
        }

        return maxVersion + 1
    }

    func shareFile(url: URL) {
        guard let windowScene = getActiveWindowScene(),
              let rootVC = windowScene.windows.first?.rootViewController else {
            print("Could not find root view controller")
            return
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        rootVC.present(activityVC, animated: true)
    }

    func appendToCSV(dataItem: InteractionData, filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = "Time Stamp,Trial Time,Touch Event,Object Type,Touch X,Touch Y,Condition\n"
            do {
                try header.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Error writing header to CSV file: \(error.localizedDescription)")
            }
        }

        do {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()

            let csvLine = "\(dataItem.timestamp),\(dataItem.trialTime),\(dataItem.touchEvent.rawValue),\(dataItem.objectType),\(String(format: "%.1f", dataItem.touchX)),\(String(format: "%.1f", dataItem.touchY)),\(dataItem.condition)\n"

            if let lineData = csvLine.data(using: .utf8) {
                fileHandle.write(lineData)
            }

            fileHandle.closeFile()
        } catch {
            print("Error opening file for appending: \(error.localizedDescription)")
        }
    }

    func filePath(path: String) -> URL {
        let fileName = "\(path).csv"

        do {
            let directory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            return directory.appendingPathComponent(fileName)
        } catch {
            print("Error obtaining document directory path: \(error.localizedDescription)")
            return URL(string: "")!
        }
    }

    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func getActiveWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first
    }
}
