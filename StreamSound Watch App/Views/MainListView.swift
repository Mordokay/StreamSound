import SwiftUI
import SwiftData

struct MainListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \YouTubeAudio.addedAt, order: .reverse) private var items: [YouTubeAudio]

    @State private var pastedURLText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @StateObject private var downloadService = AudioDownloadService()
    private let service = YouTubeAudioService()

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("Paste YouTube URL", text: $pastedURLText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button(action: addFromPaste) {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(isLoading || pastedURLText.isEmpty)
            }
            if isLoading { ProgressView().scaleEffect(0.8) }
            if let errorMessage { Text(errorMessage).font(.caption2).foregroundStyle(.red) }

            List {
                ForEach(items) { item in
                    NavigationLink(destination: AudioPlayerView(audio: item)) {
                        HStack(spacing: 8) {
                            // Thumbnail on the left
                            ThumbnailImage(urlString: item.thumbnailURL ?? "", originalURLString: item.originalURL)
                                .frame(width: 50, height: 50)
                                .clipped()
                                .cornerRadius(4)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                // Title on the right
                                Text(item.title ?? "Untitled")
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                // Duration below thumbnail
                                if let duration = item.duration {
                                    Text(formatDuration(duration))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                // Download status indicator
                                if item.isDownloaded {
                                    HStack(spacing: 2) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption2)
                                        Text("Downloaded")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                } else if downloadService.isDownloading(item) {
                                    HStack(spacing: 2) {
                                        ProgressView()
                                            .scaleEffect(0.4)
                                        Text("Downloading...")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Delete button (always available)
                        Button(role: .destructive, action: { deleteItem(item) }) {
                            Label("Delete", systemImage: "trash.fill")
                        }
                        
                        // Download/Delete local file button
                        if item.isDownloaded {
                            Button(action: { downloadService.deleteLocalFile(for: item) }) {
                                Label("Remove Download", systemImage: "arrow.up.circle.fill")
                            }
                            .tint(.orange)
                        } else if !downloadService.isDownloading(item) {
                            Button(action: { 
                                Task { 
                                    try? await downloadService.downloadAudio(for: item) 
                                } 
                            }) {
                                Label("Download", systemImage: "arrow.down.circle.fill")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .contentMargins(.zero)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func addFromPaste() {
        let trimmed = pastedURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Normalize input: accept full URL or bare 11-char video ID
        let normalizedURLString: String
        if let url = URL(string: trimmed), url.scheme != nil {
            normalizedURLString = trimmed
        } else if isYouTubeVideoID(trimmed) {
            normalizedURLString = "https://www.youtube.com/watch?v=\(trimmed)"
        } else {
            errorMessage = "Invalid URL or ID"
            return
        }
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            do {
                let info = try await service.fetchInfo(for: normalizedURLString)
                if let yt = YouTubeAudio.from(info: info) {
                    modelContext.insert(yt)
                    try? modelContext.save()
                    pastedURLText = ""
                } else {
                    errorMessage = "Server returned no stream"
                }
            } catch {
                errorMessage = "Failed to fetch"
            }
            isLoading = false
        }
    }

    private func isYouTubeVideoID(_ text: String) -> Bool {
        // Standard YouTube IDs are 11 chars of URL-safe base64-ish charset
        let pattern = "^[A-Za-z0-9_-]{11}$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func deleteItem(_ item: YouTubeAudio) {
        // Delete local file if it exists
        downloadService.deleteLocalFile(for: item)
        // Delete from database
        modelContext.delete(item)
        try? modelContext.save()
    }
}


