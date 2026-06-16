// MapDesignerView.swift
// On-device tool to draw corridors on a grid and export testMap_Condition1.json.
// Uses SwiftUI Canvas (no MapKit). Preview matches the live app's stretch + viewport.

import SwiftUI

/// A model representing a corridor while it is being designed on-canvas.
/// Points are stored in the 0...1000 canvas coordinate space.
private struct DesignCorridor: Identifiable {
    let id = UUID()
    var jsonId: String
    var name: String
    var points: [CGPoint]
}

/// A pure-SwiftUI visual designer for building `testMap_Condition1.json` on device.
///
/// - Tap "Add Corridor", then tap to drop points; double-tap to finish.
/// - Tap an existing corridor to select it and rename it.
/// - Drag the circular endpoint handles to reshape a corridor.
/// - "Export JSON" prints the full FeatureCollection to the Xcode console.
struct MapDesignerView: View {
    @State private var corridors: [DesignCorridor] = []
    @State private var selectedID: DesignCorridor.ID?
    @State private var isDrawing = false
    @State private var currentPoints: [CGPoint] = []
    @State private var draggingHandle: (corridor: Int, point: Int)?
    @State private var lastTapDate = Date.distantPast
    @State private var lastTapPoint = CGPoint.zero
    @State private var corridorCounter = 0

    private let roadColor = Color(red: 0x02 / 255.0, green: 0x3e / 255.0, blue: 0x8a / 255.0)
    private let background = Color(red: 0.118, green: 0.118, blue: 0.118)

    // MARK: - Live-app transform (mirrors RouteMapView rendering)
    //
    // The app applies a ×2.6 vertical stretch around y=500 and then shows a
    // fixed viewport. The canvas reproduces both so what you draw is exactly
    // what renders on device.
    private let stretchFactor: CGFloat = 2.6
    private let centerY: CGFloat = 500
    private let xMin: CGFloat = 270        // visible raw-X window (lng 0.0027…0.0073)
    private let xMax: CGFloat = 730
    private let syMin: CGFloat = 160       // visible stretched-Y window (lat 0.0016…0.0116)
    private let syMax: CGFloat = 1160

