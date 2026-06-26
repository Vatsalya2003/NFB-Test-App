// FilesListView.swift
// Browse, share, and delete CSV touch logs saved in the app Documents folder.

import SwiftUI

struct FilesListView: View {
    @State private var files: [URL] = []
    @State private var showingDeleteAlert = false
    @State private var fileToDelete: URL?

    var body: some View {
        List {
            if files.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)

                        Text("No log files yet")
                            .font(.headline)
                            .foregroundColor(.gray)

                        Text("Complete a route navigation session to generate data logs.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                Section(header: Text("Saved Log Files")) {
                    ForEach(files, id: \.absoluteString) { file in
                        FileRowView(
                            file: file,
                            onShare: { shareFile(file) },
                            onDelete: { confirmDelete(file) }
                        )
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmDeleteAll()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete All Files")
                        }
                    }
                    .disabled(files.isEmpty)
                }
            }
        }
        .navigationTitle("Data Files")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshFiles()
        }
        .alert("Delete File?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let file = fileToDelete {
                    deleteFile(file)
                }
            }
            Button("Cancel", role: .cancel) {
                fileToDelete = nil
            }
        } message: {
            if let file = fileToDelete {
                Text("Are you sure you want to delete \(file.lastPathComponent)?")
            }
        }
        .refreshable {
            refreshFiles()
        }
    }

    private func refreshFiles() {
        files = DataService.shared.getAllLogFiles()
    }

    private func shareFile(_ file: URL) {
        DataService.shared.shareFile(at: file)
    }

    private func confirmDelete(_ file: URL) {
        fileToDelete = file
        showingDeleteAlert = true
    }

    private func confirmDeleteAll() {
        for file in files {
            _ = DataService.shared.deleteFile(at: file)
        }
        refreshFiles()
    }

    private func deleteFile(_ file: URL) {
        if DataService.shared.deleteFile(at: file) {
            refreshFiles()
        }
        fileToDelete = nil
    }
}

struct FileRowView: View {
    let file: URL
    let onShare: () -> Void
    let onDelete: () -> Void

    private var fileName: String {
        file.deletingPathExtension().lastPathComponent
    }

    private var fileSize: String {
        DataService.shared.getFileSize(at: file)
    }

    private var fileDate: String {
        let components = fileName.split(separator: "_")

        if components.count >= 3 {
            let dateStr = String(components[1])
            let timeStr = String(components[2])

            if dateStr.count == 8 {
                let year = dateStr.prefix(4)
                let month = dateStr.dropFirst(4).prefix(2)
                let day = dateStr.dropFirst(6).prefix(2)

                if timeStr.count == 6 {
                    let hour = timeStr.prefix(2)
                    let minute = timeStr.dropFirst(2).prefix(2)
                    let second = timeStr.dropFirst(4).prefix(2)
                    return "\(year)-\(month)-\(day) \(hour):\(minute):\(second)"
                }

                return "\(year)-\(month)-\(day)"
            }
        }

        return "Unknown date"
    }

    private var sessionLabel: String {
        let name = fileName
        if name.hasPrefix("JWToMarriott") { return "JW Marriott → Austin Marriott" }
        if name.hasPrefix("MarriottToJW") { return "Marriott → JW Marriott" }
        if name.hasPrefix("PracticeNL") { return "Practice - NL" }
        if name.hasPrefix("PracticeSpatial") { return "Practice - Spatial" }
        if name.hasPrefix("PracticeIcons") { return "Practice - Icons" }
        if name.hasPrefix("NL_") || name.hasPrefix("NL") { return "Natural Language" }
        if name.hasPrefix("SpatialAudio") { return "Spatialized Audio" }
        if name.hasPrefix("AuditoryIcons") { return "Auditory Icons" }
        if name.hasPrefix("route_") {
            return String(name.dropFirst(6)).replacingOccurrences(of: "_", with: " ")
        }
        return name.components(separatedBy: "_").first ?? "Session"
    }

    private var sessionVersion: String {
        if let vIndex = fileName.lastIndex(of: "v") {
            return String(fileName.suffix(from: vIndex))
        }
        return ""
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(sessionLabel)
                        .font(.headline)

                    if !sessionVersion.isEmpty {
                        Text(sessionVersion)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                Text(fileDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(fileSize)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share \(sessionLabel) log")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(sessionLabel) log")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sessionLabel) \(sessionVersion), \(fileDate), \(fileSize)")
    }
}

#Preview {
    NavigationStack {
        FilesListView()
    }
}
