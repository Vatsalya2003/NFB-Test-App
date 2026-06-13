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
                    
                    Text("Route Overlay Study")
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
                    
                    NavigationLink(destination: RouteStudyView()) {
                        StudyOptionButton(
                            title: "Marriott → JW Marriott",
                            description: "Austin downtown grid route",
                            systemImage: "arrow.triangle.turn.up.right.diamond",
                            color: .green
                        )
                    }
                }
                
                Divider()
                    .padding(.horizontal)
                
                // Feedback Customization Tester
                VStack(spacing: 16) {
                    Text("Tools")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
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

struct LegendItem: View {
    let color: Color
    let label: String
    let feedback: String
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
            Text(feedback)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    RouteContentView()
}
