// RouteContentView.swift
// Home screen — pick a route (Marriott ↔ JW) or open dev tools.

import SwiftUI

/// Main entry point for Route Overlay POC app
struct RouteContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("NFB Test")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.top, 20)
                
                Divider()
                    .padding(.horizontal)
                
                // Main Study Options
                VStack(spacing: 16) {
                    Text("Route Navigation")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    NavigationLink(destination: RouteStudyView(
                        title: "JW Marriott → Austin Marriott",
                        routeFile: "route_jwmarriott_to_marriott"
                    )) {
                        StudyOptionButton(
                            title: "JW Marriott → Austin Marriott",
                            description: "East 1st St → Brazos St → East 2nd St",
                            systemImage: "arrow.triangle.turn.up.right.diamond",
                            color: .blue
                        )
                    }

                    NavigationLink(destination: RouteStudyView(
                        title: "Marriott → JW Marriott",
                        routeFile: "route_marriott_to_jwmarriott"
                    )) {
                        StudyOptionButton(
                            title: "Marriott → JW Marriott",
                            description: "East 2nd St → Brazos St → East 1st St",
                            systemImage: "arrow.triangle.turn.up.right.diamond",
                            color: .green
                        )
                    }
                }
                
                Divider()
                    .padding(.horizontal)
                
                // Tools
                VStack(spacing: 16) {
                    Text("Tools")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    NavigationLink(destination: FilesListView()) {
                        StudyOptionButton(
                            title: "Data Files",
                            description: "View, share, and delete CSV touch logs",
                            systemImage: "doc.text",
                            color: .teal
                        )
                    }

                    NavigationLink(destination: FeedbackCustomizationTesterView()) {
                        StudyOptionButton(
                            title: "Feedback Customization Tester",
                            description: "Preview and assign haptic patterns to map elements",
                            systemImage: "waveform.path",
                            color: .purple
                        )
                    }

                    NavigationLink(destination: MapDesignerView()) {
                        StudyOptionButton(
                            title: "Map Designer",
                            description: "Draw corridors on a grid and export JSON",
                            systemImage: "pencil.and.ruler",
                            color: .orange
                        )
                    }
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .disableInteractivePopGesture()
        }
    }
}

// MARK: - Supporting Views

struct StudyOptionButton: View {
    let title: String
    let description: String
    let systemImage: String
    var color: Color = .blue
    
    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 50)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

// MARK: - Preview

#Preview {
    RouteContentView()
}