    /// Lowest raw-Y that stays inside the viewport (after un-stretching).
    private var yMin: CGFloat { centerY + (syMin - centerY) / stretchFactor }
    /// Highest raw-Y that stays inside the viewport (after un-stretching).
    private var yMax: CGFloat { centerY + (syMax - centerY) / stretchFactor }
    /// Width-to-height ratio of the fixed viewport rect.
    private var viewportAspect: CGFloat { (xMax - xMin) / (syMax - syMin) }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let size = canvasSize(in: geo.size)
                designCanvas(size: size)
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            controls
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("Map Designer")
        .navigationBarTitleDisplayMode(.inline)
        .disableInteractivePopGesture()
    }

    /// Fits an aspect-correct canvas (matching the device viewport) into the available space.
    private func canvasSize(in available: CGSize) -> CGSize {
        var w = available.width
        var h = w / viewportAspect
        if h > available.height {
            h = available.height
            w = h * viewportAspect
        }
        return CGSize(width: w, height: h)
    }

    // MARK: - Canvas

    private func designCanvas(size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            drawGrid(ctx, canvasSize)
            drawCorridors(ctx, canvasSize)
            drawInProgress(ctx, canvasSize)
            drawHandles(ctx, canvasSize)
        }
        .background(background)
        .contentShape(Rectangle())
        .gesture(canvasGesture(size: size))
    }

    private func drawGrid(_ ctx: GraphicsContext, _ size: CGSize) {
        let divisions = 10
        let stepX = size.width / CGFloat(divisions)
        let stepY = size.height / CGFloat(divisions)
        var grid = Path()
        for i in 0...divisions {
            let x = CGFloat(i) * stepX
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            let y = CGFloat(i) * stepY
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)

        let border = Path(CGRect(origin: .zero, size: size))
        ctx.stroke(border, with: .color(.white.opacity(0.3)), lineWidth: 1.5)
    }

    private func drawCorridors(_ ctx: GraphicsContext, _ size: CGSize) {
        for c in corridors where c.points.count >= 2 {
            var path = Path()
            path.move(to: screen(c.points[0], size))
            for pt in c.points.dropFirst() {
                path.addLine(to: screen(pt, size))
            }
            let isSelected = c.id == selectedID
            ctx.stroke(
                path,
                with: .color(isSelected ? .yellow : roadColor),
                style: StrokeStyle(lineWidth: isSelected ? 10 : 8, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawInProgress(_ ctx: GraphicsContext, _ size: CGSize) {
        guard !currentPoints.isEmpty else { return }
        var path = Path()
        path.move(to: screen(currentPoints[0], size))
        for pt in currentPoints.dropFirst() {
            path.addLine(to: screen(pt, size))
        }
        ctx.stroke(
            path,
            with: .color(.green),
            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: [10, 6])
        )
        for pt in currentPoints {
            let p = screen(pt, size)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.green))
        }
    }

    private func drawHandles(_ ctx: GraphicsContext, _ size: CGSize) {
        for c in corridors {
            for pt in c.points {
                let p = screen(pt, size)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(roadColor))
            }
        }
    }

    // MARK: - Gestures

    private func canvasGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if let dh = draggingHandle {
                    if dh.corridor >= 0 {
                        corridors[dh.corridor].points[dh.point] = clampRaw(rawPoint(value.location, size))
                    }
                    return
                }
                let moved = hypot(value.translation.width, value.translation.height)
                guard moved > 8 else { return }
                if let hit = handleHit(at: value.startLocation, size: size) {
                    draggingHandle = hit
                    selectedID = corridors[hit.corridor].id
                    corridors[hit.corridor].points[hit.point] = clampRaw(rawPoint(value.location, size))
                } else {
                    draggingHandle = (corridor: -1, point: -1)
                }
            }
            .onEnded { value in
                let wasDrag = draggingHandle != nil
                draggingHandle = nil
                if wasDrag { return }
                handleTap(at: value.location, size: size)
            }
    }

    private func handleTap(at loc: CGPoint, size: CGSize) {
        let now = Date()
        if now.timeIntervalSince(lastTapDate) < 0.35,
           hypot(loc.x - lastTapPoint.x, loc.y - lastTapPoint.y) < 30 {
            finishDrawing()
            lastTapDate = .distantPast
            return
        }
        lastTapDate = now
        lastTapPoint = loc

        if isDrawing {
            currentPoints.append(clampRaw(rawPoint(loc, size)))
        } else {
            selectedID = nearestCorridor(to: loc, size: size)
        }
    }

    // MARK: - Actions

    private func toggleDrawing() {
        if isDrawing {
            finishDrawing()
        } else {
            isDrawing = true
            currentPoints = []
            selectedID = nil
        }
    }

    private func finishDrawing() {
        defer {
            currentPoints = []
            isDrawing = false
        }
        guard isDrawing, currentPoints.count >= 2 else { return }
        corridorCounter += 1
        let corridor = DesignCorridor(
            jsonId: "c_\(corridorCounter)",
            name: "Road \(corridorCounter)",
            points: currentPoints
        )
        corridors.append(corridor)
        selectedID = corridor.id
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        corridors.removeAll { $0.id == id }
        selectedID = nil
    }

    private func exportJSON() {
        var features: [String] = []
        for c in corridors where c.points.count >= 2 {
            let coords = c.points
                .map { "[\(Int($0.x.rounded())), \(Int($0.y.rounded()))]" }
                .joined(separator: ", ")
            features.append("""
                {
                  "id": "\(c.jsonId)",
                  "type": "corridor",
                  "geometry": {
                    "type": "LineString",
                    "coordinates": [\(coords)]
                  },
                  "properties": {
                    "name": "\(c.name)",
                    "level": 1,
                    "accessible": true
                  }
                }
            """)
        }
        let json = """
        {
          "type": "FeatureCollection",
          "bounds": { "width": 1000, "height": 1000 },
          "features": [
        \(features.joined(separator: ",\n"))
          ]
        }
        """
        print("=================== testMap_Condition1.json ===================")
        print(json)
        print("===============================================================")
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if let binding = selectedBinding {
                HStack {
                    Text("Name")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    TextField("Corridor name", text: binding.name)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                Button(action: toggleDrawing) {
                    Label(isDrawing ? "Finish (\(currentPoints.count))" : "Add Corridor",
                          systemImage: isDrawing ? "checkmark.circle.fill" : "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isDrawing ? .green : .blue)

                Button(role: .destructive, action: deleteSelected) {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(selectedID == nil)

                Button(action: exportJSON) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Text(isDrawing
                 ? "Tap to drop points · double-tap to finish"
                 : "Canvas = exact device view (×2.6 stretch). Tap to select · drag handles to reshape.")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(red: 0.15, green: 0.15, blue: 0.15))
    }

    private var selectedBinding: Binding<DesignCorridor>? {
        guard let id = selectedID,
              let index = corridors.firstIndex(where: { $0.id == id }) else { return nil }
        return $corridors[index]
    }

    // MARK: - Geometry helpers

    /// Raw design coordinate -> screen point (applies ×2.6 stretch + viewport window).
    private func screen(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        let sy = centerY + (p.y - centerY) * stretchFactor
        let x = (p.x - xMin) / (xMax - xMin) * size.width
        let y = (sy - syMin) / (syMax - syMin) * size.height
        return CGPoint(x: x, y: y)
    }

    /// Screen point -> raw design coordinate (inverse of `screen`).
    private func rawPoint(_ s: CGPoint, _ size: CGSize) -> CGPoint {
        let x = xMin + (s.x / size.width) * (xMax - xMin)
        let sy = syMin + (s.y / size.height) * (syMax - syMin)
        let y = centerY + (sy - centerY) / stretchFactor
        return CGPoint(x: x, y: y)
    }

    /// Keeps a raw point inside the on-screen (viewport) window.
    private func clampRaw(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, xMin), xMax), y: min(max(p.y, yMin), yMax))
    }

    /// Returns the corridor/point index of a handle near `location` (screen space).
    private func handleHit(at location: CGPoint, size: CGSize) -> (corridor: Int, point: Int)? {
        let threshold: CGFloat = 24
        for (ci, c) in corridors.enumerated() {
            for (pi, pt) in c.points.enumerated() {
                let s = screen(pt, size)
                if hypot(s.x - location.x, s.y - location.y) <= threshold {
                    return (ci, pi)
                }
            }
        }
        return nil
    }

    /// Returns the id of the corridor whose nearest segment is within tap range.
    private func nearestCorridor(to location: CGPoint, size: CGSize) -> DesignCorridor.ID? {
        let threshold: CGFloat = 24
        var best: (id: DesignCorridor.ID, dist: CGFloat)?
        for c in corridors where c.points.count >= 2 {
            for i in 0..<(c.points.count - 1) {
                let a = screen(c.points[i], size)
                let b = screen(c.points[i + 1], size)
                let d = distanceToSegment(location, a, b)
                if d <= threshold, best == nil || d < best!.dist {
                    best = (c.id, d)
                }
            }
        }
        return best?.id
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}

#Preview {
    NavigationView {
        MapDesignerView()
    }
}
