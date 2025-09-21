import SwiftUI
import SwiftData
import UIKit

struct MainListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \YouTubeAudio.addedAt, order: .reverse) private var items: [YouTubeAudio]

    @State private var pastedURLText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @StateObject private var downloadService = AudioDownloadService()
    private let service = YouTubeAudioService()

    let thumbnailWidth: CGFloat = 60
    let thumbnailHeight: CGFloat = 60
    
    var body: some View {
        VStack(spacing: 4) {
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
                        HStack(alignment: .top, spacing: 8) {
                                // Thumbnail on the left with duration and download overlays
                                ZStack {
                                    ThumbnailImage(urlString: item.thumbnailURL ?? "", originalURLString: item.originalURL)
                                        .frame(width: thumbnailWidth, height: thumbnailHeight)
                                        .clipped()
                                        .cornerRadius(4)
                                    
                                    // Duration overlay at bottom right of thumbnail
                                    if let duration = item.duration {
                                        VStack {
                                            Spacer()
                                            Text(formatDuration(duration))
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.black.opacity(0.7))
                                                .cornerRadius(2)
                                        }.frame(width: thumbnailWidth, height: thumbnailHeight)
                                    }
                                    
                                    // Download checkmark at top right of thumbnail
                                    if item.isDownloaded {
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .background(Color.white)
                                                    .clipShape(Circle())
                                            }
                                            Spacer()
                                        }.frame(width: thumbnailWidth, height: thumbnailHeight)
                                    }
                                    
                                    // Download progress at top center of thumbnail
                                    if downloadService.isDownloading(item) {
                                        VStack {
                                            HStack {
                                                Spacer()
                                                if let progress = downloadService.downloadProgress[item.id] {
                                                    HStack(spacing: 4) {
                                                        ProgressView()
                                                            .frame(width: 8, height: 8)
                                                        Text("\(Int(progress * 100))%")
                                                            .font(.system(size: 13, weight: .semibold))
                                                            .foregroundColor(.white)
                                                            .padding(.horizontal, 4)
                                                            .padding(.vertical, 2)
                                                    }
                                                    .frame(width: thumbnailWidth * 0.9, height: 20)
                                                    .padding([.horizontal], 5)
                                                    .background(Color.black.opacity(0.7))
                                                    .cornerRadius(2)
                                                } else {
                                                    ProgressView()
                                                        .frame(width: 15, height: 15)
                                                }
                                                Spacer()
                                            }
                                            Spacer()
                                        }.frame(width: thumbnailWidth, height: thumbnailHeight)
                                    }
                                }
                                
                                // Title on the right side of thumbnail
                                Text(item.title ?? "Untitled")
                                .font(.system(size: 13, weight: .regular))
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)
                                
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


